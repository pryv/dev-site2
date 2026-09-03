// Faithful HTML renderer for the API reference, ported from the legacy Pug mixins
// (reference.pug + includes/mixins.pug). Produces the same structure: <section id={docId}>
// wrappers, heading ids via the shared per-page slugger, recursive property tables, and
// the five example panes with the api-* marker spans the environment switcher toggles.
import MarkdownIt from 'markdown-it';
import {
	getDocId, getRestCall, getCurlCall, getWebsocketCall, getBatchBlock, printJSON, httpOnly as httpOnlyMsg,
} from './helpers';
import { createSlugger } from './slug';
import { version } from './index';
import type { Section, Property, ResultObject, ReferenceFlavor } from './types';

const md = new MarkdownIt({ typographer: true, html: true });
const renderMd = (s?: string): string => (s ? md.render(s) : '');
const stripTags = (h: string): string => h.replace(/<[^>]*>/g, '');
// Emit an example code block tagged with its language and carrying the raw source as
// base64 in a data attribute. A build-time pass (highlight.ts) replaces these with
// syntax-highlighted markup. Base64 keeps the raw source intact even when it contains
// the `api-*` environment-marker <span>s (the cURL panes), which the highlighter
// restores after tokenizing so the runtime environment switcher keeps working.
function codeBlock (raw: string, lang: string): string {
	const b64 = Buffer.from(raw, 'utf8').toString('base64');
	return `<pre><code data-lang="${lang}" data-raw="${b64}"></code></pre>`;
}

// Wrap the endpoint-host PLACEHOLDERS in sample responses with the same `api-*` marker
// spans the environment switcher rewrites, so responses follow the selected API pattern
// (Pryv Lab / DNS-less / Own) like the requests do. Only the `{username}.pryv.me` and
// `reg.pryv.me` placeholders are templated; concrete example hosts (e.g. chuangzi.pryv.me)
// are literal sample data and left untouched. Must NOT run on the cURL blocks (already
// carry their own spans) — apply only to JSON/response bodies.
function templateEndpoints (json: string): string {
	return json
		.replace(/\{username\}\.pryv\.me/g, '<span class="api">{username}.pryv.me</span>')
		.replace(/reg\.pryv\.me/g, '<span class="api-reg">reg.pryv.me</span>');
}

// The "strip the wrapping <p>...</p>\n" hack the legacy mixins use for inline fragments.
function stripParagraph (html: string): string {
	return html.indexOf('<p>') === 0 ? html.substr(3, html.length - 8) : html;
}

function heading (level: number, title: string, raw = false): string {
	if (!title) return '';
	const display = raw ? title : md.renderInline(title);
	return `<h${level}>${display}</h${level}>`;
}

// Post-pass reproducing metalsmith-headings-identifier: assign an id to EVERY heading in
// document order (structural headings and headings embedded in description markdown alike),
// with per-page dedup, so in-page anchors match the previous site.
function decodeEntities (s: string): string {
	return s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
		.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&nbsp;/g, ' ');
}

export function assignHeadingIds (html: string): string {
	const slug = createSlugger();
	return html.replace(/<(h[1-6])([^>]*)>([\s\S]*?)<\/\1>/g, (_m, tag, attrs, inner) => {
		// Match the legacy cheerio .text() (which decodes entities) before slugging.
		const id = slug(decodeEntities(stripTags(inner)));
		const cleaned = String(attrs).replace(/\s+id="[^"]*"/, '');
		return `<${tag}${cleaned} id="${id}">${inner}</${tag}>`;
	});
}

function renderHttp (http?: Section['http'] | Property['http'], httpOnlyFlag?: boolean, server?: string): string {
	if (!http) return '';
	let inner: string;
	if (typeof http === 'object') {
		if (http.code) inner = `<code>${http.code}</code>`;
		else if (http.text) inner = `<span>${stripParagraph(md.render(http.text))}</span>`;
		else inner = '';
	} else if (server) {
		inner = `<code>${http.replace(' ', ` <a href="/reference-system/#api-endpoint">{${server}}</a>`)}</code>`;
	} else {
		inner = `<code>${http}</code>`;
	}
	const label = httpOnlyFlag ? 'HTTP-only' : 'HTTP';
	return `<span class="http"><span class="label">${label}</span><span class="label-value">${inner}</span></span>`;
}

