// OpenAPI 3.0.3 generator for the API reference. Pure function of the reference data
// (reference.json): no I/O, deterministic output. The published files under
// /open-api/3.0/ are rendered from it at build time, never hand-edited.
//
// Rules: map only what the reference states. Every property `type` string goes through
// TYPE_TABLE; an unknown string throws, so a new free-text type fails the build instead
// of degrading silently.
import type { ApiReference, Section, Property, ResultObject, Example } from './types';

export type OpenApiSource = 'default' | 'system';

export interface OpenApiOptions {
	/** Absolute site URL used to turn in-page links into absolute ones. */
	siteUrl?: string;
	/** Short commit of the reference source, recorded in `x-generated-from` when known. */
	commit?: string;
}

type Schema = Record<string, unknown>;
type Operation = Record<string, unknown>;

const OPENAPI_VERSION = '3.0.3';
const ISSUES_URL = 'https://github.com/pryv/open-pryv.io/issues';

// ---------- type strings ----------

const ref = (name: string): Schema => ({ $ref: `#/components/schemas/${name}` });
const arrayOf = (items: Schema): Schema => ({ type: 'array', items });
const enumOf = (...values: string[]): Schema => ({ type: 'string', enum: values });
const prose = (type: string, text: string): Schema => ({ type, description: `Described in the reference as: ${text}.` });

/** Every free-text `type` string of the user and system references, mapped explicitly. */
const TYPE_TABLE: Record<string, () => Schema> = {
	string: () => ({ type: 'string' }),
	number: () => ({ type: 'number' }),
	boolean: () => ({ type: 'boolean' }),
	object: () => ({ type: 'object' }),
	Object: () => ({ type: 'object' }),
	array: () => arrayOf({}),
	'any type': () => ({}),
	'object or array': () => ({ oneOf: [{ type: 'object' }, arrayOf({})] }),
	'`true`': () => ({ type: 'boolean', enum: [true] }),
	'[identifier](#data-structure-identifier)': () => ref('identifier'),
	// Non-breaking spaces around the bar, as in the reference source. Both alternatives are
	// strings, so anyOf (oneOf would never match exactly one).
	'[identifier](#data-structure-identifier) | string': () => ({ anyOf: [ref('identifier'), { type: 'string' }] }),
	'[timestamp](#data-structure-timestamp)': () => ref('timestamp'),
	'[event](#data-structure-event)': () => ref('event'),
	'[stream](#data-structure-stream)': () => ref('stream'),
	'[access](#data-structure-access)': () => ref('access'),
	'[webhook](#data-structure-webhook)': () => ref('webhook'),
	'[key-value](#data-structure-key-value)': () => ref('key-value'),
	'[key-value](#methods-key-value-)': () => ref('key-value'),
	'[item deletion](#data-structure-item-deletion)': () => ref('item-deletion'),
	'[external id](#data-structure-external-id)': () => ref('external-id'),
	'[integrity](#data-structure-integrity)': () => ref('integrity'),
	'[account information](#data-structure-account)': () => ref('account'),
	'[account](#data-structure-account)': () => ref('account'),
	'array of strings': () => arrayOf({ type: 'string' }),
	'array of objects': () => arrayOf({ type: 'object' }),
	'array of [item deletions](#data-structure-item-deletion)': () => arrayOf(ref('item-deletion')),
	'array of [events](#data-structure-event)': () => arrayOf(ref('event')),
	'array of [accesses](#data-structure-access)': () => arrayOf(ref('access')),
	'array of deleted [accesses](#data-structure-access)': () => arrayOf(ref('access')),
	'array of [streams](#data-structure-stream)': () => arrayOf(ref('stream')),
	'array of streams': () => arrayOf(ref('stream')),
	'array of [webhooks](#data-structure-webhook)': () => arrayOf(ref('webhook')),
	'array of [external ids](#data-structure-external-id)': () => arrayOf(ref('external-id')),
	'array of [identifier](#data-structure-identifier)': () => arrayOf(ref('identifier')),
	'array of [content query](#data-structure-content-query) conditions': () => arrayOf(ref('content-query')),
	'array of stream [identifiers](#data-structure-identifier) or [streams query](#data-structure-streams-query)':
		() => ({ oneOf: [arrayOf(ref('identifier')), ref('streams-query')] }),
	'array of errors': () => arrayOf(ref('error')),
	'array of invite objects': () => arrayOf(prose('object', 'invite object')),
	'array of permission request objects': () => arrayOf(prose('object', 'permission request object')),
	'array of permission objects': () => arrayOf(prose('object', 'permission object')),
	'array of outcome objects': () => arrayOf(prose('object', 'outcome object')),
	'array of attachment objects': () => arrayOf(prose('object', 'attachment object')),
	'array of call results': () => arrayOf(prose('object', 'call result')),
	'array of Run objects': () => arrayOf(prose('object', 'Run object')),
	'Run object': () => prose('object', 'Run object'),
	'Array of fields': () => arrayOf({ description: 'Described in the reference as: field.' }),
	'Array of data points': () => arrayOf({ description: 'Described in the reference as: data point.' }),
	'`totp`|`sms`': () => enumOf('totp', 'sms'),
	'`read`|`contribute`|`manage`': () => enumOf('read', 'contribute', 'manage'),
	'`read`|`contribute`|`manage`|`create-only`': () => enumOf('read', 'contribute', 'manage', 'create-only'),
	'`self`|`target`': () => enumOf('self', 'target'),
	'`hint`|`forced`': () => enumOf('hint', 'forced'),
	'`mail`|`audit-only`': () => enumOf('mail', 'audit-only'),
	'`NEED_SIGNIN`': () => enumOf('NEED_SIGNIN'),
	'`ACCEPTED`': () => enumOf('ACCEPTED'),
	'`REFUSED`': () => enumOf('REFUSED'),
	'`default`|`trashed`|`all`': () => enumOf('default', 'trashed', 'all'),
	'`default`|`all`': () => enumOf('default', 'all'),
	'`app`': () => enumOf('app'),
	'`control`': () => enumOf('control'),
	'`personal`|`app`|`shared`': () => enumOf('personal', 'app', 'shared'),
	'`selfRevoke`|`secretSharing`|`webhooks`': () => enumOf('selfRevoke', 'secretSharing', 'webhooks'),
	'`forbidden`|`allowed`': () => enumOf('forbidden', 'allowed'),
	'`active`|`inactive`': () => enumOf('active', 'inactive'),
	'`default`|`never`|`date`|`inactivity`': () => enumOf('default', 'never', 'date', 'inactivity'),
	'`never`|`date`|`inactivity`': () => enumOf('never', 'date', 'inactivity'),
	'`delete`|`transfer`': () => enumOf('delete', 'transfer'),
	'`user`|`operator`|`none`': () => enumOf('user', 'operator', 'none'),
	'`owner`|`delegate`': () => enumOf('owner', 'delegate'),
	'`date`|`inactivity`|`minimum-notice`': () => enumOf('date', 'inactivity', 'minimum-notice'),
	'`available`|`no-email`|`not-configured`': () => enumOf('available', 'no-email', 'not-configured'),
};

