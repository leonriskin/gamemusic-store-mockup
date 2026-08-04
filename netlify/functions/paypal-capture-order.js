const { paypalFetch, jsonResponse, isDev } = require('./lib/paypal');
const { normalizeItems, formatMoneyAmount } = require('./lib/pricing');

function itemsFromPayPalOrder(data) {
  const unit = data?.purchase_units?.[0];
  const paypalItems = unit?.items || [];
  return paypalItems
    .map((item) => {
      const [trackIdRaw, tierRaw] = String(item.sku || '').split(':');
      return {
        trackId: Number(trackIdRaw),
        tier: tierRaw || 'loop',
      };
    })
    .filter((item) => Number.isFinite(item.trackId));
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

  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch {
    return jsonResponse(400, { error: 'Invalid request' });
  }

  const orderId = String(body.orderId || '').trim();
  if (!orderId) {
    return jsonResponse(400, { error: 'Missing PayPal order ID.' });
  }

  try {
    let { res, data } = await paypalFetch(`/v2/checkout/orders/${encodeURIComponent(orderId)}/capture`, {
      method: 'POST',
    });

    // Capture can succeed in PayPal while our first response path fails; retry via GET.
    const alreadyCaptured =
      !res.ok &&
      Array.isArray(data?.details) &&
      data.details.some((d) => d?.issue === 'ORDER_ALREADY_CAPTURED');

    if (alreadyCaptured) {
      ({ res, data } = await paypalFetch(`/v2/checkout/orders/${encodeURIComponent(orderId)}`, {
        method: 'GET',
      }));
    }

    if (!res.ok) {
      console.error('PayPal capture failed:', res.status, data);
      return jsonResponse(502, {
        error: 'PayPal payment could not be completed.',
        ...(isDev() && { detail: data?.message || data?.details?.[0]?.description }),
      });
    }

    const status = data.status;
    const capture = data?.purchase_units?.[0]?.payments?.captures?.[0];
    const captureStatus = capture?.status;
    const capturedAmount = capture?.amount?.value;
    const captureId = capture?.id;

    if (status !== 'COMPLETED' || captureStatus !== 'COMPLETED') {
      return jsonResponse(402, { error: 'Payment was not completed.' });
    }

    // Capture responses often omit line items/SKUs. Prefer client cart (re-priced
    // server-side) and fall back to PayPal items when present.
    let rawItems = itemsFromClientBody(body);
    if (!rawItems.length) rawItems = itemsFromPayPalOrder(data);

    let priced;
    try {
      priced = normalizeItems(rawItems);
    } catch (err) {
      console.error('PayPal capture item validation failed:', err.message, rawItems);
      return jsonResponse(400, {
        error: 'Paid items could not be verified.',
        ...(isDev() && { detail: err.message }),
      });
    }

    if (capturedAmount && formatMoneyAmount(capturedAmount) !== priced.total) {
      console.error('PayPal capture amount mismatch:', capturedAmount, priced.total);
      return jsonResponse(400, { error: 'Payment amount mismatch.' });
    }

    return jsonResponse(200, {
      ok: true,
      orderId,
      captureId,
      status,
      total: priced.total,
      items: priced.lineItems.map(({ trackId, tier, title, unitAmount }) => ({
        trackId,
        tier,
        title,
        unitAmount,
      })),
    });
  } catch (err) {
    console.error('PayPal capture error:', err);
    const notConfigured = err.code === 'NOT_CONFIGURED';
    return jsonResponse(notConfigured ? 503 : 502, {
      error: notConfigured
        ? 'PayPal is not configured yet.'
        : 'PayPal payment could not be completed.',
      ...(isDev() && { detail: err.message }),
    });
  }
};
