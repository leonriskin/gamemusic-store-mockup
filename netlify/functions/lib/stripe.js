const { loadEnvIfNeeded } = require('./load-env');

loadEnvIfNeeded();

function isStripeConfigured() {
  return !!(process.env.STRIPE_SECRET_KEY && process.env.STRIPE_PUBLISHABLE_KEY);
}

function getStripeMode() {
  const secret = process.env.STRIPE_SECRET_KEY || '';
  if (secret.startsWith('sk_live')) return 'live';
  return 'test';
}

function getStripeSecretKey() {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) {
    const err = new Error('Stripe credentials not configured');
    err.code = 'NOT_CONFIGURED';
    throw err;
  }
  return key;
}

async function stripeRequest(apiPath, { method = 'GET', body } = {}) {
  const key = getStripeSecretKey();
  const res = await fetch(`https://api.stripe.com/v1${apiPath}`, {
    method,
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: body || undefined,
  });
  const data = await res.json().catch(() => ({}));
  return { res, data };
}

function encodeForm(fields) {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(fields)) {
    if (value === undefined || value === null) continue;
    params.append(key, String(value));
  }
  return params.toString();
}

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
}

function isDev() {
  return process.env.NETLIFY_DEV === 'true';
}

module.exports = {
  isStripeConfigured,
  getStripeMode,
  getStripeSecretKey,
  stripeRequest,
  encodeForm,
  jsonResponse,
  isDev,
};
