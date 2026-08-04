const { loadEnvIfNeeded } = require('./lib/load-env');

loadEnvIfNeeded();

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function getEmailFromEvent(event) {
  const qs = event.queryStringParameters || {};
  let email = (qs.email || '').trim().toLowerCase();
  if (email) return email;

  const ct = (event.headers['content-type'] || event.headers['Content-Type'] || '').toLowerCase();
  const raw = event.body || '';
  if (!raw) return '';

  try {
    if (ct.includes('application/json')) {
      const parsed = JSON.parse(raw);
      return String(parsed.email || '').trim().toLowerCase();
    }
  } catch {
    /* fall through */
  }

  // application/x-www-form-urlencoded (and one-click POST bodies)
  try {
    const params = new URLSearchParams(raw);
    email = (params.get('email') || '').trim().toLowerCase();
    if (email) return email;
  } catch {
    /* ignore */
  }
  return '';
}

async function resendPatch(apiKey, path, body) {
  const res = await fetch(`https://api.resend.com${path}`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  return { res, data };
}

/**
 * Mark contact unsubscribed in Resend (global contact + optional legacy audience).
 */
async function unsubscribeContact(apiKey, email) {
  const result = { ok: false, already: false };

  const contact = await resendPatch(apiKey, `/contacts/${encodeURIComponent(email)}`, {
    unsubscribed: true,
  });

  if (contact.res.ok) {
    result.ok = true;
  } else if (contact.res.status === 404) {
    // No contact yet — treat as success so the user still sees confirmation.
    result.ok = true;
    result.already = true;
    console.log('Waitlist unsubscribe: contact not found (ok):', email);
  } else {
    console.error('Resend contact unsubscribe failed:', contact.res.status, contact.data);
    result.error = contact.data?.message || `HTTP ${contact.res.status}`;
  }

  const audienceId = (process.env.WAITLIST_AUDIENCE_ID || '').trim();
  if (audienceId) {
    const legacy = await resendPatch(
      apiKey,
      `/audiences/${encodeURIComponent(audienceId)}/contacts/${encodeURIComponent(email)}`,
      { unsubscribed: true }
    );
    if (legacy.res.ok || legacy.res.status === 404) {
      result.ok = true;
    } else {
      console.error('Resend audience unsubscribe failed:', legacy.res.status, legacy.data);
    }
  }

  return result;
}

function confirmationHtml({ email, ok, error }) {
  const safeEmail = email ? escapeHtml(email) : '';
  let title;
  let body;
  if (!email) {
    title = error === 'invalid email' ? 'Invalid link' : 'Missing email';
    body =
      'This unsubscribe link is incomplete or invalid. If you still receive waitlist mail, reply to that message and we\'ll remove you.';
  } else if (ok) {
    title = 'You\'re unsubscribed';
    body = `${safeEmail} has been removed from the Riskin Tracks waitlist. You won\'t get further waitlist emails from us.`;
  } else {
    title = 'Something went wrong';
    body = `We couldn\'t unsubscribe ${safeEmail} right now. Please try again in a moment, or reply to a waitlist email.`;
  }

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${title} — Riskin Tracks</title>
  <style>
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 32px 20px;
      font-family: system-ui, -apple-system, sans-serif;
      background: #0c0d10;
      color: #f2f3f7;
      text-align: center;
    }
    .card { max-width: 420px; }
    h1 { font-family: Georgia, serif; font-size: 28px; font-weight: 400; margin: 0 0 12px; }
    p { font-size: 15px; line-height: 1.6; color: #8b92a8; margin: 0 0 24px; }
    a { color: #5eead4; }
  </style>
</head>
<body>
  <div class="card">
    <h1>${title}</h1>
    <p>${body}</p>
    <p><a href="https://riskintracks.com/">Back to Riskin Tracks</a></p>
  </div>
</body>
</html>`;
}

exports.handler = async (event) => {
  const method = event.httpMethod || 'GET';
  if (method !== 'GET' && method !== 'POST') {
    return { statusCode: 405, body: 'Method not allowed' };
  }

  const email = getEmailFromEvent(event);
  const apiKey = process.env.RESEND_API_KEY;

  let ok = false;
  let error = null;

  if (email && isValidEmail(email) && apiKey) {
    try {
      const result = await unsubscribeContact(apiKey, email);
      ok = result.ok;
      error = result.error || null;
    } catch (err) {
      console.error('Waitlist unsubscribe failed:', err);
      error = String(err.message || err);
    }
  } else if (email && !isValidEmail(email)) {
    error = 'invalid email';
  } else if (email && !apiKey) {
    console.error('RESEND_API_KEY is not set');
    error = 'not configured';
  }

  // RFC 8058 one-click: POST returns blank 200/202.
  if (method === 'POST') {
    return {
      statusCode: ok || !email ? 200 : 502,
      headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      body: '',
    };
  }

  const validEmail = email && isValidEmail(email) ? email : '';
  return {
    statusCode: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
    body: confirmationHtml({
      email: validEmail,
      ok,
      error: !validEmail && email ? 'invalid email' : error,
    }),
  };
};
