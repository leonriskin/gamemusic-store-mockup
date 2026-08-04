const { loadEnvIfNeeded } = require('./lib/load-env');
const {
  isDev,
  isNewsletterAllowed,
  readHistoryFile,
  appendHistoryFile,
} = require('./lib/newsletter');

loadEnvIfNeeded();

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
}

exports.handler = async (event) => {
  if (!isNewsletterAllowed(event)) {
    return jsonResponse(403, {
      error: 'Newsletter history is only available in local Netlify Dev, or with a valid ADMIN_NEWSLETTER_SECRET header.',
    });
  }

  if (event.httpMethod === 'GET') {
    const items = readHistoryFile();
    return jsonResponse(200, {
      ok: true,
      items,
      note:
        'History is persisted to data/newsletter-history.json when the filesystem is writable (local netlify dev). Production Netlify functions are ephemeral — use localStorage in Admin + Blobs/KV later if needed.',
      ...(isDev() && { persisted: true }),
    });
  }

  // Optional: allow client to push a history entry (e.g. after localStorage-only send record)
  if (event.httpMethod === 'POST') {
    let body;
    try {
      body = JSON.parse(event.body || '{}');
    } catch {
      return jsonResponse(400, { error: 'Invalid request' });
    }
    const entry = body.entry || body;
    if (!entry || !entry.subject || !entry.sentAt) {
      return jsonResponse(400, { error: 'entry with subject and sentAt is required.' });
    }
    const valid = new Set(['tracks', 'discount', 'announcement']);
    let sections = Array.isArray(entry.sections)
      ? entry.sections.map((s) => String(s)).filter((s) => valid.has(s))
      : [];
    if (!sections.length && valid.has(entry.template)) sections = [entry.template];
    if (!sections.length) sections = ['tracks'];
    const normalized = {
      id: entry.id || `local-${Date.now()}`,
      sentAt: entry.sentAt,
      subject: String(entry.subject).slice(0, 200),
      sections,
      template: sections.length === 1 ? sections[0] : sections.join('+'),
      headline: entry.headline ? String(entry.headline).slice(0, 200) : undefined,
      recipientCount:
        typeof entry.recipientCount === 'number' ? entry.recipientCount : null,
      mode: entry.mode || 'client',
      testEmail: entry.testEmail || null,
    };
    const write = appendHistoryFile(normalized);
    return jsonResponse(write.ok ? 200 : 500, {
      ok: write.ok,
      entry: normalized,
      ...(write.error && { error: write.error }),
    });
  }

  return jsonResponse(405, { error: 'Method not allowed' });
};
