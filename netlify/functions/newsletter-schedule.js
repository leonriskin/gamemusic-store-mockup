const { loadEnvIfNeeded } = require('./lib/load-env');
const {
  isDev,
  isNewsletterAllowed,
  normalizePayload,
  validatePayload,
  readScheduleFile,
  writeScheduleFile,
} = require('./lib/newsletter');

loadEnvIfNeeded();

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
}

function sortByScheduledAt(items) {
  return [...items].sort((a, b) =>
    String(a.scheduledAt || '').localeCompare(String(b.scheduledAt || ''))
  );
}

exports.handler = async (event) => {
  if (!isNewsletterAllowed(event)) {
    return jsonResponse(403, {
      error: 'Newsletter schedule is only available in local Netlify Dev, or with a valid ADMIN_NEWSLETTER_SECRET header.',
    });
  }

  if (event.httpMethod === 'GET') {
    const items = sortByScheduledAt(readScheduleFile().filter((i) => i && i.status !== 'sent'));
    return jsonResponse(200, {
      ok: true,
      items,
      note:
        'Scheduled sends persist to data/newsletter-schedule.json when the filesystem is writable (local netlify dev). Production needs a Netlify scheduled function / cron — local Admin poll only fires while the Newsletter page is open.',
      ...(isDev() && { persisted: true }),
    });
  }

  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch {
    return jsonResponse(400, { error: 'Invalid request' });
  }

  if (event.httpMethod === 'DELETE' || body.action === 'cancel' || body.action === 'delete') {
    const id = String(body.id || '').trim();
    if (!id) return jsonResponse(400, { error: 'id is required to cancel a scheduled send.' });
    const items = readScheduleFile().filter((i) => i && i.id !== id);
    const write = writeScheduleFile(items);
    return jsonResponse(write.ok ? 200 : 500, {
      ok: write.ok,
      items: sortByScheduledAt(write.items || items),
      ...(write.error && { error: write.error }),
    });
  }

  if (event.httpMethod === 'POST' && body.action === 'mark-sent') {
    const id = String(body.id || '').trim();
    if (!id) return jsonResponse(400, { error: 'id is required.' });
    const items = readScheduleFile().filter((i) => i && i.id !== id);
    const write = writeScheduleFile(items);
    return jsonResponse(write.ok ? 200 : 500, {
      ok: write.ok,
      items: sortByScheduledAt(write.items || items),
      ...(write.error && { error: write.error }),
    });
  }

  if (event.httpMethod !== 'POST') {
    return jsonResponse(405, { error: 'Method not allowed' });
  }

  // Create scheduled send
  const scheduledAt = String(body.scheduledAt || '').trim();
  const when = Date.parse(scheduledAt);
  if (!scheduledAt || Number.isNaN(when)) {
    return jsonResponse(400, { error: 'scheduledAt must be a valid ISO date/time.' });
  }
  if (when < Date.now() - 30_000) {
    return jsonResponse(400, { error: 'scheduledAt must be in the future.' });
  }

  const payloadBody = body.payload || body;
  // Strip schedule-only / send-control fields from nested payload
  const {
    scheduledAt: _sa,
    action: _act,
    id: _id,
    timezone: _tz,
    localLabel: _ll,
    payload: _p,
    previewOnly: _po,
    dryRun: _dr,
    testEmail: _te,
    ...composeFields
  } = payloadBody;

  const normalized = normalizePayload(composeFields, event);
  const validationError = validatePayload(normalized);
  if (validationError) {
    return jsonResponse(400, { error: validationError });
  }

  const timezone =
    String(body.timezone || Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC').trim() ||
    'UTC';
  const localLabel = String(body.localLabel || '').trim() || new Date(when).toLocaleString();

  const entry = {
    id: `sched-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    scheduledAt: new Date(when).toISOString(),
    timezone,
    localLabel,
    createdAt: new Date().toISOString(),
    status: 'pending',
    subject: normalized.subject,
    sections: normalized.sections,
    template: normalized.template,
    headline: normalized.headline,
    payload: {
      sections: normalized.sections,
      template: normalized.template,
      subject: normalized.subject,
      headline: normalized.headline,
      intro: normalized.intro,
      tracks: normalized.tracks,
      discount: normalized.discount,
      announcement: normalized.announcement,
    },
  };

  const items = readScheduleFile().filter((i) => i && i.status !== 'sent');
  items.push(entry);
  const write = writeScheduleFile(sortByScheduledAt(items));
  if (!write.ok) {
    return jsonResponse(500, {
      ok: false,
      error: write.error || 'Could not persist schedule.',
      entry,
    });
  }

  return jsonResponse(200, {
    ok: true,
    entry,
    items: write.items,
  });
};
