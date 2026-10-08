import { handleRequest } from './index.ts';

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}
const fakeToken = 'synthetic-test-recipient-not-a-real-fcm-token';
const payload = {
  incidentId: 'test-incident', eventType: 'Distress Sound', riskScore: '95',
  riskLevel: 'critical', detectedAt: '2026-09-21T12:00:00Z', isSimulated: 'true',
  latitude: '33.6844', longitude: '73.0479', senderToken: 'x'.repeat(320),
};
function request(body: unknown, key = 'local-test-key') {
  return new Request('http://localhost/send-alert', { method: 'POST',
    headers: { 'x-suno-relay-key': key }, body: JSON.stringify(body) });
}

Deno.test('local relay validation and mocked upstream delivery', async (t) => {
  const names = ['SUNO_RELAY_AUTH_KEY', 'FIREBASE_PROJECT_ID', 'FIREBASE_CLIENT_EMAIL', 'FIREBASE_PRIVATE_KEY'];
  const before = names.map((name) => Deno.env.get(name));
  const originalFetch = globalThis.fetch;
  let calls = 0;
  try {
    globalThis.fetch = () => { calls++; throw new Error('Unexpected network request'); };
    Deno.env.delete('SUNO_RELAY_AUTH_KEY');
    await t.step('fails closed without authentication configuration', async () => {
      equal((await handleRequest(request({}))).status, 503);
    });
    Deno.env.set('SUNO_RELAY_AUTH_KEY', 'local-test-key');
    await t.step('rejects incorrect authentication', async () => {
      equal((await handleRequest(request({}, 'wrong'))).status, 401);
    });
    await t.step('validates before OAuth including sender token and coordinates', async () => {
      for (const invalid of [null, [], { contactTokens: [12], payload },
        { contactTokens: [fakeToken], payload: { ...payload, latitude: 'NaN' } },
        { contactTokens: [fakeToken], payload: { ...payload, riskScore: '101' } },
        { response: { incidentId: 'test' } },
      ]) equal((await handleRequest(request(invalid))).status, 400);
      equal(calls, 0);
    });
    await t.step('limits streamed bodies without Content-Length', async () => {
      const stream = new ReadableStream<Uint8Array>({ start(controller) {
        controller.enqueue(new Uint8Array(9000)); controller.enqueue(new Uint8Array(9000)); controller.close();
      } });
      const response = await handleRequest(new Request('http://localhost/send-alert', {
        method: 'POST', headers: { 'x-suno-relay-key': 'local-test-key' }, body: stream,
      }));
      equal(response.status, 413);
      equal(calls, 0);
    });
    const pair = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
    const bytes = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
    let binary = '';
    for (const byte of bytes) binary += String.fromCharCode(byte);
    Deno.env.set('FIREBASE_PROJECT_ID', 'local-test-project');
    Deno.env.set('FIREBASE_CLIENT_EMAIL', 'test@example.invalid');
    Deno.env.set('FIREBASE_PRIVATE_KEY', `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----`);
    const messages: Record<string, unknown>[] = [];
    globalThis.fetch = async (input, init) => {
      if (String(input).includes('oauth2.googleapis.com')) return Response.json({ access_token: 'synthetic-oauth-token' });
      const message = JSON.parse(String(init?.body)).message;
      messages.push(message);
      if (message.token === 'failed-recipient-token-for-local-test') throw new Error('Offline');
      return new Response('{}', { status: 200 });
    };
    await t.step('deduplicates tokens, accepts long sender tokens, preserves partial results', async () => {
      const response = await handleRequest(request({ contactTokens: [fakeToken, ` ${fakeToken} `, 'failed-recipient-token-for-local-test'], payload }));
      equal(response.status, 200);
      const body = await response.json();
      equal([body.sent, body.attempted, body.ok], [1, 2, false]);
      equal(messages.length, 2);
      const notification = (messages[0].android as Record<string, unknown>).notification as Record<string, unknown>;
      equal(notification.channel_id, 'suno_alerts_v2');
      equal(notification.click_action, undefined);
      equal((messages[0].data as Record<string, string>).senderToken.length, 320);
    });
    await t.step('motion-only safety escalation accepts the emitted ambient label', async () => {
      messages.length = 0;
      const response = await handleRequest(request({ contactTokens: [fakeToken],
        payload: { ...payload, eventType: 'Ambient Sound', riskScore: '65', riskLevel: 'medium' } }));
      equal(response.status, 200);
      equal((await response.json()).sent, 1);
      equal((messages[0].data as Record<string, unknown>).eventType, 'Ambient Sound');
    });
    await t.step('names the sender in the tray title and rejects unusable names', async () => {
      messages.length = 0;
      const named = await handleRequest(request({ contactTokens: [fakeToken],
        payload: { ...payload, isSimulated: 'false', senderName: 'Ayan' } }));
      equal(named.status, 200);
      equal((messages[0].notification as Record<string, unknown>).title, 'Ayan may be in danger');
      messages.length = 0;
      const anonymous = await handleRequest(request({ contactTokens: [fakeToken],
        payload: { ...payload, isSimulated: 'false' } }));
      equal(anonymous.status, 200);
      equal((messages[0].notification as Record<string, unknown>).title, 'SUNO emergency alert');
      for (const invalid of ['x'.repeat(65), '']) {
        equal((await handleRequest(request({ contactTokens: [fakeToken],
          payload: { ...payload, senderName: invalid } }))).status, 400);
      }
      equal(messages.length, 1);
    });
    await t.step('builds the banner in the sender language and falls back to English', async () => {
      messages.length = 0;
      const arabic = await handleRequest(request({ contactTokens: [fakeToken],
        payload: { ...payload, isSimulated: 'false', senderName: 'Ayan', languageCode: 'ar' } }));
      equal(arabic.status, 200);
      const banner = messages[0].notification as Record<string, unknown>;
      equal(banner.title, 'قد يكون Ayan في خطر');
      equal(banner.body, 'صوت استغاثة · خطر 95%');
      messages.length = 0;
      const unsupported = await handleRequest(request({ contactTokens: [fakeToken],
        payload: { ...payload, isSimulated: 'false', languageCode: 'pt' } }));
      equal(unsupported.status, 200);
      equal((messages[0].notification as Record<string, unknown>).title, 'SUNO emergency alert');
      equal((messages[0].data as Record<string, unknown>).languageCode, 'pt');
    });
    await t.step('prefers lang over languageCode and never blocks on an unknown code', async () => {
      messages.length = 0;
      const spanish = await handleRequest(request({ contactTokens: [fakeToken],
        payload: { ...payload, isSimulated: 'false', senderName: 'Ali', lang: 'es', languageCode: 'ar' } }));
      equal(spanish.status, 200);
      equal((messages[0].notification as Record<string, unknown>).title, 'Ali puede estar en peligro');
      equal((messages[0].data as Record<string, unknown>).lang, 'es');
      messages.length = 0;
      const legacyOnly = await handleRequest(request({ contactTokens: [fakeToken],
        payload: { ...payload, isSimulated: 'false', senderName: 'Ali', languageCode: 'ar' } }));
      equal(legacyOnly.status, 200);
      equal((messages[0].notification as Record<string, unknown>).title, 'قد يكون Ali في خطر');
      messages.length = 0;
      const unknown = await handleRequest(request({ contactTokens: [fakeToken],
        payload: { ...payload, isSimulated: 'false', senderName: 'Ali', lang: 'pt' } }));
      equal(unknown.status, 200);
      equal((messages[0].notification as Record<string, unknown>).title, 'Ali may be in danger');
    });
    await t.step('silent tests have no notification content', async () => {
      messages.length = 0;
      equal((await handleRequest(request({ contactTokens: [fakeToken], payload: { type: 'test' }, test: true }))).status, 200);
      equal(messages[0].notification, undefined);
      equal((messages[0].android as Record<string, unknown>).notification, undefined);
    });
    await t.step('responses target one incident and use the current channel', async () => {
      messages.length = 0;
      const response = await handleRequest(request({ response: { recipientToken: fakeToken,
        incidentId: 'old-incident', responderName: 'Your contact', status: 'resolved', message: 'They are safe' } }));
      equal((await response.json()).sent, 1);
      equal((messages[0].data as Record<string, unknown>).incidentId, 'old-incident');
    });
    await t.step('titles the reply banner in the sender language and keeps English without it', async () => {
      messages.length = 0;
      const spanish = await handleRequest(request({ response: { recipientToken: fakeToken,
        incidentId: 'spanish-incident', responderName: 'Ali', status: 'resolved',
        message: 'Están a salvo', lang: 'es' } }));
      equal(spanish.status, 200);
      const banner = messages[0].notification as Record<string, unknown>;
      equal(banner.title, 'Respuesta de un contacto de SUNO');
      equal(banner.body, 'Ali: Están a salvo');
      equal((messages[0].data as Record<string, unknown>).incidentId, 'spanish-incident');
      for (const lang of [undefined, 'pt']) {
        messages.length = 0;
        const reply = await handleRequest(request({ response: { recipientToken: fakeToken,
          incidentId: 'english-incident', responderName: 'Your contact', status: 'resolved',
          message: 'They are safe', lang } }));
        equal(reply.status, 200);
        equal((messages[0].notification as Record<string, unknown>).title, 'SUNO contact response');
      }
    });
    await t.step('OAuth failure is bounded and has no credential-bearing response', async () => {
      globalThis.fetch = () => Promise.reject(new Error('sensitive-upstream-value'));
      const response = await handleRequest(request({ contactTokens: [fakeToken], payload }));
      equal(response.status, 502);
      equal(await response.json(), { error: 'Push service unavailable' });
    });
  } finally {
    globalThis.fetch = originalFetch;
    names.forEach((name, index) => {
      const value = before[index];
      if (value === undefined) Deno.env.delete(name); else Deno.env.set(name, value);
    });
  }
});
