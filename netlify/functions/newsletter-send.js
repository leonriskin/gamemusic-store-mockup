const { loadEnvIfNeeded } = require('./lib/load-env');
const {
  isDev,
  isNewsletterAllowed,
  getLogoUrl,
  buildUnsubscribeUrl,
  buildNewsletterHtml,
  normalizePayload,
  validatePayload,
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

function resendErrorDetail(data) {
  if (!data || typeof data !== 'object') return null;
  if (data.message) return data.message;
  if (Array.isArray(data.errors) && data.errors[0]?.message) return data.errors[0].message;
  return null;
}

async function resendFetch(apiKey, path, body, method = 'POST') {
  const res = await fetch(`https://api.resend.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: body != null ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  return { res, data };
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

/** Best-effort subscriber count for WAITLIST_AUDIENCE_ID (segment or legacy audience). */
async function fetchAudienceCount(apiKey, audienceId) {
  if (!audienceId) return null;

  // Legacy audiences contacts list
  try {
    const { res, data } = await resendFetch(
      apiKey,
      `/audiences/${encodeURIComponent(audienceId)}/contacts?limit=1`,
      null,
      'GET'
    );
    if (res.ok) {
      if (typeof data.total === 'number') return data.total;
      if (typeof data.count === 'number') return data.count;
      if (Array.isArray(data.data)) {
        // Some responses only return a page; still better than nothing when total missing
        return data.data.length;
      }
    }
  } catch (err) {
    console.error('audience count (legacy) failed:', err.message || err);
  }

  // Global contacts list (no reliable segment filter on all plans) — skip
  return null;
}

async function sendBroadcast(apiKey, { from, subject, html, audienceId, name }) {
  // Prefer segment_id (current Resend), fall back to audience_id (legacy).
  const payloadSegment = {
    segment_id: audienceId,
    from,
    subject,
    html,
    name: name || subject,
    send: true,
  };
  let { res, data } = await resendFetch(apiKey, '/broadcasts', payloadSegment);
  if (res.ok) return { ok: true, id: data.id, mode: 'broadcast-segment', data };

  const segmentErr = resendErrorDetail(data);
  console.error('Resend broadcast (segment_id) failed:', res.status, data);

  const payloadAudience = {
    audience_id: audienceId,
    from,
    subject,
    html,
    name: name || subject,
    send: true,
  };
  ({ res, data } = await resendFetch(apiKey, '/broadcasts', payloadAudience));
  if (res.ok) return { ok: true, id: data.id, mode: 'broadcast-audience', data };

  console.error('Resend broadcast (audience_id) failed:', res.status, data);
  return {
    ok: false,
    error: resendErrorDetail(data) || segmentErr || `HTTP ${res.status}`,
    status: res.status,
  };
}

async function sendTestEmail(apiKey, { from, to, subject, html, unsubscribeUrl }) {
  const payload = {
    from,
    to: [to],
    subject,
    html,
    headers: {
      'List-Unsubscribe': `<${unsubscribeUrl}>`,
      'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
    },
  };
  const { res, data } = await resendFetch(apiKey, '/emails', payload);
  if (!res.ok) {
    return {
      ok: false,
      error: resendErrorDetail(data) || `HTTP ${res.status}`,
      status: res.status,
    };
  }
  return { ok: true, id: data.id, mode: 'test-email', data };
}

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return jsonResponse(405, { error: 'Method not allowed' });
  }

  if (!isNewsletterAllowed(event)) {
    return jsonResponse(403, {
      error: 'Newsletter send is only allowed in local Netlify Dev, or with a valid ADMIN_NEWSLETTER_SECRET header.',
      ...(isDev() ? {} : { detail: 'Set ADMIN_NEWSLETTER_SECRET and send X-Admin-Newsletter-Secret.' }),
    });
  }

  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch {
    return jsonResponse(400, { error: 'Invalid request' });
  }

  const previewOnly = Boolean(body.previewOnly || body.dryRun);
  const testEmail = String(body.testEmail || '').trim().toLowerCase();
  const payload = normalizePayload(body, event);
  // Preview may be incomplete while composing; only enforce full rules on send/schedule.
  if (!previewOnly) {
    const validationError = validatePayload(payload);
    if (validationError) {
      return jsonResponse(400, { error: validationError });
    }
  } else if (!payload.subject) {
    payload.subject = payload.headline || 'Riskin Tracks';
  }

  const logoUrl = getLogoUrl();
  const useResendUnsubscribe = !previewOnly && !testEmail;
  const unsubscribeUrl = testEmail
    ? buildUnsubscribeUrl(payload.siteBase, testEmail)
    : buildUnsubscribeUrl(payload.siteBase, 'subscriber@example.com');

  const html = buildNewsletterHtml({
    sections: payload.sections,
    template: payload.template,
    headline: payload.headline,
    intro: payload.intro,
    tracks: payload.tracks,
    discount: payload.discount,
    announcement: payload.announcement,
    logoUrl,
    siteBase: payload.siteBase,
    unsubscribeUrl,
    useResendUnsubscribe,
  });

  if (previewOnly) {
    return jsonResponse(200, {
      ok: true,
      preview: true,
      html,
      subject: payload.subject,
      sections: payload.sections,
      template: payload.template,
    });
  }

  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    return jsonResponse(500, {
      error: 'Email service not configured',
      ...(isDev() && { detail: 'Set RESEND_API_KEY in .env and restart npm run dev.' }),
    });
  }

  const from =
    process.env.WAITLIST_FROM ||
    process.env.RESEND_FROM ||
    'Riskin Tracks <onboarding@resend.dev>';
  const audienceId = (process.env.WAITLIST_AUDIENCE_ID || '').trim();

  let sendResult;
  let recipientCount = null;

  try {
    if (testEmail) {
      if (!isValidEmail(testEmail)) {
        return jsonResponse(400, { error: 'Invalid test email address.' });
      }
      sendResult = await sendTestEmail(apiKey, {
        from,
        to: testEmail,
        subject: payload.subject,
        html,
        unsubscribeUrl,
      });
      recipientCount = 1;
    } else {
      if (!audienceId) {
        return jsonResponse(400, {
          error: 'WAITLIST_AUDIENCE_ID is required to broadcast to waitlist subscribers.',
          detail:
            'Create a Resend Audience/Segment, set WAITLIST_AUDIENCE_ID, or send a test with testEmail instead.',
        });
      }
      recipientCount = await fetchAudienceCount(apiKey, audienceId);
      sendResult = await sendBroadcast(apiKey, {
        from,
        subject: payload.subject,
        html,
        audienceId,
        name: `Newsletter — ${payload.sections.join('+')} — ${payload.subject}`.slice(0, 120),
      });
    }
  } catch (err) {
    console.error('Newsletter send failed:', err);
    return jsonResponse(502, {
      error: 'Could not send newsletter. Please try again.',
      ...(isDev() && { detail: String(err.message || err) }),
    });
  }

  if (!sendResult?.ok) {
    return jsonResponse(502, {
      error: 'Could not send newsletter. Please try again.',
      ...(isDev() && sendResult?.error && { detail: sendResult.error }),
    });
  }

  const historyEntry = {
    id: sendResult.id || `local-${Date.now()}`,
    sentAt: new Date().toISOString(),
    subject: payload.subject,
    sections: payload.sections,
    template: payload.template,
    headline: payload.headline,
    recipientCount,
    mode: sendResult.mode,
    testEmail: testEmail || null,
    trackTitles: payload.sections.includes('tracks')
      ? payload.tracks.map((t) => t.title)
      : undefined,
    discountCode: payload.sections.includes('discount') ? payload.discount?.code : undefined,
  };

  const write = appendHistoryFile(historyEntry);

  return jsonResponse(200, {
    ok: true,
    id: sendResult.id,
    mode: sendResult.mode,
    recipientCount,
    history: historyEntry,
    historyPersisted: write.ok,
    ...(isDev() && !write.ok && write.error && { historyDetail: write.error }),
    subject: payload.subject,
    sections: payload.sections,
  });
};