function renderTypeText (type?: string): string {
	if (!type) return '';
	return `<span class="type">${stripParagraph(md.render(type))}</span>`;
}

function labelValue (label: string, cssClass: string, value?: boolean | string): string {
	if (!value) return '';
	return `<span class="label label-default ${cssClass}">${label + (typeof value === 'string' ? ' ' + value : '')}</span>`;
}

function renderProperties (properties?: Property[]): string {
	if (!properties) return '';
	let rows = '';
	for (const prop of properties) {
		let th: string;
		if (Array.isArray(prop.key)) {
			th = prop.key.map((k, i) => `<code>${k}</code>${i < (prop.key as string[]).length - 1 ? ' | ' : ''}`).join('');
		} else {
			th = `<code>${prop.key}</code>`;
		}
		const header = renderTypeText(prop.type) +
			labelValue('unique', 'unique', prop.unique) +
			labelValue('optional', 'optional', prop.optional) +
			labelValue('read-only', 'read-only', prop.readOnly) +
			renderHttp(prop.http);
		rows += `<tr><th>${th}</th><td><div class="header">${header}</div>` +
			`<div class="description">${renderMd(prop.description)}</div>` +
			renderProperties(prop.properties) + '</td></tr>';
	}
	return `<table class="definitions">${rows}</table>`;
}

function renderResult (result: ResultObject): string {
	if (!result) return '';
	return heading(4, result.title || 'Result') +
		renderHttp(result.http) +
		renderMd(result.description) +
		renderProperties(result.properties);
}

function tag (cls: string, onclick: string, labelTitle: string, labelText: string, flag?: boolean, valueCode?: string): string {
	if (!flag) return '';
	const value = valueCode ? `<span class="label-value"><code>${valueCode}</code></span>` : '';
	return `<span onclick="location='${onclick}'" class="${cls}"><span class="label" title="${labelTitle}">${labelText}</span>${value}</span>`;
}

function exampleContent (content: unknown): string {
	if (!content) return '';
	if (typeof content === 'string') return renderMd(content);
	return codeBlock(templateEndpoints(printJSON(content)), 'json');
}

function resultHttpStatus (ex: { resultHTTP?: string }, settings: Section): string {
	if (ex.resultHTTP) return ex.resultHTTP;
	const r = settings.result;
	if (Array.isArray(r)) return r[0]?.http || '';
	return r?.http || '';
}

function responseBlock (ex: { result?: unknown; resultHTTP?: string }, settings: Section): string {
	const body = `HTTP/1.1 ${resultHttpStatus(ex, settings)}\n` +
		`Content-Type: application/json; charset=utf-8\nAPI-Version: ${version}\n\n` +
		printJSON(ex.result);
	return '<div class="step-marker">⬇︎</div>' + codeBlock(templateEndpoints(body), 'http');
}

function renderExamples (examples: Section['examples'], settings: Section): string {
	if (!examples) return '';
	let out = '';
	for (const ex of examples) {
		let block = ex.title ? renderMd(ex.title) : '';
		if (ex.content || typeof ex.params === 'string') {
			block += exampleContent(ex.content) + exampleContent(ex.params);
			if (ex.result) block += '<div class="step-marker">⬇︎</div>' + exampleContent(ex.result);
		} else if (ex.params) {
			const p = ex.params as Record<string, unknown>;
			let panes = `<div class="tab-pane json active">${codeBlock(getRestCall(p, settings.http as string), 'json')}`;
			if (ex.result) panes += '<div class="step-marker">⬇︎</div>' + codeBlock(templateEndpoints(printJSON(ex.result)), 'json');
			panes += '</div>';
			if (settings.http) {
				panes += `<div class="tab-pane http">${codeBlock(getCurlCall(p, settings.http, settings.server, false), 'bash')}`;
				if (ex.result) panes += responseBlock(ex, settings);
				panes += '</div>';
			}
			if (settings.id) {
				panes += '<div class="tab-pane sockets">';
				if (settings.httpOnly) panes += `<pre>${httpOnlyMsg()}</pre>`;
				else {
					panes += codeBlock(`socket.emit('${settings.id}', ${getWebsocketCall(p)}, callback);`, 'javascript');
					if (ex.result) panes += '<div class="step-marker">⬇︎</div>' + codeBlock(templateEndpoints(printJSON(ex.result)), 'json');
				}
				panes += '</div>';
			}
			if (settings.id) {
				panes += '<div class="tab-pane batch">';
				if (settings.httpOnly) panes += `<pre>${httpOnlyMsg()}</pre>`;
				else {
					if (settings.id === 'callBatch') panes += renderMd('Yes it works! Calling a method `callBatch` within a **call batch** would make no sense. Look at Rest or Socket.io calls.');
					panes += codeBlock(getBatchBlock(settings.id as string, p), 'json');
					if (ex.result) panes += '<div class="step-marker">⬇︎</div>' + codeBlock(templateEndpoints(printJSON(ex.result)), 'json');
				}
				panes += '</div>';
			}
			if (settings.http) {
				panes += `<div class="tab-pane httpAuth">${codeBlock(getCurlCall(p, settings.http, settings.server, true), 'bash')}`;
				if (ex.result) panes += responseBlock(ex, settings);
				panes += '</div>';
			}
			block += `<div class="tab-content">${panes}</div>`;
		}
		out += `<div class="example">${block}</div>`;
	}
	return `<aside>${out}</aside>`;
}

