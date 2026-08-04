/**
 * Upload local tracks/* files to Cloudflare R2 via S3-compatible API.
 *
 * Usage:
 *   node scripts/upload-r2.mjs              # skip objects already in R2 (default)
 *   node scripts/upload-r2.mjs --force        # re-upload everything
 *   node scripts/upload-r2.mjs --skip-existing
 *
 * Requires .env: R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY
 * (optional R2_ACCOUNT_ID, R2_BUCKET, R2_PUBLIC_BASE_URL)
 */
import { S3Client, PutObjectCommand, HeadObjectCommand } from '@aws-sdk/client-s3';
import { createReadStream, existsSync, readFileSync, readdirSync, statSync, writeFileSync } from 'fs';
import { join, extname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = fileURLToPath(new URL('.', import.meta.url));
const root = join(__dirname, '..');
const args = new Set(process.argv.slice(2));
const skipExisting = !args.has('--force');
const statePath = join(__dirname, '.r2-upload-state.json');

function loadEnv() {
  const map = {};
  const envPath = join(root, '.env');
  if (existsSync(envPath)) {
    for (const line of readFileSync(envPath, 'utf8').split(/\r?\n/)) {
      if (!line || line.trim().startsWith('#')) continue;
      const i = line.indexOf('=');
      if (i > 0) map[line.slice(0, i).trim()] = line.slice(i + 1).trim();
    }
  }
  for (const key of [
    'R2_ACCOUNT_ID', 'CLOUDFLARE_ACCOUNT_ID',
    'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY',
    'R2_BUCKET', 'R2_PUBLIC_BASE_URL',
  ]) {
    if (process.env[key]) map[key] = process.env[key];
  }
  return map;
}

function loadState() {
  if (!existsSync(statePath)) return {};
  try {
    return JSON.parse(readFileSync(statePath, 'utf8'));
  } catch {
    return {};
  }
}

function saveState(state) {
  writeFileSync(statePath, `${JSON.stringify(state, null, 2)}\n`, 'utf8');
}

function fileFingerprint(filePath) {
  const st = statSync(filePath);
  return `${st.size}-${st.mtimeMs}`;
}

function walkFiles(dir, base = dir, out = []) {
  for (const name of readdirSync(dir)) {
    if (name.startsWith('.~lock')) continue;
    const full = join(dir, name);
    const st = statSync(full);
    if (st.isDirectory()) walkFiles(full, base, out);
    else {
      const ext = extname(name).toLowerCase();
      if (['.mp3', '.zip', '.jpg', '.jpeg', '.png', '.json'].includes(ext)) {
        out.push(full.slice(base.length + 1).replace(/\\/g, '/'));
      }
    }
  }
  return out;
}

const env = loadEnv();
const accountId = env.R2_ACCOUNT_ID || env.CLOUDFLARE_ACCOUNT_ID || '90f505deba234410dfcef0f5a4b880f8';
const accessKeyId = env.R2_ACCESS_KEY_ID;
const secretAccessKey = env.R2_SECRET_ACCESS_KEY;
const bucket = env.R2_BUCKET || 'riskin-tracks';
const publicBase = env.R2_PUBLIC_BASE_URL || 'https://pub-45a1df6488174a1a84baf1ed003ac6dd.r2.dev';

if (!accessKeyId || !secretAccessKey) {
  console.error('Missing R2_ACCESS_KEY_ID or R2_SECRET_ACCESS_KEY in .env');
  console.error('Create token: Cloudflare Dashboard -> R2 -> Manage R2 API Tokens');
  process.exit(1);
}

const client = new S3Client({
  region: 'auto',
  endpoint: `https://${accountId}.r2.cloudflarestorage.com`,
  credentials: { accessKeyId, secretAccessKey },
});

const tracksRoot = join(root, 'tracks');
if (!existsSync(tracksRoot)) {
  console.error(`Missing tracks folder: ${tracksRoot}`);
  process.exit(1);
}

const files = walkFiles(tracksRoot, root).sort();
const state = loadState();

const contentType = (name) => {
  if (name.endsWith('.mp3')) return 'audio/mpeg';
  if (name.endsWith('.zip')) return 'application/zip';
  if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.json')) return 'application/json';
  return 'application/octet-stream';
};

async function objectExists(key) {
  try {
    await client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    return true;
  } catch {
    return false;
  }
}

let done = 0;
let uploaded = 0;
let skipped = 0;

for (const key of files) {
  done++;
  const filePath = join(root, key);
  const fingerprint = fileFingerprint(filePath);

  if (skipExisting) {
    if (state[key] === fingerprint) {
      console.log(`[${done}/${files.length}] skip (unchanged) ${key}`);
      skipped++;
      continue;
    }
    if (await objectExists(key)) {
      state[key] = fingerprint;
      console.log(`[${done}/${files.length}] skip (exists) ${key}`);
      skipped++;
      continue;
    }
  }

  console.log(`[${done}/${files.length}] upload ${key}`);
  await client.send(new PutObjectCommand({
    Bucket: bucket,
    Key: key,
    Body: createReadStream(filePath),
    ContentType: contentType(key),
  }));
  state[key] = fingerprint;
  uploaded++;
}

saveState(state);
console.log(`Done. uploaded=${uploaded} skipped=${skipped} total=${files.length}`);
console.log(`Public base: ${publicBase}/`);
