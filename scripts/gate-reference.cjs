/*
 * Fidelity gate: regenerate the reference dataset to a temp file and compare it
 * byte-for-byte against the committed src/reference-data/reference.json. Exits
 * non-zero on drift, so CI or a pre-commit check can enforce that the committed
 * JSON is exactly what the CoffeeScript source in reference-src/ produces.
 *
 * Usage: node scripts/gate-reference.cjs
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const committed = path.join(__dirname, '..', 'src', 'reference-data', 'reference.json');
const tmp = path.join(os.tmpdir(), 'reference-data.check.json');

execFileSync(process.execPath, [path.join(__dirname, 'generate-reference.cjs'), tmp], { stdio: 'ignore' });

const a = fs.readFileSync(tmp);
const b = fs.readFileSync(committed);
if (a.equals(b)) {
  console.log('GATE PASS: re-generation byte-identical to committed reference.json (' + b.length + ' bytes)');
  process.exit(0);
}
console.error('GATE FAIL: committed reference.json differs from a fresh generation of reference-src/.');
console.error('Regenerate with: npm run gen:reference   (or: just gen-reference)');
process.exit(1);
