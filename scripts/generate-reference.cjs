/*
 * Generate src/reference-data/reference.json from the CoffeeScript reference
 * source in reference-src/.
 *
 * The source (reference-src/) was migrated out of the now-archived legacy
 * dev-site repo so the reference dataset is regenerable from within this repo.
 * Output is DETERMINISTIC: every source of nondeterminism the example fixtures
 * touch (cuid, Date, Math.random, crypto.randomBytes) is frozen below, so a
 * regeneration is byte-identical on every run and machine. Run the gate
 * (scripts/gate-reference.cjs) to verify a fresh generation matches the
 * committed file.
 *
 * Usage:
 *   node scripts/generate-reference.cjs [outfile]
 * Default outfile: src/reference-data/reference.json
 */
const fs = require('fs');
const path = require('path');
const Module = require('module');

const SOURCE_INDEX = path.join(__dirname, '..', 'reference-src', 'index.js');
const DEFAULT_OUT = path.join(__dirname, '..', 'src', 'reference-data', 'reference.json');

// Deterministic cuid stub (freeze example ids). Intercepts before the real
// module is resolved, so `cuid` need not be installed.
let counter = 0;
const pad = (n) => 'c' + String(n).padStart(24, '0');
const origLoad = Module._load;
Module._load = function (request) {
  if (request === 'cuid') {
    const f = () => pad(counter++);
    f.slug = () => 's' + String(counter++);
    f.fingerprint = () => 'fingerprint00';
    return f;
  }
  return origLoad.apply(this, arguments);
};

// Freeze Date fully (both `new Date()` and `Date.now()`).
const FIXED_MS = 1735689600000; // 2025-01-01T00:00:00Z
const RealDate = Date;
class FixedDate extends RealDate {
  constructor (...args) {
    if (args.length === 0) super(FIXED_MS);
    else super(...args);
  }
  static now () { return FIXED_MS; }
}
global.Date = FixedDate;

// Deterministic Math.random (mulberry32).
let s = 0x12345678;
Math.random = () => {
  s |= 0; s = (s + 0x6D2B79F5) | 0;
  let t = Math.imul(s ^ (s >>> 15), 1 | s);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};

// Deterministic crypto.randomBytes.
const crypto = require('crypto');
let cb = 0;
crypto.randomBytes = (n) => {
  const b = Buffer.alloc(n);
  for (let i = 0; i < n; i++) b[i] = (cb++ * 37 + 11) & 0xff;
  return b;
};

// index.js self-registers CoffeeScript, then assembles the reference object.
const ref = require(SOURCE_INDEX);

// Detect function values (JSON.stringify would silently drop them).
const fns = [];
(function walk (o, p) {
  if (o && typeof o === 'object') {
    for (const k of Object.keys(o)) {
      const v = o[k];
      if (typeof v === 'function') fns.push(p + '.' + k);
      else if (v && typeof v === 'object') walk(v, p + '.' + k);
    }
  }
})(ref, 'root');

let methods = 0, sections = 0;
(function w (o) {
  if (o && typeof o === 'object') {
    if (o.type === 'method') methods++;
    if (Array.isArray(o.sections)) sections += o.sections.length;
    for (const k in o) if (o[k] && typeof o[k] === 'object') w(o[k]);
  }
})(ref);

const json = JSON.stringify(ref, null, 2);
const out = process.argv[2] || DEFAULT_OUT;
fs.writeFileSync(out, json);

console.log('version       :', ref.version);
console.log('root keys     :', Object.keys(ref).join(', '));
console.log('top sections  :', ref.sections.length);
console.log('system/admin  :', ref.system && ref.system.id, '/', ref.admin && ref.admin.id);
console.log('total methods :', methods);
console.log('nested sects  :', sections);
console.log('function vals :', fns.length, fns.length ? fns.slice(0, 20) : '(none - safe to serialize)');
console.log('json chars    :', json.length, '->', out);
