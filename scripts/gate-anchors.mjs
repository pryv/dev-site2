/*
 * Anchor gate (post-build): every in-site link with a fragment must land on an element
 * id (or a legacy `name`) of its target page. Run after `astro build`, on a root build.
 *
 * The Starlight link validator does not see the custom (non-collection) pages: the API
 * references, event types, functional specifications and test results are excluded from
 * it, both as link sources and as link targets (see astro.config.mjs). This gate covers
 * them: it reads every built page under dist/, collects its ids, then checks
 *   - every local `href="#..."` on an excluded page,
 *   - every root-absolute `href="/<page>/#..."` on an excluded page (to any page), and
 *   - every root-absolute `href="/<page>/#..."` (from any page) pointing to an excluded page.
 * Links between ordinary content pages stay with the Starlight validator.
 *
 * Usage: node scripts/gate-anchors.mjs
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const dist = path.join(root, 'dist');

// Pages the Starlight link validator does not check (kept in step with astro.config.mjs).
const CUSTOM_PAGES = [
	'/reference/', '/reference-light/', '/reference-preview/', '/reference-system/',
	'/reference-admin/', '/event-types/', '/functional-specifications/', '/tests/',
];

if (!fs.existsSync(path.join(dist, 'index.html'))) {
	console.error('GATE FAIL: no dist/index.html: run `astro build` (root build, SITE_BASE unset) first.');
	process.exit(1);
}

/** All built HTML pages, keyed by their URL path (`/reference/`, `/`, `/404.html`). */
function pages (dir = dist, out = new Map()) {
	for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
		const p = path.join(dir, e.name);
		if (e.isDirectory()) pages(p, out);
		else if (e.name.endsWith('.html')) {
			const rel = '/' + path.relative(dist, p).split(path.sep).join('/');
			out.set(rel.endsWith('/index.html') || rel === '/index.html' ? rel.replace(/index\.html$/, '') : rel, p);
		}
	}
	return out;
}

const decodeEntities = (s) => s
	.replace(/&#x([0-9a-f]+);/gi, (_m, h) => String.fromCodePoint(parseInt(h, 16)))
	.replace(/&#(\d+);/g, (_m, d) => String.fromCodePoint(Number(d)))
	.replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');

const safeDecode = (s) => { try { return decodeURIComponent(s); } catch { return s; } };

const all = pages();
const html = new Map();
const idsCache = new Map();
const read = (url) => { if (!html.has(url)) html.set(url, fs.readFileSync(all.get(url), 'utf8')); return html.get(url); };
function idsOf (url) {
	if (!idsCache.has(url)) {
		const ids = new Set();
		for (const m of read(url).matchAll(/\s(?:id|name)="([^"]*)"/g)) ids.add(decodeEntities(m[1]));
		idsCache.set(url, ids);
	}
	return idsCache.get(url);
}

/** Normalise a link path to a page key of `all`, or null when it is no built page. */
function pageKey (p) {
	if (all.has(p)) return p;
	if (!p.endsWith('/') && all.has(p + '/')) return p + '/';
	return null;
}

const failures = [];
let checked = 0;
for (const url of all.keys()) {
	const sourceIsCustom = CUSTOM_PAGES.includes(url);
	for (const m of read(url).matchAll(/\shref="([^"]*#[^"]*)"/g)) {
		const href = decodeEntities(m[1]);
		const hash = href.indexOf('#');
		const before = href.slice(0, hash).split('?')[0];
		const fragment = safeDecode(href.slice(hash + 1));
		let target;
		if (before === '') {
			if (!sourceIsCustom) continue; // ordinary pages: the Starlight validator's job
			target = url;
		} else if (before.startsWith('/') && !before.startsWith('//')) {
			const key = pageKey(before);
			if (key === null) {
				if (sourceIsCustom || CUSTOM_PAGES.includes(before + '/')) failures.push(`${url}: href="${href}" points to no built page`);
				continue;
			}
			if (!sourceIsCustom && !CUSTOM_PAGES.includes(key)) continue;
			target = key;
		} else continue; // external, protocol-relative or relative: out of scope
		if (fragment === '' || fragment === 'top' || fragment === '_top') continue;
		checked++;
		if (!idsOf(target).has(fragment)) failures.push(`${url}: href="${href}" has no target id on ${target}`);
	}
}

if (failures.length) {
	const unique = [...new Set(failures)];
	console.error(`GATE FAIL: ${unique.length} link(s) to a missing anchor:`);
	for (const f of unique) console.error('  ' + f);
	process.exit(1);
}
console.log(`GATE PASS: ${checked} fragment link(s) into the custom pages all resolve (${all.size} pages read).`);
