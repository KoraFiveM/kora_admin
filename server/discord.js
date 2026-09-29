'use strict';

const crypto = require('node:crypto');
const http = require('node:http');
const https = require('node:https');

// Use the bundled Node runtime; enabling Discord needs no npm dependencies.
function requestJson(url, { method, headers, body, timeoutMs = 10000 }) {
    return new Promise((resolve, reject) => {
        const endpoint = new URL(url);
        const transport = endpoint.protocol === 'https:' ? https : http;
        if (!['https:', 'http:'].includes(endpoint.protocol)) return reject(new Error('Unsupported protocol'));
        const req = transport.request(endpoint, { method, headers: {
            'User-Agent': 'DiscordBot (https://github.com/qbcore2, 1.0)', ...headers,
        } }, res => {
            let text = '', size = 0;
            res.setEncoding('utf8');
            res.on('data', chunk => {
                size += Buffer.byteLength(chunk);
                if (size > 65536) return req.destroy(new Error('Response too large'));
                text += chunk;
            });
            res.on('error', reject);
            res.on('end', () => resolve({
                ok: res.statusCode >= 200 && res.statusCode < 300, status: res.statusCode,
                headers: { getSetCookie: () => res.headers['set-cookie'] || [] },
                json: async () => JSON.parse(text),
            }));
        });
        const timer = setTimeout(() => req.destroy(new Error('HTTP request timed out')), timeoutMs);
        req.on('close', () => clearTimeout(timer));
        req.on('error', reject);
        req.end(body);
    });
}

function verifyInteraction(publicKey, timestamp, signature, body, now = Date.now()) {
    if (!/^[a-f\d]{64}$/i.test(publicKey) || !/^\d{1,12}$/.test(timestamp)
        || !/^[a-f\d]{128}$/i.test(signature) || Math.abs(now / 1000 - Number(timestamp)) > 300) return false;
    try {
        const key = crypto.createPublicKey({ format: 'der', type: 'spki',
            key: Buffer.from('302a300506032b6570032100' + publicKey, 'hex') });
        return crypto.verify(null, Buffer.concat([Buffer.from(timestamp), Buffer.from(body)]), key, Buffer.from(signature, 'hex'));
    } catch { return false; }
}

async function restartTxAdmin({ url, username, password }, request = requestJson) {
    const base = new URL(url);
    if (!['http:', 'https:'].includes(base.protocol) || base.username || base.password
        || base.pathname !== '/' || base.search || base.hash
        || (base.protocol === 'http:' && !['127.0.0.1', 'localhost', '[::1]'].includes(base.hostname))) {
        throw new Error('txAdmin URL must be a local HTTP or remote HTTPS origin');
    }
    const login = await request(new URL('/auth/password', base), {
        method: 'POST',
        headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username, password }),
    });
    if (!login.ok) throw new Error('txAdmin authentication request failed');
    const auth = await login.json();
    const cookies = login.headers.getSetCookie().map(cookie => cookie.split(';')[0]).join('; ');
    if (auth.error || auth.logout || !auth.csrfToken || !cookies) throw new Error('txAdmin authentication failed');
    const result = await request(new URL('/fxserver/controls', base), {
        method: 'POST', timeoutMs: 20000,
        headers: { 'content-type': 'application/json', cookie: cookies, 'x-txadmin-csrftoken': auth.csrfToken },
        body: JSON.stringify({ action: 'restart' }),
    });
    if (!result.ok) throw new Error('txAdmin did not confirm the restart');
    const data = await result.json();
    if (!['success', 'warning'].includes(data.type) || data.logout || data.error) {
        throw new Error('txAdmin refused the restart; check control.server permission and server logs');
    }
    return 'txAdmin accepted the server restart';
}

