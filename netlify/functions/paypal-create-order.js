const { paypalFetch, jsonResponse, isDev } = require('./lib/paypal');
const { normalizeItems, formatMoneyAmount } = require('./lib/pricing');

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email || '').trim());
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

  const paypalItems = priced.lineItems.map((item) => ({
    name: item.name.slice(0, 127),
    sku: item.sku,
    unit_amount: {
      currency_code: 'USD',
      value: formatMoneyAmount(item.unitAmount),
    },
    quantity: '1',
    category: 'DIGITAL_GOODS',
  }));

  const orderPayload = {
    intent: 'CAPTURE',
    purchase_units: [
      {
        reference_id: `riskin-${Date.now()}`,
        description: 'Riskin Tracks — indie game music license',
        custom_id: email.slice(0, 127),
        amount: {
          currency_code: 'USD',
          value: priced.total,
          breakdown: {
            item_total: {
              currency_code: 'USD',
              value: priced.total,
            },
          },
        },
        items: paypalItems,
      },
    ],
    application_context: {
      brand_name: 'Riskin Tracks',
      shipping_preference: 'NO_SHIPPING',
      user_action: 'PAY_NOW',
    },
  };

  try {
    const { res, data } = await paypalFetch('/v2/checkout/orders', {
      method: 'POST',
      body: JSON.stringify(orderPayload),
    });

    if (!res.ok) {
      console.error('PayPal create order failed:', res.status, data);
      return jsonResponse(502, {
        error: 'Could not start PayPal checkout.',
        ...(isDev() && { detail: data?.message || data?.details?.[0]?.description }),
      });
    }

    return jsonResponse(200, {
      id: data.id,
      total: priced.total,
      licenseeName,
      email,
    });
  } catch (err) {
    console.error('PayPal create order error:', err);
    const notConfigured = err.code === 'NOT_CONFIGURED';
    return jsonResponse(notConfigured ? 503 : 502, {
      error: notConfigured
        ? 'PayPal is not configured yet.'
        : 'Could not start PayPal checkout.',
      ...(isDev() && { detail: err.message }),
    });
  }
};
