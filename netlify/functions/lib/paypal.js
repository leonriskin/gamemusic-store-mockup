const { loadEnvIfNeeded } = require('./load-env');

loadEnvIfNeeded();

let cachedToken = null;
let tokenExpiresAt = 0;

function getPayPalMode() {
  const mode = (process.env.PAYPAL_MODE || 'sandbox').toLowerCase();
  return mode === 'live' ? 'live' : 'sandbox';
}

function getPayPalBaseUrl() {
  return getPayPalMode() === 'live'
    ? 'https://api-m.paypal.com'
    : 'https://api-m.sandbox.paypal.com';
}

function getCredentials() {
  const clientId = process.env.PAYPAL_CLIENT_ID;
  const clientSecret = process.env.PAYPAL_CLIENT_SECRET;
  if (!clientId || !clientSecret) {
    const err = new Error('PayPal credentials not configured');
    err.code = 'NOT_CONFIGURED';
    throw err;
  }
  return { clientId, clientSecret };
}

function isPayPalConfigured() {
  return !!(process.env.PAYPAL_CLIENT_ID && process.env.PAYPAL_CLIENT_SECRET);
}

async function getAccessToken() {
  if (cachedToken && Date.now() < tokenExpiresAt - 60_000) {
    return cachedToken;
  }

  const { clientId, clientSecret } = getCredentials();
  const auth = Buffer.from(`${clientId}:${clientSecret}`).toString('base64');
  const res = await fetch(`${getPayPalBaseUrl()}/v1/oauth2/token`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${auth}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials',
  });

  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(data.error_description || 'PayPal authentication failed');
    err.code = 'AUTH_FAILED';
    throw err;
  }

  cachedToken = data.access_token;
  tokenExpiresAt = Date.now() + (data.expires_in * 1000);
  return cachedToken;
}

async function paypalFetch(apiPath, options = {}) {
  const token = await getAccessToken();
  const res = await fetch(`${getPayPalBaseUrl()}${apiPath}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });
  const data = await res.json().catch(() => ({}));
  return { res, data };
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
  getPayPalMode,
  getPayPalBaseUrl,
  getCredentials,
  isPayPalConfigured,
  getAccessToken,
  paypalFetch,
  jsonResponse,
  isDev,
};
