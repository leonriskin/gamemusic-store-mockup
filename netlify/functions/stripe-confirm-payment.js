const { stripeRequest, jsonResponse, isDev, isStripeConfigured } = require('./lib/stripe');
const { normalizeItems, formatMoneyAmount } = require('./lib/pricing');

function itemsFromMetadata(data) {
  try {
    const raw = data?.metadata?.items;
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.map((item) => ({
      trackId: Number(item?.trackId),
      tier: String(item?.tier || 'loop'),
    }));
  } catch {
    return [];
  }
}

function itemsFromClientBody(body) {
  if (!Array.isArray(body?.items) || !body.items.length) return [];
  return body.items.map((item) => ({
    trackId: Number(item?.trackId),
    tier: String(item?.tier || 'loop'),
  }));
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

  const paymentIntentId = String(body.paymentIntentId || '').trim();
  if (!paymentIntentId) {
    return jsonResponse(400, { error: 'Missing payment intent ID.' });
  }

  try {
    const { res, data } = await stripeRequest(`/payment_intents/${encodeURIComponent(paymentIntentId)}`, {
      method: 'GET',
    });

    if (!res.ok) {
      console.error('Stripe PaymentIntent retrieve failed:', res.status, data);
      return jsonResponse(502, {
        error: 'Could not verify card payment.',
        ...(isDev() && { detail: data?.error?.message }),
      });
    }

    if (data.status !== 'succeeded') {
      return jsonResponse(402, {
        error: 'Payment was not completed.',
        ...(isDev() && { detail: `status=${data.status}` }),
      });
    }

    let rawItems = itemsFromClientBody(body);
    if (!rawItems.length) rawItems = itemsFromMetadata(data);

    let priced;
    try {
      priced = normalizeItems(rawItems);
    } catch (err) {
      console.error('Stripe item validation failed:', err.message, rawItems);
      return jsonResponse(400, {
        error: 'Paid items could not be verified.',
        ...(isDev() && { detail: err.message }),
      });
    }

    const captured = formatMoneyAmount((Number(data.amount_received || data.amount) || 0) / 100);
    if (captured !== priced.total) {
      console.error('Stripe amount mismatch:', captured, priced.total);
      return jsonResponse(400, { error: 'Payment amount mismatch.' });
    }

    return jsonResponse(200, {
      ok: true,
      paymentIntentId: data.id,
      total: priced.total,
      items: priced.lineItems.map(({ trackId, tier, title, unitAmount }) => ({
        trackId,
        tier,
        title,
        unitAmount,
      })),
    });
  } catch (err) {
    console.error('Stripe confirm error:', err);
    return jsonResponse(502, {
      error: 'Could not verify card payment.',
      ...(isDev() && { detail: err.message }),
    });
  }
};