/** The type strings the generator knows (the gate checks the reference against it). */
export const knownTypeStrings: readonly string[] = Object.keys(TYPE_TABLE);

export function mapType (type: string): Schema {
	const make = TYPE_TABLE[type];
	if (!make) throw new Error(`OpenAPI generator: unmapped reference type string ${JSON.stringify(type)}`);
	return make();
}

/**
 * Data structures the reference describes in prose only (no property table). The type
 * is the one their description states; unknown prose-only structures throw.
 */
const PROSE_STRUCTURES: Record<string, Schema> = {
	identifier: { type: 'string' }, // "A string uniquely identifying an item"
	timestamp: { type: 'number' }, // "A positive floating-point number"
	'key-value': { type: 'object', additionalProperties: true }, // "An object (key-value map)"
	integrity: { type: 'string' }, // "An integrity hash ... prefixed with the data structure"
	'streams-query': { type: 'object' }, // the query object syntax
	'content-query': { type: 'object' }, // one condition of the array
};

// ---------- markdown links ----------

function absolutize (text: string | undefined, pageUrl: string, siteUrl: string): string | undefined {
	if (!text) return text;
	return text
		.replace(/\]\(#/g, `](${pageUrl}#`)
		.replace(/\]\(\/(?!\/)/g, `](${siteUrl}/`);
}

// ---------- properties to schemas ----------

// `required` is emitted for request parameters only: there "optional" is the documented
// contract. In results and data structures the reference does not mark absent-able
// fields consistently, so requiring them would state constraints it does not.
interface Ctx { pageUrl: string; siteUrl: string; withRequired?: boolean }

function describe (base: Schema, prop: Property, ctx: Ctx): Schema {
	const notes: string[] = [];
	if (typeof prop.optional === 'string') notes.push(`Optional ${prop.optional}.`);
	if (prop.unique) notes.push(typeof prop.unique === 'string' ? `Unique ${prop.unique}.` : 'Unique.');
	// `readOnly: "(except at creation)"` qualifies the flag: settable at creation, so not an
	// OpenAPI readOnly (which forbids the property in every request); stated in the text.
	if (typeof prop.readOnly === 'string') notes.push(`Read-only ${prop.readOnly}.`);
	const readOnly = prop.readOnly === true;
	const text = [absolutize(prop.description, ctx.pageUrl, ctx.siteUrl)?.trim(), ...notes].filter(Boolean).join('\n\n');
	let out: Schema = { ...base };
	if (prop.nullable && out.$ref) {
		// 3.0 cannot make a referenced schema nullable (`allOf` keeps the target's type);
		// for the primitive prose structures, inline the primitive instead of the $ref.
		const name = (out.$ref as string).replace('#/components/schemas/', '');
		const primitive = PROSE_STRUCTURES[name];
		if (!primitive || primitive.type === 'object') throw new Error(`OpenAPI generator: nullable reference to '${name}' is not supported`);
		out = { ...primitive };
	}
	if (readOnly) out.readOnly = true;
	if (prop.nullable) out.nullable = true;
	if (out.$ref && text) {
		// A $ref sibling is ignored in 3.0: wrap so the description survives.
		return { allOf: [{ $ref: out.$ref }], ...(readOnly ? { readOnly: true } : {}), description: text };
	}
	if (text) out.description = out.description ? `${out.description as string}\n\n${text}` : text;
	return out;
}

function propertySchema (prop: Property, ctx: Ctx): Schema {
	let base: Schema = prop.type ? mapType(prop.type) : {};
	if (prop.properties && prop.properties.length) {
		const nested = objectSchema(prop.properties, ctx);
		if (base.type === 'array') base = { ...base, items: { ...(base.items as Schema), ...nested } };
		else if (base.$ref) base = { allOf: [{ $ref: base.$ref }, nested] };
		else base = { ...base, ...nested, type: 'object' };
	}
	return describe(base, prop, ctx);
}

function keysOf (prop: Property): string[] {
	return Array.isArray(prop.key) ? prop.key : [prop.key];
}

/** Object schema from a property table; dotted keys (`meta.serial`) nest. */
export function objectSchema (props: Property[], ctx: Ctx): Schema {
	const properties: Record<string, Schema> = {};
	const required: string[] = [];
	for (const prop of props) {
		const alternatives = keysOf(prop);
		for (const key of alternatives) {
			const path = key.split('.');
			let target = properties;
			for (const segment of path.slice(0, -1)) {
				const holder = (target[segment] ??= { type: 'object', properties: {} });
				target = (holder.properties ??= {}) as Record<string, Schema>;
			}
			target[path[path.length - 1]] = propertySchema(prop, ctx);
		}
		if (ctx.withRequired && alternatives.length === 1 && !prop.optional && !alternatives[0].includes('.')) required.push(alternatives[0]);
	}
	const out: Schema = { type: 'object', properties };
	if (required.length) out.required = required;
	return out;
}

// ---------- reference walking ----------

interface MethodEntry { section: Section; parent: Section; tag: string }

function collectMethods (sections: Section[] | undefined, parent: Section, tag: string, out: MethodEntry[]): void {
	for (const s of sections || []) {
		if (s.type === 'method') out.push({ section: s, parent, tag });
		else collectMethods(s.sections, s, s.title || tag, out);
	}
}

function findSection (sections: Section[] | undefined, id: string): Section | undefined {
	for (const s of sections || []) {
		if (s.id === id) return s;
		const found = findSection(s.sections, id);
		if (found) return found;
	}
	return undefined;
}

// ---------- routes ----------

interface Route { verb: string; path: string; note?: string }

/** `"GET /events/{id}/{fileId}[/{fileName}]"` -> the base path, the optional part noted. */
export function parseRoute (http: string): Route {
	const [verb, rawPath] = http.trim().split(/\s+/);
	const optional = rawPath.match(/\[(.+)\]$/);
	if (!optional) return { verb: verb.toLowerCase(), path: rawPath };
	const path = rawPath.slice(0, optional.index);
	const variants = optional[1].split('|').map(v => `\`${path}${v}\``).join(', ');
	return { verb: verb.toLowerCase(), path, note: `Also served as ${variants}.` };
}

const pathParamNames = (path: string): string[] => [...path.matchAll(/\{(\w+)\}/g)].map(m => m[1]);

function httpHint (prop: Property): string {
	if (!prop.http) return '';
	return (typeof prop.http === 'string' ? prop.http : (prop.http.text || prop.http.code || '')).toLowerCase();
}

/** The data structure a description points at when it names exactly one. */
function singleStructureLink (text: string | undefined): string | undefined {
	if (!text) return undefined;
	const ids = [...new Set([...text.matchAll(/\(#data-structure-([\w-]+)\)/g)].map(m => m[1]))];
	return ids.length === 1 ? ids[0] : undefined;
}

// Methods whose transport the property table cannot express.
const MULTIPART_METHODS = new Set(['events.addAttachment']);
const BINARY_RESULTS: Record<string, string> = { 'events.getAttachment': '*/*', 'events.getPreview': 'image/jpeg' };
// No access token: the same list the reference's cURL helper treats as token-less.
const UNAUTHENTICATED = new Set(['auth.login', 'mfa.login', 'account.requestPasswordReset', 'account.resetPassword', 'mfa.recover', 'service-info']);

function statusOf (http: string | undefined): string {
	const code = (http || '').match(/^\d{3}/);
	return code ? code[0] : '200';
}

function buildParameters (m: Section, route: Route, baseCtx: Ctx): { parameters: Schema[]; body?: Schema; bodyType?: string } {
	const ctx: Ctx = { ...baseCtx, withRequired: true };
	const props = m.params?.properties || [];
	const parameters: Schema[] = [];
	const inPath = new Set(pathParamNames(route.path));
	const rest: Property[] = [];
	let bodyFromUpdate: Schema | undefined;

	for (const name of inPath) {
		const prop = props.find(p => keysOf(p).includes(name));
		const schema = prop ? propertySchema(prop, ctx) : { type: 'string' };
		const description = schema.description;
		delete schema.description;
		parameters.push({ in: 'path', name, required: true, schema, ...(description ? { description } : {}) });
	}
	for (const prop of props) {
		if (keysOf(prop).some(k => inPath.has(k))) continue;
		const hint = httpHint(prop);
		if (hint.includes('request body') && keysOf(prop)[0] === 'update') {
			const linked = prop.properties ? undefined : singleStructureLink(prop.description);
			bodyFromUpdate = linked ? describe(ref(linked), prop, ctx) : propertySchema(prop, ctx);
			continue;
		}
		if (hint.includes('query')) {
			parameters.push(queryParam(prop, ctx));
			continue;
		}
		rest.push(prop);
	}

	const hasBody = route.verb === 'post' || route.verb === 'put';
	if (!hasBody) {
		for (const prop of rest) parameters.push(queryParam(prop, ctx));
		return { parameters };
	}
	if (MULTIPART_METHODS.has(m.id)) {
		return {
			parameters,
			bodyType: 'multipart/form-data',
			body: { type: 'object', additionalProperties: { type: 'string', format: 'binary' }, description: 'One or more files, one form part each.' },
		};
	}
	if (m.id === 'callBatch') {
		return { parameters, body: arrayOf(objectSchema(rest, ctx)) };
	}
	if (bodyFromUpdate) return { parameters, body: bodyFromUpdate };
	const linked = singleStructureLink(m.params?.description);
	if (linked && !rest.length) return { parameters, body: ref(linked) };
	if (linked) return { parameters, body: { allOf: [ref(linked), objectSchema(rest, ctx)] } };
	if (!rest.length) return { parameters };
	return { parameters, body: objectSchema(rest, ctx) };
}

function queryParam (prop: Property, ctx: Ctx): Schema {
	const schema = propertySchema(prop, ctx);
	const description = schema.description;
	delete schema.description;
	const p: Schema = { in: 'query', name: keysOf(prop)[0], required: !prop.optional, schema };
	if (description) p.description = description;
	if (schema.type === 'array') { p.style = 'form'; p.explode = true; }
	if (isObjectLike(schema)) { p.style = 'deepObject'; p.explode = true; }
	return p;
}

/** Whether a schema serializes as an object (a $ref to a primitive structure does not). */
function isObjectLike (schema: Schema): boolean {
	if (schema.type === 'object') return true;
	if (schema.type !== undefined) return false;
	const target = (schema.$ref as string | undefined) ?? ((schema.allOf as Schema[] | undefined)?.[0]?.$ref as string | undefined);
	if (!target) return false;
	const primitive = PROSE_STRUCTURES[target.replace('#/components/schemas/', '')];
	return !primitive || primitive.type === 'object';
}

// ---------- results and errors ----------

function resultContent (m: Section, r: ResultObject, ctx: Ctx): Schema | undefined {
	if (statusOf(r.http) === '204') return undefined;
	const binary = BINARY_RESULTS[m.id];
	if (binary) return { [binary]: { schema: { type: 'string', format: 'binary' } } };
	// A 302 can carry a body too (mfa.login: { mfaToken, mfaMethod }).
	const schema: Schema = r.properties && r.properties.length ? objectSchema(r.properties, ctx) : { type: 'object' };
	const properties = (schema.properties ??= {}) as Record<string, Schema>;
	properties.meta = ref('meta');
	return { 'application/json': { schema } };
}

function buildResponses (m: Section, ctx: Ctx): Record<string, Schema> {
	const responses: Record<string, Schema> = {};
	const results = m.result ? (Array.isArray(m.result) ? m.result : [m.result]) : [];
	for (const r of results) {
		const code = statusOf(r.http);
		const description = [r.title, absolutize(r.description, ctx.pageUrl, ctx.siteUrl)?.trim()].filter(Boolean).join(': ') || r.http || 'Result';
		const content = resultContent(m, r, ctx);
		const existing = responses[code];
		if (!existing) {
			responses[code] = { description, ...(content ? { content } : {}) };
			continue;
		}
		existing.description = `${existing.description as string}\n\nOr: ${description}`;
		if (content && existing.content) {
			const a = (existing.content as Record<string, Schema>)['application/json'];
			const b = (content as Record<string, Schema>)['application/json'];
			if (a && b) a.schema = alternatives([a.schema as Schema, b.schema as Schema]);
		}
	}
	if (!results.length) responses['200'] = { description: 'See the method description.' };
	const byCode = new Map<string, Property[]>();
	for (const e of m.errors || []) {
		const code = statusOf(typeof e.http === 'string' ? e.http : e.http?.code);
		byCode.set(code, [...(byCode.get(code) || []), e]);
	}
	for (const [code, errs] of byCode) {
		const ids = [...new Set(errs.flatMap(keysOf))];
		const lines = errs.map(e => `- \`${keysOf(e).join('`, `')}\`: ${(absolutize(e.description, ctx.pageUrl, ctx.siteUrl) || '').trim()}`);
		const entry: Schema = {
			description: `Specific errors:\n\n${lines.join('\n')}`,
			'x-pryv-error-ids': ids,
			content: { 'application/json': { schema: ref('error-response') } },
		};
		if (responses[code]) responses[code].description = `${responses[code].description as string}\n\n${entry.description as string}`;
		else responses[code] = entry;
	}
	responses.default = { $ref: '#/components/responses/usual-errors' };
	return responses;
}

// ---------- examples ----------

function exampleName (ex: Example, i: number, taken: Record<string, unknown> = {}): string {
	const base = (ex.title || '').replace(/<[^>]*>/g, '').replace(/[^\w]+/g, '-').replace(/^-|-$/g, '').toLowerCase().slice(0, 48) || `example-${i + 1}`;
	let name = base;
	for (let n = 2; name in taken; n++) name = `${base}-${n}`; // two examples with the same title
	return name;
}

function requestExample (params: Record<string, unknown> | unknown[], route: Route): unknown {
	if (Array.isArray(params)) return params; // callBatch: the body is the array of calls
	const body: Record<string, unknown> = { ...params };
	for (const name of pathParamNames(route.path)) delete body[name]; // they travel in the path
	const verb = route.verb;
	if (verb === 'put' && body.update && typeof body.update === 'object') return body.update;
	return body;
}

// ---------- document ----------

function buildOperation (entry: MethodEntry, route: Route, source: OpenApiSource, ctx: Ctx): Operation {
	const m = entry.section;
	const { parameters, body, bodyType } = buildParameters(m, route, ctx);
	const description = [absolutize(m.description, ctx.pageUrl, ctx.siteUrl)?.trim(), absolutize(m.params?.description, ctx.pageUrl, ctx.siteUrl)?.trim(), route.note]
		.filter(Boolean).join('\n\n');
	const op: Operation = {
		operationId: m.id,
		summary: m.title || m.id,
		tags: [entry.tag],
		'x-pryv-method-ids': [m.id],
	};
	if (description) op.description = description;
	if (m.server) op['x-pryv-server'] = m.server;
	if (m.trustedOnly || entry.parent.trustedOnly) op['x-pryv-trusted-only'] = true;
	if (parameters.length) op.parameters = parameters;
	if (body) {
		const media: Schema = { schema: body };
		const examples: Record<string, Schema> = {};
		(m.examples || []).forEach((ex, i) => {
			if (ex.params && typeof ex.params === 'object' && !ex.content) {
				examples[exampleName(ex, i, examples)] = { value: requestExample(ex.params as Record<string, unknown>, route) };
			}
		});
		if (Object.keys(examples).length && bodyType !== 'multipart/form-data') media.examples = examples;
		op.requestBody = { required: true, content: { [bodyType || 'application/json']: media } };
	}
	op.responses = buildResponses(m, ctx);
	addResponseExamples(op, m);
	op.security = securityFor(entry, source);
	return op;
}

function addResponseExamples (op: Operation, m: Section): void {
	const responses = op.responses as Record<string, Schema>;
	(m.examples || []).forEach((ex, i) => {
		if (!ex.result || typeof ex.params !== 'object' || ex.content) return;
		const results = m.result ? (Array.isArray(m.result) ? m.result : [m.result]) : [];
		const code = ex.resultHTTP ? statusOf(ex.resultHTTP) : statusOf(results[0]?.http);
		const media = (responses[code]?.content as Record<string, Schema> | undefined)?.['application/json'];
		if (!media) return;
		const examples = (media.examples ??= {}) as Record<string, Schema>;
		examples[exampleName(ex, i, examples)] = { value: ex.result };
	});
}

function securityFor (entry: MethodEntry, source: OpenApiSource): Schema[] {
	if (source === 'system') {
		return entry.section.adminOnly || entry.parent.adminOnly ? [{ adminKey: [] }] : [];
	}
	if (UNAUTHENTICATED.has(entry.section.id)) return [];
	return [{ tokenHeader: [] }, { tokenQuery: [] }];
}

/**
 * Combine alternative schemas: identical ones collapse, distinct ones become an anyOf
 * (the reference does not make alternatives mutually exclusive, so oneOf would reject
 * valid values that match more than one shape).
 */
function alternatives (schemas: Schema[]): Schema {
	const unique: Schema[] = [];
	for (const s of schemas) {
		const flat = (s.anyOf as Schema[] | undefined) || [s];
		for (const f of flat) if (!unique.some(u => JSON.stringify(u) === JSON.stringify(f))) unique.push(f);
	}
	if (!unique.length) return {};
	return unique.length === 1 ? unique[0] : { anyOf: unique };
}

/** A schema labelled with a title; a $ref cannot carry siblings in 3.0, so wrap it. */
function titled (title: string, schema: Schema): Schema {
	return schema.$ref ? { title, allOf: [schema] } : { title, ...schema };
}

/** Merge operations that share a path and verb (e.g. events.create and hfs.create). */
function merge (ops: Operation[]): Operation {
	if (ops.length === 1) return ops[0];
	const [first] = ops;
	const merged: Operation = { ...first };
	merged.summary = ops.map(o => o.summary).join(' / ');
	merged['x-pryv-method-ids'] = ops.flatMap(o => o['x-pryv-method-ids'] as string[]);
	merged.tags = [...new Set(ops.flatMap(o => o.tags as string[]))];
	merged.description = ops.map(o => `**${o.operationId as string}**: ${(o.description as string | undefined) || o.summary as string}`).join('\n\n');
	const params = new Map<string, Schema>();
	for (const o of ops) for (const p of (o.parameters as Schema[] | undefined) || []) params.set(`${p.in as string}:${p.name as string}`, p);
	if (params.size) merged.parameters = [...params.values()];
	const bodies = ops.map(o => o.requestBody as Schema | undefined).filter((b): b is Schema => !!b);
	if (bodies.length) {
		const schemas = ops.map(o => {
			const content = (o.requestBody as Schema | undefined)?.content as Record<string, Schema> | undefined;
			return content?.['application/json']?.schema as Schema | undefined;
		});
		const present = schemas.filter((s): s is Schema => !!s);
		const combined = alternatives(present);
		// Distinct bodies are labelled with the method they belong to.
		const schema = combined.anyOf
			? { anyOf: ops.flatMap((o, i) => (schemas[i] ? [titled(o.operationId as string, schemas[i] as Schema)] : [])) }
			: combined;
		const media: Schema = { schema };
		const examples = mergeExamples(ops.map(o => ((o.requestBody as Schema | undefined)?.content as Record<string, Schema> | undefined)?.['application/json']));
		if (examples) media.examples = examples;
		merged.requestBody = { required: true, content: { 'application/json': media } };
	}
	const responses: Record<string, Schema> = {};
	for (const o of ops) {
		for (const [code, r] of Object.entries(o.responses as Record<string, Schema>)) {
			if (!responses[code]) { responses[code] = structuredClone(r); continue; }
			if (code === 'default') continue;
			const target = responses[code];
			if (r.description !== target.description) {
				target.description = `${target.description as string}\n\nOr (${o.operationId as string}): ${r.description as string}`;
			}
			const a = (target.content as Record<string, Schema> | undefined)?.['application/json'];
			const b = (r.content as Record<string, Schema> | undefined)?.['application/json'];
			if (a && b) {
				a.schema = alternatives([a.schema as Schema, b.schema as Schema]);
				const examples = mergeExamples([a, b]);
				if (examples) a.examples = examples;
			} else if (b && !a) target.content = structuredClone(r.content);
		}
	}
	merged.responses = responses;
	// Any requirement of any merged method is acceptable; an unauthenticated one adds `{}`.
	const requirements = new Map<string, Schema>();
	for (const o of ops) {
		const sec = o.security as Schema[];
		if (!sec.length) requirements.set('{}', {});
		for (const r of sec) requirements.set(JSON.stringify(r), r);
	}
	merged.security = [...requirements.values()];
	return merged;
}

/** Examples of several media objects, keeping every one (names suffixed on collision). */
function mergeExamples (medias: (Schema | undefined)[]): Record<string, Schema> | undefined {
	const out: Record<string, Schema> = {};
	for (const media of medias) {
		for (const [name, ex] of Object.entries((media?.examples as Record<string, Schema> | undefined) || {})) {
			let key = name;
			for (let n = 2; key in out && JSON.stringify(out[key]) !== JSON.stringify(ex); n++) key = `${name}-${n}`;
			out[key] = ex;
		}
	}
	return Object.keys(out).length ? out : undefined;
}

function dataStructureSchemas (refData: ApiReference, ctx: Ctx): Record<string, Schema> {
	const ds = findSection(refData.sections, 'data-structure');
	const schemas: Record<string, Schema> = {};
	for (const s of ds?.sections || []) {
		const description = absolutize(s.description, ctx.pageUrl, ctx.siteUrl)?.trim();
		let schema: Schema;
		if (s.properties && s.properties.length) schema = objectSchema(s.properties, ctx);
		else if (PROSE_STRUCTURES[s.id]) schema = { ...PROSE_STRUCTURES[s.id] };
		else throw new Error(`OpenAPI generator: data structure '${s.id}' has no property table and no prose mapping`);
		if (s.title) schema.title = s.title;
		if (description) schema.description = description;
		schemas[s.id] = schema;
	}
	const metaSection = findSection(refData.sections, 'method-results');
	const meta = objectSchema(metaSection?.properties || [], ctx).properties as Record<string, Schema>;
	schemas.meta = { ...(meta.meta || { type: 'object' }), description: 'Metadata included in every method result.' };
	schemas['error-response'] = { type: 'object', properties: { error: ref('error'), meta: ref('meta') }, required: ['error'] };
	return schemas;
}

function usualErrors (refData: ApiReference, ctx: Ctx): Schema {
	const usual = findSection(refData.sections, 'usual-errors');
	const props = usual?.properties || [];
	const lines = props.map(e => `- \`${keysOf(e).join('`, `')}\` (${typeof e.http === 'string' ? e.http : e.http?.code || ''}): ${(absolutize(e.description, ctx.pageUrl, ctx.siteUrl) || '').trim()}`);
	return {
		description: `Usual errors, possible on any call:\n\n${lines.join('\n')}`,
		'x-pryv-error-ids': props.flatMap(keysOf),
		content: { 'application/json': { schema: ref('error-response') } },
	};
}

const SOURCES: Record<OpenApiSource, { title: string; page: string; intro: string }> = {
	default: {
		title: 'Pryv.io API',
		page: 'reference',
		intro: 'The Pryv.io API: the methods an app calls on a user account.',
	},
	system: {
		title: 'Pryv.io system API',
		page: 'reference-system',
		intro: 'The Pryv.io system API: account creation, platform services and administration calls.',
	},
};

/** Build one OpenAPI document from the reference data. Pure and deterministic. */
export function buildOpenApi (source: OpenApiSource, refData: ApiReference, opts: OpenApiOptions = {}): Schema {
	const siteUrl = (opts.siteUrl || 'https://pryv.github.io').replace(/\/$/, '');
	const meta = SOURCES[source];
	const ctx: Ctx = { siteUrl, pageUrl: `${siteUrl}/${meta.page}/` };

	const entries: MethodEntry[] = [];
	if (source === 'default') {
		const basics = findSection(refData.sections, 'basics');
		const serviceInfo = findSection(basics?.sections, 'service-info');
		if (serviceInfo) entries.push({ section: { ...serviceInfo, type: 'method', id: 'service-info' }, parent: basics as Section, tag: basics?.title || 'Basics' });
		const methods = findSection(refData.sections, 'methods');
		collectMethods(methods?.sections, methods as Section, methods?.title || 'Methods', entries);
	} else {
		collectMethods(refData.system.sections, refData.system, refData.system.title || 'System', entries);
	}

	const byRoute = new Map<string, Operation[]>();
	const order: string[] = [];
	for (const entry of entries) {
		if (typeof entry.section.http !== 'string') continue; // text-only HTTP forms (app authorization flow)
		const route = parseRoute(entry.section.http);
		const key = `${route.path} ${route.verb}`;
		if (!byRoute.has(key)) { byRoute.set(key, []); order.push(key); }
		(byRoute.get(key) as Operation[]).push(buildOperation(entry, route, source, ctx));
	}

	const paths: Record<string, Record<string, Operation>> = {};
	for (const key of order) {
		const [path, verb] = key.split(' ');
		(paths[path] ??= {})[verb] = merge(byRoute.get(key) as Operation[]);
	}

	const tags = [...new Set(entries.map(e => e.tag))].map(name => ({ name }));
	const doc: Schema = {
		openapi: OPENAPI_VERSION,
		info: {
			title: meta.title,
			version: refData.version,
			description: [
				meta.intro,
				`Generated from the [API reference](${ctx.pageUrl}) at every documentation build: do not edit by hand. The reference is the authoritative description; report differences at ${ISSUES_URL}.`,
				source === 'default'
					? 'Authorization: send the access token in the `Authorization` header (preferred) or as the `auth` query parameter. A third form, the token as basic-auth user in the URL (`https://{token}@{username}.{domain}/`), cannot be expressed in OpenAPI.'
					: 'Methods flagged admin-only take the platform admin key in the `Authorization` header.',
			].join('\n\n'),
			contact: { url: ISSUES_URL },
			license: { name: 'MIT', url: 'https://opensource.org/licenses/MIT' },
		},
		'x-generated-from': { referenceVersion: refData.version, ...(opts.commit ? { commit: opts.commit } : {}) },
		servers: source === 'default'
			? [
				{ url: 'https://{username}.{domain}', description: 'Account endpoint, DNS form', variables: { username: { default: 'username' }, domain: { default: 'pryv.me' } } },
				{ url: 'https://{host}/{username}', description: 'Account endpoint, single-host (DNS-less) form', variables: { host: { default: 'host.your-domain.io' }, username: { default: 'username' } } },
			]
			: [
				{ url: 'https://reg.{domain}', description: 'Register service (methods marked x-pryv-server: register)', variables: { domain: { default: 'pryv.me' } } },
				{ url: 'https://{core}.{domain}', description: 'Core server (methods marked x-pryv-server: core)', variables: { core: { default: 'core' }, domain: { default: 'pryv.me' } } },
			],
		tags,
		paths,
		components: {
			schemas: dataStructureSchemas(refData, ctx),
			responses: { 'usual-errors': usualErrors(refData, ctx) },
			securitySchemes: source === 'default'
				? {
					tokenHeader: { type: 'apiKey', in: 'header', name: 'Authorization', description: 'Access token.' },
					tokenQuery: { type: 'apiKey', in: 'query', name: 'auth', description: 'Access token as a query parameter.' },
				}
				: { adminKey: { type: 'apiKey', in: 'header', name: 'Authorization', description: 'Platform admin key.' } },
		},
	};
	pruneUnusedSchemas(doc);
	return doc;
}

/** Drop component schemas no path reaches (the system API uses few data structures). */
function pruneUnusedSchemas (doc: Schema): void {
	const components = doc.components as { schemas: Record<string, Schema>; responses: Record<string, Schema> };
	const used = new Set<string>();
	const pending: unknown[] = [doc.paths, components.responses];
	while (pending.length) {
		const node = pending.pop();
		if (Array.isArray(node)) { pending.push(...node); continue; }
		if (!node || typeof node !== 'object') continue;
		const target = (node as Schema).$ref;
		if (typeof target === 'string' && target.startsWith('#/components/schemas/')) {
			const name = target.slice('#/components/schemas/'.length);
			if (!used.has(name)) { used.add(name); pending.push(components.schemas[name]); }
		}
		pending.push(...Object.values(node));
	}
	for (const name of Object.keys(components.schemas)) if (!used.has(name)) delete components.schemas[name];
}

/** Method ids an OpenAPI document covers (from `x-pryv-method-ids`). */
export function coveredMethodIds (doc: Schema): string[] {
	const ids: string[] = [];
	for (const item of Object.values(doc.paths as Record<string, Record<string, Operation>>)) {
		for (const op of Object.values(item)) ids.push(...(op['x-pryv-method-ids'] as string[]));
	}
	return ids;
}
