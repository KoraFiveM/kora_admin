const MEDAL_ENDPOINT = 'http://localhost:12665/api/v1/event/invoke';

async function reportResult(result) {
    try {
        await fetch(`https://${GetParentResourceName()}/qbadmin:medal:result`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(result),
        });
    } catch (error) {
        console.error('Could not return the Medal result to qbadmin', error);
    }
}

window.addEventListener('message', async ({ data }) => {
    if (!data || data.type !== 'qbadmin:medal:invoke') return;

    const timeoutMs = Math.min(Math.max(Number(data.timeoutMs) || 5000, 1000), 30000);
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), timeoutMs);

    try {
        const response = await fetch(MEDAL_ENDPOINT, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json; charset=utf-8',
                publicKey: String(data.publicKey || ''),
            },
            body: JSON.stringify(data.body),
            signal: controller.signal,
        });
        await reportResult({ requestId: data.requestId, ok: response.ok, status: response.status });
    } catch {
        await reportResult({ requestId: data.requestId, ok: false, status: 0 });
    } finally {
        window.clearTimeout(timeout);
    }
});
