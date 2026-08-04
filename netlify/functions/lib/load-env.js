const fs = require('fs');
const path = require('path');

let loaded = false;

/** Read project-root .env when a var is missing (local dev after .env edits without restart). */
function loadEnvIfNeeded() {
  if (loaded) return;
  loaded = true;

  const envPath = path.resolve(__dirname, '../../../.env');
  if (!fs.existsSync(envPath)) return;

  const text = fs.readFileSync(envPath, 'utf8');
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    const val = trimmed.slice(eq + 1).trim();
    if (process.env[key] === undefined) process.env[key] = val;
  }
}

module.exports = { loadEnvIfNeeded };
