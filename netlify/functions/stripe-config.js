const { isStripeConfigured, getStripeMode, jsonResponse } = require('./lib/stripe');

exports.handler = async () => {
  const configured = isStripeConfigured();
  return jsonResponse(200, {
    configured,
    mode: getStripeMode(),
    publishableKey: configured ? process.env.STRIPE_PUBLISHABLE_KEY : '',
  });
};
