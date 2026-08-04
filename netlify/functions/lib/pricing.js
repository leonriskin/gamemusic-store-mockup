const fs = require('fs');
const path = require('path');

const DEFAULT_LOOP_PRICE = 9;
const DEFAULT_PACK_PRICE = 12;

const TIER_LABELS = {
  loop: 'Loop only',
  pack: 'Full pack',
  upgrade: 'Pack upgrade',
};

let catalogCache = null;

function readJsonFile(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, '');
  return JSON.parse(raw);
}

function resolveCatalogPath() {
  const candidates = [
    path.join(__dirname, 'catalog.json'),
    path.join(__dirname, '..', '..', 'tracks', 'catalog.json'),
    path.join(process.cwd(), 'tracks', 'catalog.json'),
  ];
  for (const filePath of candidates) {
    if (fs.existsSync(filePath)) return filePath;
  }
  throw new Error(`Catalog not found (tried: ${candidates.join(', ')})`);
}

function loadCatalogTracks() {
  if (catalogCache) return catalogCache;
  const catalogPath = resolveCatalogPath();
  const parsed = readJsonFile(catalogPath);
  catalogCache = Array.isArray(parsed.tracks) ? parsed.tracks : [];
  return catalogCache;
}

function getTrack(trackId) {
  const id = Number(trackId);
  if (!Number.isFinite(id)) return null;
  return loadCatalogTracks().find((track) => track.id === id) || null;
}

function getLoopPrice(track) {
  return track?.loopPrice ?? track?.price ?? DEFAULT_LOOP_PRICE;
}

function getPackPrice(track) {
  return track?.packPrice ?? DEFAULT_PACK_PRICE;
}

function tierPrice(track, tier) {
  if (!track) return null;
  if (tier === 'pack') return getPackPrice(track);
  if (tier === 'upgrade') return Math.max(0, getPackPrice(track) - getLoopPrice(track));
  return getLoopPrice(track);
}

function formatMoneyAmount(amount) {
  return Number(amount).toFixed(2);
}

function normalizeItems(items) {
  if (!Array.isArray(items) || !items.length) {
    throw new Error('Cart is empty.');
  }

  const lineItems = [];
  let total = 0;

  for (const item of items) {
    const trackId = Number(item?.trackId);
    const tier = String(item?.tier || 'loop');
    if (!Number.isFinite(trackId)) {
      throw new Error('Invalid track in cart.');
    }
    if (!['loop', 'pack', 'upgrade'].includes(tier)) {
      throw new Error('Invalid purchase tier.');
    }

    const track = getTrack(trackId);
    if (!track) {
      throw new Error(`Track #${trackId} is not available.`);
    }

    const unitAmount = tierPrice(track, tier);
    if (unitAmount == null || unitAmount <= 0) {
      throw new Error(`Track "${track.title}" is not available for ${TIER_LABELS[tier] || tier}.`);
    }

    total += unitAmount;
    lineItems.push({
      trackId,
      tier,
      title: track.title,
      unitAmount,
      sku: `${trackId}:${tier}`,
      name: `${track.title} — ${TIER_LABELS[tier] || tier}`,
    });
  }

  return {
    lineItems,
    total: formatMoneyAmount(total),
  };
}

module.exports = {
  DEFAULT_LOOP_PRICE,
  DEFAULT_PACK_PRICE,
  TIER_LABELS,
  getTrack,
  tierPrice,
  formatMoneyAmount,
  normalizeItems,
};
