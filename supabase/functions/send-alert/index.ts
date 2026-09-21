const MAX_BODY_BYTES = 16 * 1024;
const MAX_TOKENS = 10;
const MAX_TOKEN_LENGTH = 4096;
const MAX_TEXT_LENGTH = 256;
const ALLOWED_EVENTS = new Set([
  'Distress Sound', 'Distress Sound + Impact', 'Possible Distress Sound',
  'Emergency Alarm', 'Impact / Breaking Sound', 'Manual Silent Alert',
  'Ambient Sound', 'Live Detector Event', 'SUNO preflight',
]);
const ALLOWED_RESPONSE_STATUSES = new Set(['contactChecking', 'resolved', 'alertTriggered']);
const encoder = new TextEncoder();

type Delivery = { token: string; message: Record<string, unknown> };

export async function handleRequest(req: Request): Promise<Response> {
  const projectId = Deno.env.get('FIREBASE_PROJECT_ID');
  const clientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL');
  const privateKey = Deno.env.get('FIREBASE_PRIVATE_KEY')?.replace(/\\n/g, '\n');
  const relayKey = Deno.env.get('SUNO_RELAY_AUTH_KEY')?.trim();
  if (req.method === 'GET') {
    return json({ ok: true, service: 'suno-send-alert', firebaseConfigured: Boolean(projectId && clientEmail && privateKey && relayKey) });
  }
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  if (!relayKey) return json({ error: 'Relay authentication is not configured' }, 503);
  if (!constantTimeEqual(req.headers.get('x-suno-relay-key') ?? '', relayKey)) {
    return json({ error: 'Unauthorized' }, 401);
  }
  let body: Record<string, unknown>;
  try {
    const decoded: unknown = JSON.parse(await readBody(req));
    if (!isRecord(decoded)) return json({ error: 'Invalid payload' }, 400);
    body = decoded;
  } catch (error) {
    const status = error instanceof BodyError ? error.status : 400;
    return json({ error: status === 413 ? 'Payload too large' : 'Invalid or incomplete JSON body' }, status);
  }
  if ('cancelIncidentId' in body) {
    if (!text(body.cancelIncidentId, 128)) return json({ error: 'Invalid incident ID' }, 400);
    return json({ ok: true, cancelled: body.cancelIncidentId });
  }
  const deliveries: Delivery[] = [];
  const android = { priority: 'HIGH', notification: { channel_id: 'suno_alerts_v2', sound: 'default', default_vibrate_timings: true } };
  if ('response' in body) {
    const r = body.response;
    if (!isRecord(r) || !token(r.recipientToken) || !text(r.incidentId, 128) ||
        !text(r.responderName) || !text(r.message) || typeof r.status !== 'string' ||
        !ALLOWED_RESPONSE_STATUSES.has(r.status)) {
      return json({ error: 'Invalid response payload' }, 400);
    }
    deliveries.push({ token: r.recipientToken.trim(), message: {
      notification: { title: 'SUNO contact response', body: `${r.responderName}: ${r.message}` },
      data: { type: 'response', incidentId: r.incidentId, responderName: r.responderName, status: r.status, message: r.message },
      android,
    } });
  } else {
    if (!Array.isArray(body.contactTokens) || body.contactTokens.length > MAX_TOKENS ||
        !body.contactTokens.every(token)) return json({ error: 'Invalid contact tokens' }, 400);
    if (!isRecord(body.payload) || ('test' in body && typeof body.test !== 'boolean')) return json({ error: 'Invalid payload' }, 400);
    const payload = body.payload;
    if (Object.keys(payload).length > 16 || Object.entries(payload).some(([key, value]) =>
      key.length > 64 || typeof value !== 'string' || value.length > (key === 'senderToken' ? MAX_TOKEN_LENGTH : MAX_TEXT_LENGTH) ||
      key.startsWith('google.') || key.startsWith('gcm.') || ['from', 'message_type', 'collapse_key'].includes(key))) {
      return json({ error: 'Invalid payload' }, 400);
    }
    const isTest = body.test === true;
    if (isTest ? payload.type !== 'test' :
        !text(payload.incidentId, 128) || typeof payload.eventType !== 'string' || !ALLOWED_EVENTS.has(payload.eventType) ||
        typeof payload.riskScore !== 'string' || !/^\d{1,3}$/.test(payload.riskScore) || Number(payload.riskScore) > 100 ||
        !['low', 'medium', 'critical'].includes(String(payload.riskLevel)) ||
        typeof payload.detectedAt !== 'string' || !Number.isFinite(Date.parse(payload.detectedAt))) {
      return json({ error: 'Invalid alert payload' }, 400);
    }
    if ((!isTest && payload.type !== undefined) ||
        (payload.senderToken !== undefined && !token(payload.senderToken)) ||
        (payload.isSimulated !== undefined && !['true', 'false'].includes(String(payload.isSimulated)))) {
      return json({ error: 'Invalid alert metadata' }, 400);
    }
    if ('latitude' in payload || 'longitude' in payload) {
      if (!coordinate(payload.latitude, 90) || !coordinate(payload.longitude, 180)) return json({ error: 'Invalid coordinates' }, 400);
    }
    const tokens = [...new Set((body.contactTokens as string[]).map((value) => value.trim()))];
    for (const recipient of tokens) deliveries.push({ token: recipient, message: {
      ...(isTest ? {} : { notification: {
        title: payload.isSimulated === 'true' ? 'SUNO simulated emergency' : 'SUNO emergency alert',
        body: `${payload.eventType} · Risk ${payload.riskScore}%`,
      } }),
      data: payload, android: isTest ? { priority: 'HIGH' } : android,
    } });
  }
  if (deliveries.some(({ message }) => encoder.encode(JSON.stringify(message)).length > 4096)) {
    return json({ error: 'FCM message is too large' }, 413);
  }
  if (deliveries.length === 0) return json({ ok: true, sent: 0, attempted: 0, results: [] });
  if (!projectId || !clientEmail || !privateKey) return json({ error: 'Firebase is not configured' }, 503);
  try {
    const accessToken = await getAccessToken(clientEmail, privateKey);
    const results = await Promise.all(deliveries.map(async ({ token, message }) => {
      try {
        const response = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
          method: 'POST', signal: AbortSignal.timeout(8000),
          headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ message: { token, ...message } }),
        });
        await response.body?.cancel();
        return { ok: response.ok, status: response.status };
      } catch (_) {
        return { ok: false, status: 502 };
      }
    }));
    return json({ ok: results.every((r) => r.ok), sent: results.filter((r) => r.ok).length, attempted: results.length, results });
  } catch (_) {
    return json({ error: 'Push service unavailable' }, 502);
  }
}

