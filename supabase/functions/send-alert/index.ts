type AlertPayload = {
  contactTokens?: string[];
  payload?: Record<string, string>;
  cancelIncidentId?: string;
  test?: boolean;
  response?: {
    recipientToken: string;
    incidentId: string;
    responderName: string;
    status: string;
    message: string;
  };
};

const MAX_BODY_BYTES = 16 * 1024;
const MAX_TOKENS = 10;
const MAX_TOKEN_LENGTH = 4096;
const ALLOWED_EVENTS = new Set([
  'Distress Sound',
  'Distress Sound + Impact',
  'Possible Distress Sound',
  'Emergency Alarm',
  'Impact / Breaking Sound',
  'Manual Silent Alert',
  'Live Detector Event',
  'SUNO preflight',
]);

const projectId = Deno.env.get('FIREBASE_PROJECT_ID');
const clientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL');
const privateKey = Deno.env.get('FIREBASE_PRIVATE_KEY')?.replace(/\\n/g, '\n');
const relayKey = Deno.env.get('SUNO_RELAY_AUTH_KEY')?.trim();

Deno.serve(async (req: Request) => {
  if (req.method === 'GET') {
    return json({
      ok: true,
      service: 'suno-send-alert',
      firebaseConfigured: Boolean(projectId && clientEmail && privateKey),
    });
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  if (relayKey) {
    const providedKey = req.headers.get('x-suno-relay-key') ?? '';
    if (!constantTimeEqual(providedKey, relayKey)) {
      return json({ error: 'Unauthorized' }, 401);
    }
  }

  if (!projectId || !clientEmail || !privateKey) {
    return json({ error: 'Firebase service account env vars missing' }, 500);
  }

  const rawBody = await req.text();
  if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
    return json({ error: 'Payload too large' }, 413);
  }

  let body: AlertPayload;
  try {
    body = JSON.parse(rawBody) as AlertPayload;
  } catch (_) {
    return json({ error: 'Invalid JSON body' }, 400);
  }

  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return json({ error: 'Invalid payload' }, 400);
  }

  if (typeof body.cancelIncidentId === 'string') {
    if (body.cancelIncidentId.length === 0 || body.cancelIncidentId.length > 128) {
      return json({ error: 'Invalid payload' }, 400);
    }
    return json({ ok: true, cancelled: body.cancelIncidentId });
  }

  const accessToken = await getAccessToken(clientEmail, privateKey);

  if (body.response) {
    const r = body.response;
    const res = await sendFcm(accessToken, r.recipientToken, {
      data: {
        type: 'response',
        incidentId: r.incidentId,
        responderName: r.responderName,
        status: r.status,
        message: r.message,
      },
      android: {
        priority: 'HIGH',
        notification: {
          channel_id: 'suno_alerts',
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
      },
    });
    return json({
      ok: res.ok,
      sent: res.ok ? 1 : 0,
      results: [{ ok: res.ok, status: res.status }],
    });
  }

  if (!Array.isArray(body.contactTokens) || body.contactTokens.length > MAX_TOKENS) {
    return json({ error: 'Invalid contact tokens' }, 400);
  }
  if (body.contactTokens.some((token) =>
    typeof token !== 'string' || token.trim().length < 21 || token.length > MAX_TOKEN_LENGTH
  )) {
    return json({ error: 'Invalid contact tokens' }, 400);
  }
  if (!body.payload || typeof body.payload !== 'object' || Array.isArray(body.payload)) {
    return json({ error: 'Invalid payload' }, 400);
  }

  const payload = body.payload;
  if (Object.keys(payload).length > 16 || Object.entries(payload).some(([key, value]) =>
    key.length > 64 || typeof value !== 'string' || value.length > 256
  )) {
    return json({ error: 'Invalid payload' }, 400);
  }
  if (payload.eventType && !ALLOWED_EVENTS.has(payload.eventType)) {
    return json({ error: 'Invalid event type' }, 400);
  }
  if (payload.riskScore && !/^\d{1,3}$/.test(payload.riskScore)) {
    return json({ error: 'Invalid risk score' }, 400);
  }
  if (payload.riskScore && Number(payload.riskScore) > 100) {
    return json({ error: 'Invalid risk score' }, 400);
  }

  const tokens = body.contactTokens.map((token) => token.trim());
  if (tokens.length === 0) {
    return json({ ok: true, sent: 0 });
  }

  try {
    const isTest = body.test === true;
    const results: Array<{ ok: boolean; status: number }> = [];
    for (const token of tokens) {
      const res = await sendFcm(accessToken, token, {
        ...(isTest
          ? {}
          : {
            notification: {
              title: 'SUNO emergency alert',
              body: `${payload.eventType ?? 'Emergency'} · Risk ${payload.riskScore ?? '?'}%`,
            },
          }),
        data: payload,
        android: {
          priority: 'HIGH',
          notification: {
            channel_id: 'suno_alerts',
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
      });
      results.push({ ok: res.ok, status: res.status });
    }

    return json({
      ok: results.every((result) => result.ok),
      sent: results.filter((result) => result.ok).length,
      attempted: results.length,
      results,
    });
  } catch (error) {
    console.error(
      '[SUNO relay] delivery failed',
      error instanceof Error ? error.message : String(error),
    );
    return json({ error: 'Push delivery failed' }, 502);
  }
});

function sendFcm(
  accessToken: string,
  token: string,
  message: Record<string, unknown>,
): Promise<{ ok: boolean; status: number }> {
  return fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ message: { token, ...message } }),
    },
  );
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function constantTimeEqual(left: string, right: string): boolean {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  let difference = leftBytes.length ^ rightBytes.length;
  const maxLength = Math.max(leftBytes.length, rightBytes.length);
  for (let i = 0; i < maxLength; i++) {
    difference |= (leftBytes[i] ?? 0) ^ (rightBytes[i] ?? 0);
  }
  return difference === 0;
}

async function getAccessToken(email: string, key: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const jwtHeader = { alg: 'RS256', typ: 'JWT' };
  const jwtClaim = {
    iss: email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const unsigned = `${base64Url(JSON.stringify(jwtHeader))}.${base64Url(JSON.stringify(jwtClaim))}`;
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64Url(signature)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`OAuth token request failed with ${res.status}`);
  }
  const decoded = await res.json() as { access_token: string };
  return decoded.access_token;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64Url(input: string | ArrayBuffer): string {
  const bytes = typeof input === 'string'
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}
