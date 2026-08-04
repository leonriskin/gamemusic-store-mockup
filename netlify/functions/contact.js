const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 5;
const rateLimitStore = new Map();

function getClientIp(event) {
  const forwarded = event.headers['x-forwarded-for'] || event.headers['X-Forwarded-For'];
  if (forwarded) return forwarded.split(',')[0].trim();
  return event.headers['client-ip'] || 'unknown';
}

function checkRateLimit(ip) {
  const now = Date.now();
  let entry = rateLimitStore.get(ip);
  if (!entry || now > entry.resetAt) {
    entry = { count: 0, resetAt: now + RATE_LIMIT_WINDOW_MS };
  }
  entry.count += 1;
  rateLimitStore.set(ip, entry);
  return entry.count <= RATE_LIMIT_MAX;
}

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
}

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

function isDev() {
  return process.env.NETLIFY_DEV === 'true';
}

function resendErrorDetail(data) {
  if (!data || typeof data !== 'object') return null;
  if (data.message) return data.message;
  if (Array.isArray(data.errors) && data.errors[0]?.message) return data.errors[0].message;
  return null;
}

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return jsonResponse(405, { error: 'Method not allowed' });
  }

  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    console.error('RESEND_API_KEY is not set');
    return jsonResponse(500, {
      error: 'Email service not configured',
      ...(isDev() && { detail: 'Set RESEND_API_KEY in .env and restart npm run dev.' }),
    });
  }

  const ip = getClientIp(event);
  if (!checkRateLimit(ip)) {
    return jsonResponse(429, {
      error: 'Too many messages. Please wait a minute and try again.',
    });
  }

  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch {
    return jsonResponse(400, { error: 'Invalid request' });
  }

  if (body._honey) {
    return jsonResponse(200, { ok: true });
  }

  const name = (body.name || '').trim();
  const email = (body.email || '').trim();
  const subject = (body.subject || '').trim();
  const message = (body.message || '').trim();

  if (!name || !email || !subject || !message) {
    return jsonResponse(400, { error: 'All fields are required.' });
  }
  if (!isValidEmail(email)) {
    return jsonResponse(400, { error: 'Invalid email address.' });
  }
  if (name.length > 200 || subject.length > 200 || message.length > 10000) {
    return jsonResponse(400, { error: 'Message is too long.' });
  }

  const to = process.env.CONTACT_TO || 'ionicsmusic2017@gmail.com';
  const from = process.env.RESEND_FROM || 'Riskin Tracks <onboarding@resend.dev>';

  const html = [
    `<p><strong>From:</strong> ${escapeHtml(name)} &lt;${escapeHtml(email)}&gt;</p>`,
    `<p><strong>Subject:</strong> ${escapeHtml(subject)}</p>`,
    '<hr/>',
    `<p>${escapeHtml(message).replace(/\n/g, '<br/>')}</p>`,
  ].join('\n');

  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from,
        to: [to],
        reply_to: email,
        subject: `Riskin Tracks — ${subject}`,
        html,
      }),
    });

    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const detail = resendErrorDetail(data);
      console.error('Resend API error:', res.status, data);
      return jsonResponse(502, {
        error: 'Could not send your message.',
        ...(isDev() && detail && { detail }),
      });
    }

    return jsonResponse(200, { ok: true, id: data.id });
  } catch (err) {
    console.error('Contact send failed:', err);
    return jsonResponse(502, { error: 'Could not send your message.' });
  }
};
