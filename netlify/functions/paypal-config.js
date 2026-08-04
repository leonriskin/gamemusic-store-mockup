const { getPayPalMode, isPayPalConfigured, jsonResponse } = require('./lib/paypal');

exports.handler = async () => {
  const configured = isPayPalConfigured();
  return jsonResponse(200, {
    clientId: configured ? process.env.PAYPAL_CLIENT_ID : '',
    mode: getPayPalMode(),
    configured,
  });
};
