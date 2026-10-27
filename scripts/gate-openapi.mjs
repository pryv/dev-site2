/*
 * OpenAPI gate: the published definitions are generated at build time from the API
 * reference (src/reference-data/openapi.ts). This gate fails when a generated document
 * is invalid OpenAPI, misses or invents a documented method, carries an admin-only
 * method, uses an unmapped reference type, or (with --dist, after `astro build`) when
 * dist/open-api/3.0/ does not hold exactly the generated files.
 *
 * Usage: node scripts/gate-openapi.mjs [--dist]
 * Needs Node 24 (imports the TypeScript generator directly).
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';
import { Validator } from '@seriousme/openapi-schema-validator';
import { buildOpenApi, coveredMethodIds, knownTypeStrings } from '../src/reference-data/openapi.ts';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const ref = JSON.parse(fs.readFileSync(path.join(root, 'src/reference-data/reference.json'), 'utf8'));
const checkDist = process.argv.includes('--dist');

// Reference methods documented only as prose HTTP forms (the app authorization flow).
const TEXT_HTTP_ALLOWED = new Set(['auth-request', 'poll-request']);
// The admin reference is not published as OpenAPI (it describes the previous admin panel).
const PUBLISHED_FILES = ['api.yaml', 'api_open.yaml', 'api_system.yaml'];

const failures = [];
const fail = (msg) => failures.push(msg);

function methodsOf (sections, out = []) {
	for (const s of sections || []) {
		if (s.type === 'method') out.push(s);
		methodsOf(s.sections, out);
	}
	return out;
}

function typeStrings (sections, out = new Set()) {
	const props = (list) => { for (const p of list || []) { if (p.type) out.add(p.type); props(p.properties); } };
	for (const s of sections || []) {
		props(s.properties);
		props(s.params?.properties);
		for (const r of [].concat(s.result || [])) props(r?.properties);
		props(s.errors);
		typeStrings(s.sections, out);
	}
	return out;
}

function danglingRefs (doc) {
	const missing = new Set();
	const walk = (node) => {
		if (Array.isArray(node)) return node.forEach(walk);
		if (!node || typeof node !== 'object') return;
		if (typeof node.$ref === 'string') {
			const target = node.$ref.replace(/^#\//, '').split('/').reduce((o, k) => (o == null ? o : o[k]), doc);
			if (target === undefined) missing.add(node.$ref);
		}
		Object.values(node).forEach(walk);
	};
	walk(doc);
	return missing;
}

// The schema validator does not check this 3.0 rule; Redocly and code generators do.
function nullableWithoutType (doc) {
	const found = [];
	const walk = (node, at) => {
		if (Array.isArray(node)) return node.forEach((n, i) => walk(n, `${at}/${i}`));
		if (!node || typeof node !== 'object') return;
		if (node.nullable === true && node.type === undefined) found.push(at);
		for (const [k, v] of Object.entries(node)) walk(v, `${at}/${k}`);
	};
	walk(doc, '#');
	return found;
}

const userMethods = methodsOf(ref.sections);
const systemMethods = methodsOf(ref.system.sections);
const publishedIds = new Set([...userMethods, ...systemMethods].map(m => m.id));
const adminOnlyIds = methodsOf(ref.admin.sections).map(m => m.id).filter(id => !publishedIds.has(id));

// S3: every type string reachable from the published sources is mapped.
const known = new Set(knownTypeStrings);
const used = typeStrings([...ref.sections, ...ref.system.sections]);
for (const t of used) {
	if (!known.has(t)) fail(`unmapped reference type string: ${JSON.stringify(t)}`);
}
// Not a failure: an entry the reference no longer uses is only dead weight in the table.
const dead = knownTypeStrings.filter(t => !used.has(t));
if (dead.length) console.warn(`note: type table entries no longer used by the reference: ${dead.map(t => JSON.stringify(t)).join(', ')}`);

const validator = new Validator();
const docs = {};
for (const [source, methods, extra] of [['default', userMethods, ['service-info']], ['system', systemMethods, []]]) {
	let doc;
	try {
		doc = buildOpenApi(source, ref);
	} catch (err) {
		fail(`${source}: generator threw: ${err.message}`);
		continue;
	}
	docs[source] = doc;

	// S1: valid OpenAPI.
	const res = await validator.validate(doc);
	if (!res.valid) {
		const errors = Array.isArray(res.errors) ? res.errors : [res.errors];
		for (const e of errors.slice(0, 20)) fail(`${source}: invalid OpenAPI at ${e.instancePath || '/'}: ${e.message}`);
	}
	if (doc.openapi !== '3.0.3') fail(`${source}: openapi is ${doc.openapi}, expected 3.0.3`);
	for (const target of danglingRefs(doc)) fail(`${source}: $ref to a missing component ${target}`);
	for (const at of nullableWithoutType(doc)) fail(`${source}: nullable without type at ${at} (OpenAPI 3.0 ignores it)`);

	// S9: version, also in x-generated-from.
	if (doc.info?.version !== ref.version) fail(`${source}: info.version ${doc.info?.version} differs from the reference ${ref.version}`);
	if (doc['x-generated-from']?.referenceVersion !== ref.version) fail(`${source}: x-generated-from.referenceVersion missing or not ${ref.version}`);

	// Every security requirement names a declared scheme.
	const schemes = new Set(Object.keys(doc.components?.securitySchemes || {}));
	for (const [p, item] of Object.entries(doc.paths)) {
		for (const [verb, op] of Object.entries(item)) {
			for (const req of op.security || []) {
				for (const name of Object.keys(req)) if (!schemes.has(name)) fail(`${source}: ${verb.toUpperCase()} ${p} names unknown security scheme ${name}`);
			}
		}
	}

	// S2: coverage, exactly once each.
	const covered = coveredMethodIds(doc);
	const expected = [...methods.filter(m => typeof m.http === 'string').map(m => m.id), ...extra];
	for (const m of methods) {
		if (typeof m.http !== 'string' && !TEXT_HTTP_ALLOWED.has(m.id)) fail(`${source}: method ${m.id} has no string http and is not allow-listed`);
	}
	for (const id of expected) {
		const n = covered.filter(c => c === id).length;
		if (n !== 1) fail(`${source}: method ${id} covered ${n} times (expected 1)`);
	}
	for (const id of covered) if (!expected.includes(id)) fail(`${source}: operation names unknown method id ${id}`);
	for (const id of adminOnlyIds) if (covered.includes(id)) fail(`${source}: carries admin-only method ${id}`);
}

if (checkDist) {
	const dir = path.join(root, 'dist/open-api/3.0');
	const files = fs.existsSync(dir) ? fs.readdirSync(dir).sort() : [];
	if (files.join(',') !== [...PUBLISHED_FILES].sort().join(',')) fail(`dist/open-api/3.0 holds [${files.join(', ')}], expected [${PUBLISHED_FILES.join(', ')}]`);
	const read = (f) => fs.existsSync(path.join(dir, f)) ? fs.readFileSync(path.join(dir, f), 'utf8') : '';
	if (read('api_open.yaml') !== read('api.yaml')) fail('dist: api_open.yaml is not byte-identical to api.yaml');
	for (const [file, source] of [['api.yaml', 'default'], ['api_system.yaml', 'system']]) {
		const text = read(file);
		if (!text || !docs[source]) continue;
		const built = parse(text);
		delete built['x-generated-from'];
		const fresh = structuredClone(docs[source]);
		delete fresh['x-generated-from'];
		// The build renders links against the configured site URL; the gate uses the default.
		if (JSON.stringify(built) !== JSON.stringify(fresh)) fail(`dist: ${file} differs from a fresh generation`);
	}
}

if (failures.length) {
	console.error(`GATE FAIL: ${failures.length} problem(s) in the OpenAPI definitions`);
	for (const f of failures) console.error(`  - ${f}`);
	process.exit(1);
}
const counts = Object.entries(docs).map(([s, d]) => `${s}: ${coveredMethodIds(d).length} methods`).join(', ');
console.log(`GATE PASS: OpenAPI definitions valid and complete (${counts}${checkDist ? ', dist checked' : ''})`);