function isVisible (section: Section, flavor: ReferenceFlavor): boolean {
	return (!section.trustedOnly && !section.previewOnly) ||
		(!section.previewOnly && !!flavor.showTrustedOnlyContent) ||
		!!flavor.showPreviewOnlyContent;
}

function renderSection (section: Section, parentDocId: string, level: number, parent: Section | undefined, flavor: ReferenceFlavor): string {
	if (!isVisible(section, flavor)) return '';
	const isMethod = section.type === 'method';
	const docId = getDocId(parentDocId, section.id);
	const cls = section.type || '';

	const titleHeading = heading(level, section.title || '', true);

	let meta = '';
	if (isMethod) {
		meta += tag('trusted-tag', '/reference/#trusted-apps-verification', 'Trusted Apps Only', 'T', section.adminOnly ? undefined : (parent?.trustedOnly));
		meta += tag('admin-tag', '/reference-system/#admin', 'Admin Only', 'A', parent?.adminOnly);
		meta += tag('v2-tag', '/change-log/', 'Added or changed in v2', 'v2', section.v2Tag || (parent as { v2Only?: boolean } | undefined)?.v2Only);
		meta += tag('method-id', '/reference/#method-ids', 'Method Id', 'id', true, section.id);
		meta += renderHttp(section.http, section.httpOnly, section.server);
	}
	if (section.trustedOnly) meta += `<span onclick="location='/reference/#trusted-apps-verification'" class="label trusted-only">Trusted apps only</span>&nbsp;`;
	if (section.adminOnly) meta += `<span onclick="location='/reference-system/#admin'" class="label admin-only">Admin only</span>&nbsp;`;
	if (section.previewOnly) meta += '<span class="label trusted-only">Preview</span>&nbsp;';

	let content = `<div class="meta">${meta}</div>`;
	content += section.description ? `<div class="intro">${renderMd(section.description)}</div>` : '';
	content += renderProperties(section.properties);
	if (section.params) {
		content += heading(4, section.params.title || 'Parameters');
		content += renderMd(section.params.description);
		content += renderProperties(section.params.properties);
	}
	if (section.result) {
		const results = Array.isArray(section.result) ? section.result : [section.result];
		for (const r of results) content += renderResult(r);
	}
	if (section.errors && section.errors.length) {
		content += heading(4, 'Specific errors');
		content += renderProperties(section.errors);
	}

	let html = `<section id="${docId}"${cls ? ` class="${cls}"` : ''}>`;
	html += titleHeading;
	html += `<div class="content">${content}</div>`;
	html += renderExamples(section.examples, section);
	if (section.sections) {
		for (const sub of section.sections) html += renderSection(sub, docId, level + 1, section, flavor);
	}
	return html + '</section>';
}

/** Render one reference page from a top-level sections array. */
export function renderReference (rootSections: Section[], flavor: ReferenceFlavor): string {
	let html = '';
	for (const level1 of rootSections) {
		html += `<section id="${getDocId(level1.id)}">`;
		html += heading(1, level1.title || '');
		html += level1.description ? `<div class="intro">${renderMd(level1.description)}</div>` : '';
		if (level1.sections) {
			for (const l2 of level1.sections) html += renderSection(l2, level1.id, 2, level1, flavor);
		}
		html += '</section>';
	}
	// Assign heading ids over the whole page (structural + description headings), matching
	// the legacy post-render pass.
	return assignHeadingIds(html);
}