function createHttpHandler({ settings, dispatch, request = requestJson, now = Date.now, report = console.error }) {
    const seen = new Map();
    return (req, res) => {
        let responded = false;
        const send = (status, payload) => {
            if (responded) return;
            responded = true;
            res.writeHead(status, { 'Content-Type': 'application/json' });
            res.send(JSON.stringify(payload));
        };
        if (req.path !== '/discord/interactions' || req.method !== 'POST') return send(404, { error: 'Not found' });
        if (Number(req.headers['content-length']) > 65536) return send(413, { error: 'Request too large' });
        req.setDataHandler(body => {
            try {
                const config = settings();
                if (Buffer.byteLength(body) > 65536) return send(413, { error: 'Request too large' });
                if (!verifyInteraction(config.publicKey, req.headers['x-signature-timestamp'], req.headers['x-signature-ed25519'], body, now())) {
                    return send(401, { error: 'Invalid signature' });
                }
                const interaction = JSON.parse(body);
                if (interaction.type === 1) return send(200, { type: 1 });
                if (!config.enabled || interaction.application_id !== config.applicationId) return send(403, { error: 'Disabled' });
                if (interaction.type !== 2 || !/^\d+$/.test(interaction.id)
                    || typeof interaction.token !== 'string' || interaction.token.length === 0
                    || interaction.token.length > 2048) return send(400, { error: 'Invalid interaction' });
                // Signed retries receive the same acknowledgement without re-running an action.
                for (const [id, expiry] of seen) if (expiry <= now()) seen.delete(id);
                const ack = { type: 5, data: { flags: 64 } };
                if (seen.has(interaction.id)) return send(200, ack);
                if (seen.size >= 10000) return send(503, { error: 'Busy' });
                seen.set(interaction.id, now() + 600000);
                send(200, ack);
                let finished = false;
                const reply = async result => {
                    if (finished) return;
                    finished = true;
                    clearTimeout(timeout);
                    const payload = {
                        content: String(result.message || 'Command completed').slice(0, 1900),
                        allowed_mentions: { parse: [] },
                        embeds: [{ title: result.ok ? 'Administration complete' : 'Administration refused',
                            color: result.ok ? 0x22c55e : 0xef4444,
                            footer: { text: `Request ${interaction.id}` } }],
                    };
                    try {
                        const response = await request(`https://discord.com/api/v10/webhooks/${config.applicationId}/${encodeURIComponent(interaction.token)}/messages/@original`, {
                            method: 'PATCH',
                            headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload),
                        });
                        if (!response.ok) report(`Discord response failed (HTTP ${response.status}) for request ${interaction.id}`);
                    } catch { report(`Discord response could not be delivered for request ${interaction.id}`); }
                };
                const timeout = setTimeout(() => void reply({ ok: false,
                    message: 'The command has not returned. Check the audit log before retrying.' }), 120000);
                try {
                    if (dispatch(body, encoded => {
                        try { void reply(JSON.parse(encoded)); }
                        catch { void reply({ ok: false, message: 'Invalid command result; check the audit log' }); }
                    }) !== true) {
                        void reply({ ok: false, message: 'The Discord command dispatcher is unavailable' });
                    }
                } catch {
                    void reply({ ok: false, message: 'The Discord command dispatcher failed' });
                }
            } catch { send(400, { error: 'Invalid request' }); }
        });
    };
}

if (typeof GetCurrentResourceName === 'function') {
    const resource = GetCurrentResourceName();
    SetHttpHandler(createHttpHandler({
        settings: () => JSON.parse(global.exports[resource].discordSettings()),
        dispatch: (body, callback) => global.exports[resource].discordDispatch(body, callback),
        report: message => console.error(`[qbadmin:discord] ${message}`),
    }));
    const restartConfig = () => ({
        url: GetConvar('qbadmin_txadmin_url', 'http://127.0.0.1:40120'),
        username: GetConvar('qbadmin_txadmin_username', ''),
        password: GetConvar('qbadmin_txadmin_password', ''),
    });
    global.exports('discordRestartReady', () => {
        const config = restartConfig();
        return Boolean(config.username && config.password);
    });
    global.exports('discordRestart', callback => {
        if (GetInvokingResource() !== resource) return false;
        restartTxAdmin(restartConfig()).then(message => setImmediate(() => callback(true, message)))
            .catch(() => setImmediate(() => callback(false,
                'txAdmin did not confirm the restart. Check its credentials, control.server permission, and logs.')));
        return true;
    });
}

if (typeof module !== 'undefined') module.exports = { verifyInteraction, restartTxAdmin, createHttpHandler };
