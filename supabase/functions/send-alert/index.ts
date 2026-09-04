type AlertPayload = {
  contactTokens?: string[];
  payload?: Record<string, string>;
  cancelIncidentId?: string;
};

const projectId = Deno.env.get('FIREBASE_PROJECT_ID');
const clientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL');
const privateKey = Deno.env.get('FIREBASE_PRIVATE_KEY')?.replace(/\\n/g, '\n');

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  if (!projectId || !clientEmail || !privateKey) {
    return json({ error: 'Firebase service account env vars missing' }, 500);
  }

  const body = await req.json() as AlertPayload;
  if (body.cancelIncidentId) {
    return json({ ok: true, cancelled: body.cancelIncidentId });
  }

  const tokens = body.contactTokens ?? [];
  const payload = body.payload ?? {};
  if (tokens.length === 0) {
    return json({ ok: true, sent: 0 });
  }

  const accessToken = await getAccessToken(clientEmail, privateKey);
  const results: Array<{ ok: boolean; status: number }> = [];
  for (const token of tokens) {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: {
              title: 'SUNO emergency alert',
              body: `${payload.eventType ?? 'Emergency'} · Risk ${payload.riskScore ?? '?'}%`,
            },
            data: payload,
            android: {
              priority: 'HIGH',
              notification: {
                channel_id: 'suno_alerts',
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
              },
            },
          },
        }),
      },
    );
    results.push({ ok: res.ok, status: res.status });
  }

  return json({ ok: true, sent: results.filter((r) => r.ok).length, results });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
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
  if (!res.ok) throw new Error(await res.text());
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
