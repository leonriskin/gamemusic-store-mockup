const fs = require('fs');
const path = require('path');

const WAITLIST_LOGO_URL = 'https://riskintracks.com/assets/riskin-tracks-logo-header.png';
const DEFAULT_R2_PUBLIC_BASE = 'https://pub-45a1df6488174a1a84baf1ed003ac6dd.r2.dev';
const HISTORY_REL = 'data/newsletter-history.json';
const SCHEDULE_REL = 'data/newsletter-schedule.json';
const MAX_HISTORY = 100;
const MAX_SCHEDULE = 50;
/** Canonical section order when concatenating multi-component emails. */
const SECTION_ORDER = ['announcement', 'tracks', 'discount'];
const VALID_SECTIONS = new Set(SECTION_ORDER);

function escapeHtml(str) {
  return String(str ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function isDev() {
  return process.env.NETLIFY_DEV === 'true';
}

function isNewsletterAllowed(event) {
  if (isDev()) return true;
  const secret = (process.env.ADMIN_NEWSLETTER_SECRET || '').trim();
  if (!secret) return false;
  const headers = event.headers || {};
  const provided = (
    headers['x-admin-newsletter-secret'] ||
    headers['X-Admin-Newsletter-Secret'] ||
    ''
  ).trim();
  return provided === secret;
}

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

function getR2PublicBase() {
  return (process.env.R2_PUBLIC_BASE_URL || DEFAULT_R2_PUBLIC_BASE).replace(/\/$/, '');
}

function getLogoUrl() {
  return (process.env.WAITLIST_LOGO_URL || WAITLIST_LOGO_URL).trim();
}

function buildUnsubscribeUrl(baseUrl, email) {
  const q = email ? `?email=${encodeURIComponent(email)}` : '';
  return `${baseUrl.replace(/\/$/, '')}/.netlify/functions/waitlist-unsubscribe${q}`;
}

/** Listen URL: R2 demo while store is under construction; site home when SITE_LIVE=true. */
function buildListenUrl(slug, siteBase) {
  const safe = String(slug || '')
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, '-')
    .replace(/^-|-$/g, '');
  if (!safe) return siteBase.replace(/\/$/, '') + '/';
  if (process.env.SITE_LIVE === 'true') {
    return `${siteBase.replace(/\/$/, '')}/`;
  }
  return `${getR2PublicBase()}/tracks/${safe}/demo.mp3`;
}

function buildCoverUrl(slug, coverPath) {
  if (coverPath && /^https?:\/\//i.test(coverPath)) return coverPath;
  const safe = String(slug || '')
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, '-')
    .replace(/^-|-$/g, '');
  if (coverPath && typeof coverPath === 'string') {
    const rel = coverPath.replace(/^\.\//, '').replace(/^\//, '');
    if (rel.startsWith('tracks/')) return `${getR2PublicBase()}/${rel}`;
  }
  if (!safe) return '';
  return `${getR2PublicBase()}/tracks/${safe}/cover.jpg`;
}

function historyFilePath() {
  return path.resolve(__dirname, '../../../', HISTORY_REL);
}

function scheduleFilePath() {
  return path.resolve(__dirname, '../../../', SCHEDULE_REL);
}

function readHistoryFile() {
  const file = historyFilePath();
  try {
    if (!fs.existsSync(file)) return [];
    const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
    return Array.isArray(raw) ? raw : Array.isArray(raw?.items) ? raw.items : [];
  } catch (err) {
    console.error('newsletter history read failed:', err.message || err);
    return [];
  }
}

function appendHistoryFile(entry) {
  const file = historyFilePath();
  try {
    const dir = path.dirname(file);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const items = readHistoryFile();
    items.unshift(entry);
    const trimmed = items.slice(0, MAX_HISTORY);
    fs.writeFileSync(file, JSON.stringify(trimmed, null, 2) + '\n', 'utf8');
    return { ok: true, items: trimmed };
  } catch (err) {
    console.error('newsletter history write failed:', err.message || err);
    return { ok: false, error: String(err.message || err) };
  }
}

function readScheduleFile() {
  const file = scheduleFilePath();
  try {
    if (!fs.existsSync(file)) return [];
    const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
    return Array.isArray(raw) ? raw : Array.isArray(raw?.items) ? raw.items : [];
  } catch (err) {
    console.error('newsletter schedule read failed:', err.message || err);
    return [];
  }
}

function writeScheduleFile(items) {
  const file = scheduleFilePath();
  try {
    const dir = path.dirname(file);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const trimmed = (Array.isArray(items) ? items : []).slice(0, MAX_SCHEDULE);
    fs.writeFileSync(file, JSON.stringify(trimmed, null, 2) + '\n', 'utf8');
    return { ok: true, items: trimmed };
  } catch (err) {
    console.error('newsletter schedule write failed:', err.message || err);
    return { ok: false, error: String(err.message || err), items: Array.isArray(items) ? items : [] };
  }
}

function emailShell({ logoUrl, titleHtml, bodyHtml, footerNoteHtml, unsubscribeHtml }) {
  const logoHref = escapeHtml(logoUrl);
  return [
    '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#0c0d10;margin:0;padding:0">',
    '<tr><td align="center" style="padding:32px 16px">',
    '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="520" style="max-width:520px;width:100%">',
    '<tr><td style="padding:0 0 20px;text-align:left">',
    `<img src="${logoHref}" alt="Riskin Tracks" width="200" style="display:block;max-width:200px;width:100%;height:auto;border:0;outline:none;text-decoration:none" />`,
    '</td></tr>',
    '<tr><td style="font-family:Georgia,serif;font-size:22px;line-height:1.35;color:#f2f3f7;padding:0 0 12px">',
    titleHtml,
    '</td></tr>',
    bodyHtml,
    '<tr><td style="font-family:system-ui,-apple-system,sans-serif;font-size:13px;color:#6b7289;padding:8px 0 20px">— Riskin Tracks</td></tr>',
    '<tr><td style="font-family:system-ui,-apple-system,sans-serif;font-size:12px;line-height:1.5;color:#6b7289;border-top:1px solid rgba(255,255,255,0.08);padding-top:16px">',
    footerNoteHtml || "Don't want waitlist updates?",
    ' ',
    unsubscribeHtml,
    '</td></tr>',
    '</table>',
    '</td></tr>',
    '</table>',
  ].join('\n');
}

function ctaButton(label, href) {
  const safeLabel = escapeHtml(label || 'Listen');
  const safeHref = escapeHtml(href || '#');
  return [
    '<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0">',
    '<tr><td style="border-radius:999px;background:#5eead4">',
    `<a href="${safeHref}" target="_blank" rel="noopener noreferrer" style="display:inline-block;padding:10px 20px;font-family:system-ui,-apple-system,sans-serif;font-size:13px;font-weight:700;color:#0c0d10;text-decoration:none;border-radius:999px">${safeLabel}</a>`,
    '</td></tr>',
    '</table>',
  ].join('');
}

function sectionDivider() {
  return '<tr><td style="padding:8px 0 28px"><div style="height:1px;background:rgba(255,255,255,0.08)"></div></td></tr>';
}

function buildTracksBody(tracks) {
  const rows = (tracks || []).map((t) => {
    const title = escapeHtml(t.title || 'Untitled');
    const blurb = escapeHtml(t.blurb || '');
    const cover = escapeHtml(t.coverUrl || '');
    const listen = t.listenUrl || '#';
    const coverCell = cover
      ? `<img src="${cover}" alt="" width="88" height="88" style="display:block;width:88px;height:88px;object-fit:cover;border-radius:10px;border:0" />`
      : `<div style="width:88px;height:88px;border-radius:10px;background:#1a1d26"></div>`;
    return [
      '<tr><td style="padding:0 0 22px">',
      '<table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">',
      '<tr>',
      `<td width="88" valign="top" style="padding:0 16px 0 0">${coverCell}</td>`,
      '<td valign="top">',
      `<div style="font-family:system-ui,-apple-system,sans-serif;font-size:16px;font-weight:700;color:#f2f3f7;padding:0 0 6px">${title}</div>`,
      blurb
        ? `<div style="font-family:system-ui,-apple-system,sans-serif;font-size:14px;line-height:1.55;color:#8b92a8;padding:0 0 12px">${blurb}</div>`
        : '',
      ctaButton('Listen', listen),
      '</td>',
      '</tr>',
      '</table>',
      '</td></tr>',
    ].join('\n');
  });
  return rows.join('\n');
}

function buildDiscountBody(discount, siteBase) {
  const code = escapeHtml(discount.code || '');
  const description = escapeHtml(discount.description || '');
  const expiry = escapeHtml(discount.expiry || '');
  const ctaLabel = discount.ctaLabel || 'Claim offer';
  const ctaUrl = discount.ctaUrl || siteBase;
  return [
    description
      ? `<tr><td style="font-family:system-ui,-apple-system,sans-serif;font-size:15px;line-height:1.6;color:#8b92a8;padding:0 0 16px">${description}</td></tr>`
      : '',
    code
      ? [
          '<tr><td style="padding:0 0 16px">',
          `<div style="display:inline-block;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:20px;font-weight:700;letter-spacing:0.08em;color:#5eead4;background:rgba(94,234,212,0.12);border:1px solid rgba(94,234,212,0.35);border-radius:10px;padding:12px 18px">${code}</div>`,
          '</td></tr>',
        ].join('\n')
      : '',
    expiry
      ? `<tr><td style="font-family:system-ui,-apple-system,sans-serif;font-size:13px;color:#6b7289;padding:0 0 18px">Expires ${expiry}</td></tr>`
      : '',
    `<tr><td style="padding:0 0 20px">${ctaButton(ctaLabel, ctaUrl)}</td></tr>`,
  ].join('\n');
}

function buildAnnouncementBody(announcement, siteBase) {
  const body = escapeHtml(announcement.body || '').replace(/\n/g, '<br />');
  const ctaLabel = announcement.ctaLabel || '';
  const ctaUrl = announcement.ctaUrl || siteBase;
  return [
    body
      ? `<tr><td style="font-family:system-ui,-apple-system,sans-serif;font-size:15px;line-height:1.6;color:#8b92a8;padding:0 0 18px">${body}</td></tr>`
      : '',
    ctaLabel
      ? `<tr><td style="padding:0 0 20px">${ctaButton(ctaLabel, ctaUrl)}</td></tr>`
      : '',
  ].join('\n');
}

/**
 * Normalize section list from request body.
 * Accepts `sections` array (preferred) or legacy single `template`.
 * Returns unique sections in canonical order: announcement → tracks → discount.
 */
function normalizeSections(body) {
  let picked = [];
  if (Array.isArray(body?.sections) && body.sections.length) {
    picked = body.sections.map((s) => String(s || '').trim()).filter((s) => VALID_SECTIONS.has(s));
  } else if (body?.template) {
    // Legacy: single section name, or joined "announcement+tracks+discount"
    const parts = String(body.template)
      .split('+')
      .map((s) => s.trim())
      .filter((s) => VALID_SECTIONS.has(s));
    picked = parts.length ? parts : VALID_SECTIONS.has(body.template) ? [body.template] : [];
  }
  // Infer from payload content when sections omitted (preview-friendly)
  if (!picked.length) {
    if (Array.isArray(body?.tracks) && body.tracks.length) picked.push('tracks');
    if (body?.announcement?.body || body?.body) picked.push('announcement');
    if (body?.discount?.code) picked.push('discount');
  }
  const seen = new Set();
  for (const s of picked) seen.add(s);
  return SECTION_ORDER.filter((s) => seen.has(s));
}

/**
 * Build full newsletter HTML.
 * @param {object} opts
 * @param {string[]} [opts.sections] multi-component sections
 * @param {'tracks'|'discount'|'announcement'} [opts.template] legacy single section
 * @param {string} opts.headline
 * @param {string} [opts.intro]
 * @param {object[]} [opts.tracks]
 * @param {object} [opts.discount]
 * @param {object} [opts.announcement]
 * @param {string} opts.logoUrl
 * @param {string} opts.siteBase
 * @param {string} [opts.unsubscribeUrl] real URL for test sends; omit for broadcast placeholder
 * @param {boolean} [opts.useResendUnsubscribe] use {{{RESEND_UNSUBSCRIBE_URL}}}
 */
function buildNewsletterHtml(opts) {
  const sections = normalizeSections(opts);
  const headline = escapeHtml(opts.headline || 'News from Riskin Tracks');
  const intro = opts.intro
    ? `<tr><td style="font-family:system-ui,-apple-system,sans-serif;font-size:15px;line-height:1.6;color:#8b92a8;padding:0 0 20px">${escapeHtml(opts.intro)}</td></tr>`
    : '';

  const parts = [];
  sections.forEach((section, i) => {
    if (i > 0) parts.push(sectionDivider());
    if (section === 'announcement') {
      parts.push(buildAnnouncementBody(opts.announcement || {}, opts.siteBase));
    } else if (section === 'tracks') {
      parts.push(buildTracksBody(opts.tracks || []));
    } else if (section === 'discount') {
      parts.push(buildDiscountBody(opts.discount || {}, opts.siteBase));
    }
  });

  const bodyHtml = intro + parts.join('\n');

  let unsubscribeHtml;
  if (opts.useResendUnsubscribe) {
    unsubscribeHtml =
      '<a href="{{{RESEND_UNSUBSCRIBE_URL}}}" style="color:#8b92a8;text-decoration:underline">Unsubscribe</a>.';
  } else {
    const unsub = escapeHtml(opts.unsubscribeUrl || '#');
    unsubscribeHtml = `<a href="${unsub}" style="color:#8b92a8;text-decoration:underline">Unsubscribe</a>.`;
  }

  return emailShell({
    logoUrl: opts.logoUrl || getLogoUrl(),
    titleHtml: headline,
    bodyHtml,
    footerNoteHtml: "Don't want waitlist updates?",
    unsubscribeHtml,
  });
}

function normalizeTracks(rawTracks, siteBase) {
  const raw = Array.isArray(rawTracks) ? rawTracks.slice(0, 3) : [];
  return raw
    .map((t) => {
      const slug = String(t.slug || '')
        .toLowerCase()
        .replace(/[^a-z0-9-]+/g, '-')
        .replace(/^-|-$/g, '');
      const title = String(t.title || '').trim();
      if (!title && !slug) return null;
      return {
        id: t.id ?? null,
        title: title || slug,
        blurb: String(t.blurb || '').trim().slice(0, 400),
        slug,
        coverUrl: buildCoverUrl(slug, t.coverUrl || t.cover || ''),
        listenUrl: String(t.listenUrl || '').trim() || buildListenUrl(slug, siteBase),
      };
    })
    .filter(Boolean);
}

function normalizePayload(body, event) {
  const siteBase = getSiteBaseUrl(event);
  const sections = normalizeSections(body);
  const template = sections.length === 1 ? sections[0] : sections.join('+');
  const subject = String(body.subject || '').trim();
  const headline = String(body.headline || subject || 'News from Riskin Tracks').trim();
  const intro = String(body.intro || '').trim();

  const tracks = sections.includes('tracks')
    ? normalizeTracks(body.tracks, siteBase)
    : [];

  const discount = sections.includes('discount')
    ? {
        code: String(body.discount?.code || '').trim().slice(0, 64),
        description: String(body.discount?.description || '').trim().slice(0, 400),
        expiry: String(body.discount?.expiry || '').trim().slice(0, 80),
        ctaLabel: String(body.discount?.ctaLabel || 'Claim offer').trim().slice(0, 60),
        ctaUrl: String(body.discount?.ctaUrl || siteBase).trim(),
      }
    : null;

  const announcement = sections.includes('announcement')
    ? {
        body: String(body.announcement?.body || body.body || '').trim().slice(0, 2000),
        ctaLabel: String(body.announcement?.ctaLabel || '').trim().slice(0, 60),
        ctaUrl: String(body.announcement?.ctaUrl || siteBase).trim(),
      }
    : null;

  return { sections, template, subject, headline, intro, tracks, discount, announcement, siteBase };
}

function validatePayload(payload) {
  if (!payload.subject) return 'Subject is required.';
  if (payload.subject.length > 200) return 'Subject is too long.';
  if (!payload.sections?.length) {
    return 'Include at least one of: tracks, announcement, or discount.';
  }

  if (payload.sections.includes('tracks')) {
    if (!payload.tracks.length) return 'Pick 1–3 tracks for the New tracks section.';
    if (payload.tracks.length > 3) return 'Maximum 3 tracks.';
  }
  if (payload.sections.includes('discount')) {
    if (!payload.discount?.code) return 'Coupon code is required when Discount is included.';
    if (!payload.discount?.description) return 'Discount description is required when Discount is included.';
  }
  if (payload.sections.includes('announcement')) {
    if (!payload.announcement?.body) return 'Announcement body is required when Announcement is included.';
  }
  return null;
}

module.exports = {
  WAITLIST_LOGO_URL,
  SECTION_ORDER,
  escapeHtml,
  isDev,
  isNewsletterAllowed,
  getSiteBaseUrl,
  getR2PublicBase,
  getLogoUrl,
  buildUnsubscribeUrl,
  buildListenUrl,
  buildCoverUrl,
  readHistoryFile,
  appendHistoryFile,
  readScheduleFile,
  writeScheduleFile,
  scheduleFilePath,
  normalizeSections,
  buildNewsletterHtml,
  normalizePayload,
  validatePayload,
};
