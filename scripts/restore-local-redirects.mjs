/**
 * Restores comment-only _redirects for local Netlify Dev.
 * Production deploys overwrite _redirects with construction rules; this undoes that
 * so localhost:8888 serves the full store again.
 */
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

const localRedirects = `# Riskin Tracks — site mode toggle
#
# LOCAL DEV (npm run dev / localhost:8888): this file intentionally has NO active
# redirects so Netlify Dev serves index.html with the contact form and checkout.
#
# PRODUCTION (riskintracks.com): redirects are generated at deploy time by
# scripts/prepare-redirects.mjs (see netlify.toml build.command). After a local
# production deploy, run npm run dev (or restore-local-redirects) to reset this file.
#
# Go live on production: edit scripts/prepare-redirects.mjs to skip construction
# redirects for production, commit, and deploy.
`;

writeFileSync(join(root, '_redirects'), localRedirects, 'utf8');
console.log('restore-local-redirects: _redirects reset for local full store');
