'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const http = require('node:http');
const { verifyInteraction, createHttpHandler, restartTxAdmin } = require('../server/discord');

const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
const key = publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('hex');
const now = 1800000000000;
const timestamp = String(now / 1000);
const sign = body => crypto.sign(null, Buffer.from(timestamp + body), privateKey).toString('hex');

test('signatures bind the exact body and timestamp, and reject old/malformed requests', () => {
    const body = '{"type":1}';
    assert.equal(verifyInteraction(key, timestamp, sign(body), body, now), true);
    assert.equal(verifyInteraction(key, timestamp, sign(body), body + ' ', now), false);
    assert.equal(verifyInteraction(key, timestamp, sign(body), body, now + 301000), false);
    assert.equal(verifyInteraction(key, timestamp, undefined, body, now), false);
    assert.equal(verifyInteraction(key, timestamp, '0'.repeat(128), body, now), false);
});

test('HTTP accepts signed pings and executes a signed command once with private replies', async () => {
    let calls = 0;
    const patches = [];
    const handler = createHttpHandler({
        now: () => now,
        settings: () => ({ enabled: true, publicKey: key, applicationId: '900' }),
        dispatch: (_, callback) => { calls++; callback(JSON.stringify({ ok: true, message: '@everyone done' })); return true; },
        request: async (url, options) => { patches.push({ url, ...options }); return { ok: true }; },
    });
    function send(interaction, signature) {
        const body = JSON.stringify(interaction);
        let status, result;
        handler({ path: '/discord/interactions', method: 'POST', headers: {
            'x-signature-timestamp': timestamp, 'x-signature-ed25519': signature || sign(body),
        }, setDataHandler: callback => callback(body) }, {
            writeHead: code => { status = code; }, send: encoded => { result = JSON.parse(encoded); },
        });
        return { status, result };
    }
    assert.deepEqual(send({ type: 1 }), { status: 200, result: { type: 1 } });
    const command = { type: 2, id: '100', application_id: '900', token: 'test_token' };
    assert.equal(send(command, '0'.repeat(128)).status, 401);
    assert.equal(calls, 0);
    assert.equal(send(command).result.data.flags, 64);
    assert.equal(send(command).status, 200);
    assert.equal(calls, 1);
    assert.equal(send({ ...command, id: '101', application_id: '901' }).status, 403);
    assert.equal(send({ ...command, id: '102', token: null }).status, 400);
    assert.equal(send({ ...command, id: '103', token: 'opaque/with=padding' }).status, 200);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(patches.length, 2);
    assert.match(patches[1].url, /opaque%2Fwith%3Dpadding/);
    assert.equal(patches[0].method, 'PATCH');
    assert.deepEqual(JSON.parse(patches[0].body).allowed_mentions, { parse: [] });
});

test('txAdmin restart uses an authenticated cookie and CSRF token; failures never retry controls', async () => {
    const calls = [];
    const request = async (url, options) => {
        calls.push({ url: String(url), ...options });
        return calls.length === 1
            ? { ok: true, headers: { getSetCookie: () => ['session=opaque; HttpOnly', 'session.sig=signature; HttpOnly'] },
                json: async () => ({ csrfToken: 'csrf' }) }
            : { ok: true, json: async () => ({ type: 'success' }) };
    };
    const config = { url: 'http://127.0.0.1:40120', username: 'discord-service', password: 'placeholder' };
    assert.match(await restartTxAdmin(config, request), /accepted/);
    assert.equal(calls[0].url, config.url + '/auth/password');
    assert.equal(calls[1].url, config.url + '/fxserver/controls');
    assert.equal(calls[1].headers.cookie, 'session=opaque; session.sig=signature');
    assert.equal(calls[1].headers['x-txadmin-csrftoken'], 'csrf');
    assert.deepEqual(JSON.parse(calls[1].body), { action: 'restart' });
    let attempts = 0;
    await assert.rejects(restartTxAdmin(config, async () => {
        attempts++;
        return { ok: true, headers: { getSetCookie: () => [] }, json: async () => ({ error: 'denied' }) };
    }), /authentication failed/);
    assert.equal(attempts, 1);
    await assert.rejects(restartTxAdmin({ ...config, url: 'http://example.com' }, request), /local HTTP/);
});

test('the bundled-runtime HTTP client works against a real local txAdmin-shaped endpoint', async t => {
    const paths = [];
    const server = http.createServer((req, res) => {
        paths.push(req.url);
        let body = '';
        req.on('data', chunk => { body += chunk; });
        req.on('end', () => {
            res.setHeader('Content-Type', 'application/json');
            if (req.url === '/auth/password') {
                assert.equal(JSON.parse(body).username, 'service');
                res.setHeader('Set-Cookie', ['session=test; HttpOnly']);
                res.end(JSON.stringify({ csrfToken: 'test-csrf' }));
            } else {
                assert.equal(req.headers.cookie, 'session=test');
                assert.equal(req.headers['x-txadmin-csrftoken'], 'test-csrf');
                assert.deepEqual(JSON.parse(body), { action: 'restart' });
                res.end(JSON.stringify({ type: 'success' }));
            }
        });
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    t.after(() => new Promise(resolve => server.close(resolve)));
    assert.match(await restartTxAdmin({ url: `http://127.0.0.1:${server.address().port}`, username: 'service', password: 'test' }), /accepted/);
    assert.deepEqual(paths, ['/auth/password', '/fxserver/controls']);
});
