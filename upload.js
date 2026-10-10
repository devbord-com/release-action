#!/usr/bin/env node
'use strict';
// Uploads all source maps from a folder to devbord, after the build and before the deploy. No dependencies (Node 18+).
//
//   DEVBORD_KEY=db_… node upload.js --url https://your.domain --project 12 --release my-app@1.0.0 \
//     [--commit <hash>] [--prefix ~/assets] [--deploy production] dist/assets
//
// --prefix is the path your files are served from on your site (default ~/). The key is an API key of the
// board with write access; put it in DEVBORD_KEY, not on the command line. Without a folder only the release
// is created (and the deploy reported).
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const opt = {};
const dirs = [];
for (let i = 0; i < args.length; i++) {
  if (args[i].startsWith('--')) opt[args[i].slice(2)] = args[++i];
  else dirs.push(args[i]);
}
const key = process.env.DEVBORD_KEY;
const fail = (msg) => { console.error(msg); process.exit(1); };
if (!key) fail('Put the API key in DEVBORD_KEY');
if (!opt.url || !opt.project || !opt.release) fail('Usage: upload.js --url <address> --project <number> --release <version> [--commit <hash>] [--prefix ~/path] [--deploy <environment>] [<folder>]');

const base = `${opt.url.replace(/\/+$/, '')}/api/v1/boards/${Number(opt.project)}/releases`;
const headers = { Authorization: `Bearer ${key}` };

/** @param {string} dir @returns {string[]} all .map files, including those in subfolders */
function mapsIn(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) return e.name === 'node_modules' ? [] : mapsIn(p);
    return e.name.endsWith('.map') ? [p] : [];
  });
}

async function call(method, url, body, type) {
  const res = await fetch(url, { method, headers: { ...headers, ...(type ? { 'Content-Type': type } : {}) }, body });
  const text = await res.text();
  if (!res.ok) { let msg = text; try { msg = JSON.parse(text).error || text; } catch { /* not JSON */ } throw new Error(`${res.status} ${msg}`); }
  return text ? JSON.parse(text) : {};
}

(async () => {
  await call('POST', base, JSON.stringify({ version: opt.release, commit: opt.commit || undefined }), 'application/json');
  const prefix = (opt.prefix || '~/').replace(/\/+$/, '');
  let n = 0;
  for (const dir of dirs) {
    for (const file of mapsIn(dir)) {
      const name = `${prefix}/${path.relative(dir, file).split(path.sep).join('/')}`;
      const out = await call('PUT', `${base}/${encodeURIComponent(opt.release)}/files?name=${encodeURIComponent(name)}`, fs.readFileSync(file), 'application/octet-stream');
      console.log(`${out.name}${out.debug_id ? ` (debug ID ${out.debug_id})` : ''}`);
      n++;
    }
  }
  if (opt.deploy) await call('POST', `${base}/${encodeURIComponent(opt.release)}/deploys`, JSON.stringify({ environment: opt.deploy }), 'application/json');
  console.log(`${n} source map(s) uploaded for ${opt.release}${opt.deploy ? `, deploy to ${opt.deploy} reported` : ''}`);
})().catch((e) => fail(`Failed: ${e.message}`));