class BodyError extends Error {
  constructor(readonly status: number) { super('Invalid request body'); }
}

async function readBody(req: Request): Promise<string> {
  if (Number(req.headers.get('content-length')) > MAX_BODY_BYTES) throw new BodyError(413);
  const reader = req.body?.getReader();
  if (!reader) throw new BodyError(400);
  const chunks: Uint8Array[] = [];
  let length = 0;
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    await Promise.race([
      (async () => {
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          length += value.length;
          if (length > MAX_BODY_BYTES) throw new BodyError(413);
          chunks.push(value);
        }
      })(),
      new Promise<never>((_, reject) => { timeout = setTimeout(() => reject(new BodyError(408)), 5000); }),
    ]);
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } finally {
    clearTimeout(timeout);
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function text(value: unknown, maximum = MAX_TEXT_LENGTH): value is string {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= maximum;
}
function token(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length >= 21 && value.length <= MAX_TOKEN_LENGTH;
}
function coordinate(value: unknown, maximum: number): boolean {
  return typeof value === 'string' && value.trim() !== '' && Number.isFinite(Number(value)) && Math.abs(Number(value)) <= maximum;
}
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}
function constantTimeEqual(left: string, right: string): boolean {
  const a = encoder.encode(left), b = encoder.encode(right);
  let difference = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) difference |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return difference === 0;
}
async function getAccessToken(email: string, key: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${base64Url(JSON.stringify({
    iss: email, scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600,
  }))}`;
  const cryptoKey = await crypto.subtle.importKey('pkcs8', pemToArrayBuffer(key), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, encoder.encode(unsigned));
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', signal: AbortSignal.timeout(8000),
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${base64Url(signature)}` }),
  });
  if (!response.ok) { await response.body?.cancel(); throw new Error('OAuth failed'); }
  const decoded = await response.json();
  if (!text(decoded.access_token, 8192)) throw new Error('Invalid OAuth result');
  return decoded.access_token;
}
function pemToArrayBuffer(pem: string): ArrayBuffer {
  const binary = atob(pem.replace('-----BEGIN PRIVATE KEY-----', '').replace('-----END PRIVATE KEY-----', '').replace(/\s/g, ''));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}
function base64Url(input: string | ArrayBuffer): string {
  const bytes = typeof input === 'string' ? encoder.encode(input) : new Uint8Array(input);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

if (import.meta.main) Deno.serve(handleRequest);
