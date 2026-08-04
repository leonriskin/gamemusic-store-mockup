const { loadEnvIfNeeded } = require('./lib/load-env');

loadEnvIfNeeded();

const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 5;
const rateLimitStore = new Map();

/** Production logo — absolute HTTPS so email clients can load it (not localhost). */
const WAITLIST_LOGO_URL = 'https://riskintracks.com/assets/riskin-tracks-logo-header.png';

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

async function resendFetch(apiKey, path, body) {
  const res = await fetch(`https://api.resend.com${path}`, {
    method: 'POST',
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
 * Site origin for unsubscribe links.
 * Prefer SITE_URL (or Netlify URL), else request Host, else production.
 */
function getSiteBaseUrl(event) {
  const fromEnv = (process.env.SITE_URL || process.env.URL || '').trim().replace(/\/$/, '');
  if (fromEnv) return fromEnv;

  const host = (
    event.headers['x-forwarded-host'] ||
    event.headers['X-Forwarded-Host'] ||
    event.headers.host ||
    event.headers.Host ||
    ''
  )
    .split(',')[0]
    .trim();
  if (host) {
    const proto = (
      event.headers['x-forwarded-proto'] ||
      event.headers['X-Forwarded-Proto'] ||
      (host.includes('localhost') || host.startsWith('127.') ? 'http' : 'https')
    )
      .split(',')[0]
      .trim();
    return `${proto}://${host}`;
  }

  return 'https://riskintracks.com';
}

function buildUnsubscribeUrl(baseUrl, email) {
  return `${baseUrl.replace(/\/$/, '')}/.netlify/functions/waitlist-unsubscribe?email=${encodeURIComponent(email)}`;
}

/**
 * Add email to Resend Contacts / Audience (optional).
 * - Always creates a global contact when possible.
 * - If WAITLIST_AUDIENCE_ID is set, also attaches to that audience (legacy)
 *   or segment (current Resend model). Failures are logged; signup continues.
 */
async function addToAudience(apiKey, email) {
  const audienceId = (process.env.WAITLIST_AUDIENCE_ID || '').trim();
  const result = { contactId: null, audienceAttached: false, skipped: !audienceId };

  const { res, data } = await resendFetch(apiKey, '/contacts', {
    email,
    unsubscribed: false,
  });

  if (res.ok || res.status === 409) {
    result.contactId = data.id || null;
    if (res.status === 409) {
      console.log('Waitlist contact already exists:', email);
    }
  } else {
    console.error('Resend contact create failed:', res.status, data);
    result.error = resendErrorDetail(data) || `HTTP ${res.status}`;
  }

  if (!audienceId) {
    if (!result.contactId) {
      console.log('Waitlist: no audience id; signup logged only for', email);
    }
    return result;
  }

  // Prefer segment attach (current Resend model), then legacy audience contacts.
  const contactKey = result.contactId || email;
  const segment = await resendFetch(
    apiKey,
    `/contacts/${encodeURIComponent(contactKey)}/segments/${encodeURIComponent(audienceId)}`,
    {}
  );
  if (segment.res.ok || segment.res.status === 409) {
    result.audienceAttached = true;
    return result;
  }

  const legacy = await resendFetch(apiKey, `/audiences/${audienceId}/contacts`, {
    email,
    unsubscribed: false,
  });
  if (legacy.res.ok || legacy.res.status === 409) {
    result.contactId = result.contactId || legacy.data.id || null;
    result.audienceAttached = true;
    return result;
  }

  console.error(
    'Resend audience/segment attach failed:',
    segment.res.status,
    segment.data,
    legacy.res.status,
    legacy.data
  );
  result.error =
    result.error ||
    resendErrorDetail(segment.data) ||
    resendErrorDetail(legacy.data) ||
    'audience attach failed';
  console.log('Waitlist: welcome email will still send for', email);
  return result;
}

const DEFAULT_R2_PUBLIC_BASE = 'https://pub-45a1df6488174a1a84baf1ed003ac6dd.r2.dev';

function getFoundersPackUrl() {
  const explicit = (process.env.WAITLIST_FOUNDERS_PACK_URL || '').trim();
  if (explicit) return explicit;
  const base = (process.env.R2_PUBLIC_BASE_URL || DEFAULT_R2_PUBLIC_BASE).replace(/\/$/, '');
  return `${base}/packs/founders-loop-pack.zip`;
}

function buildWelcomeHtml({ foundersPackUrl, unsubscribeUrl, logoUrl }) {
  const packHref = escapeHtml(foundersPackUrl);
  const unsubHref = escapeHtml(unsubscribeUrl);
  const logoHref = escapeHtml(logoUrl);
  // Table layout + dark bg so the black-backed logo stays readable in clients
  // that ignore dark-mode CSS.
  return [
    '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0c0d10;margin:0;padding:0">',
    '<tr><td align="center" style="padding:32px 16px">',
    '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="520" style="max-width:520px;width:100%">',
    '<tr><td style="padding:0 0 20px;text-align:left">',
    `<img src="${logoHref}" alt="Riskin Tracks" width="200" style="display:block;max-width:200px;width:100%;height:auto;border:0;outline:none;text-decoration:none" />`,
    '</td></tr>',
    '<tr><td style="font-family:Georgia,serif;font-size:22px;line-height:1.35;color:#f2f3f7;padding:0 0 12px">',
    'You\'re on the Riskin Tracks waitlist.',
    '</td></tr>',
    '<tr><td style="font-family:system-ui,-apple-system,sans-serif;font-size:15px;line-height:1.6;color:#8b92a8;padding:0 0 12px">',
    'Thanks for joining. We\'re building a curated music store for indie game developers.',
    '</td></tr>',
    '<tr><td style="font-family:system-ui,-apple-system,sans-serif;font-size:15px;line-height:1.6;color:#8b92a8;padding:0 0 12px">',
    `<a href="${packHref}" style="color:#5eead4;font-weight:600">Founders Loop Pack</a>`,
    ' — a small free pack of loops for early waitlist members,',
    ' plus early access when the store opens.',
    '</td></tr>',
    '<tr><td style="font-family:system-ui,-apple-system,sans-serif;font-size:14px;line-height:1.6;color:#6b7289;padding:0 0 28px">',
    'We\'ll email you when new tracks drop and when the catalog goes live.',
    ' Follow <a href="https://x.com/Leon_Riskin" style="color:#5eead4">@Leon_Riskin</a> for teasers.',
    '</td></tr>',
    '<tr><td style="font-family:system-ui,-apple-system,sans-serif;font-size:13px;color:#6b7289;padding:0 0 20px">— Riskin Tracks</td></tr>',
    '<tr><td style="font-family:system-ui,-apple-system,sans-serif;font-size:12px;line-height:1.5;color:#6b7289;border-top:1px solid rgba(255,255,255,0.08);padding-top:16px">',
    'Don\'t want waitlist updates?',
    ` <a href="${unsubHref}" style="color:#8b92a8;text-decoration:underline">Unsubscribe</a>.`,
    '</td></tr>',
    '</table>',
    '</td></tr>',
    '</table>',
  ].join('\n');
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
      error: 'Too many signups from this network. Please wait a minute and try again.',
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

  const email = (body.email || '').trim().toLowerCase();
  if (!email) {
    return jsonResponse(400, { error: 'Email is required.' });
  }
  if (!isValidEmail(email)) {
    return jsonResponse(400, { error: 'Invalid email address.' });
  }
  if (email.length > 320) {
    return jsonResponse(400, { error: 'Email is too long.' });
  }

  const from =
    process.env.WAITLIST_FROM ||
    process.env.RESEND_FROM ||
    'Riskin Tracks <onboarding@resend.dev>';
  const notifyTo = process.env.CONTACT_TO || '';
  const foundersPackUrl = getFoundersPackUrl();
  const siteBase = getSiteBaseUrl(event);
  const unsubscribeUrl = buildUnsubscribeUrl(siteBase, email);
  const logoUrl = (process.env.WAITLIST_LOGO_URL || WAITLIST_LOGO_URL).trim();

  let audience;
  try {
    audience = await addToAudience(apiKey, email);
  } catch (err) {
    console.error('Waitlist audience step failed:', err);
    audience = { contactId: null, audienceAttached: false, error: String(err.message || err) };
  }

  const html = buildWelcomeHtml({ foundersPackUrl, unsubscribeUrl, logoUrl });

  try {
    const payload = {
      from,
      to: [email],
      subject: 'You\'re on the list — Riskin Tracks Founders waitlist',
      html,
      headers: {
        'List-Unsubscribe': `<${unsubscribeUrl}>`,
        'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
      },
    };
    // Optional owner ping (same inbox as contact form).
    if (notifyTo && notifyTo.toLowerCase() !== email) {
      payload.bcc = [notifyTo];
    }

    const { res, data } = await resendFetch(apiKey, '/emails', payload);
    if (!res.ok) {
      const detail = resendErrorDetail(data);
      console.error('Resend welcome email error:', res.status, data);
      return jsonResponse(502, {
        error: 'Could not complete signup. Please try again.',
        ...(isDev() && detail && { detail }),
      });
    }

    return jsonResponse(200, {
      ok: true,
      id: data.id,
      audience: audience.audienceAttached,
      ...(isDev() && audience.error && { audienceDetail: audience.error }),
    });
  } catch (err) {
    console.error('Waitlist welcome send failed:', err);
    return jsonResponse(502, { error: 'Could not complete signup. Please try again.' });
  }
};
