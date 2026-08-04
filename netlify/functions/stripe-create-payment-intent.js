const { stripeRequest, encodeForm, jsonResponse, isDev, isStripeConfigured } = require('./lib/stripe');
const { normalizeItems } = require('./lib/pricing');

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email || '').trim());
}

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return jsonResponse(405, { error: 'Method not allowed' });
  }

  if (!isStripeConfigured()) {
    return jsonResponse(503, { error: 'Stripe is not configured yet.' });
  }

  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch {
    return jsonResponse(400, { error: 'Invalid request' });
  }

  const email = String(body.email || '').trim().toLowerCase();
  const licenseeName = String(body.licenseeName || '').trim();

  if (!licenseeName) {
    return jsonResponse(400, { error: 'Licensee name is required.' });
  }
  if (!email || !isValidEmail(email)) {
    return jsonResponse(400, { error: 'A valid email is required.' });
  }

  let priced;
  try {
    priced = normalizeItems(body.items);
  } catch (err) {
    return jsonResponse(400, { error: err.message || 'Invalid cart.' });
  }

  const amountCents = Math.round(Number(priced.total) * 100);
  if (!Number.isFinite(amountCents) || amountCents < 50) {
    return jsonResponse(400, { error: 'Order total is too low for card payment.' });
  }

  const description = priced.lineItems
    .map((item) => item.name)
    .join('; ')
    .slice(0, 900);

  try {
    const { res, data } = await stripeRequest('/payment_intents', {
      method: 'POST',
      body: encodeForm({
        amount: amountCents,
        currency: 'usd',
        'automatic_payment_methods[enabled]': 'true',
        receipt_email: email,
        description: `Riskin Tracks — ${description}`.slice(0, 1000),
        'metadata[licensee_name]': licenseeName.slice(0, 500),
        'metadata[email]': email.slice(0, 500),
        'metadata[items]': JSON.stringify(
          priced.lineItems.map(({ trackId, tier }) => ({ trackId, tier }))
        ).slice(0, 500),
      }),
    });

    if (!res.ok) {
      console.error('Stripe PaymentIntent create failed:', res.status, data);
      return jsonResponse(502, {
        error: 'Could not start card checkout.',
        ...(isDev() && { detail: data?.error?.message || data?.message }),
      });
    }

    return jsonResponse(200, {
      clientSecret: data.client_secret,
      paymentIntentId: data.id,
      total: priced.total,
    });
  } catch (err) {
    console.error('Stripe create PaymentIntent error:', err);
    return jsonResponse(502, {
      error: 'Could not start card checkout.',
      ...(isDev() && { detail: err.message }),
    });
  }
};
