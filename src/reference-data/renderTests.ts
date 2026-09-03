// Renders the test-results page, ported from tests.pug. Aggregated Mocha results per
// component, with per-suite [CODE] anchors and pass/pending/fail status icons.
import MarkdownIt from 'markdown-it';
import { getDocId, capitalize } from './helpers';
import { assignHeadingIds } from './render';

const md = new MarkdownIt({ typographer: true, html: true });
const renderMd = (s?: string): string => (s ? md.render(s) : '');
const stripParagraph = (h: string): string => (h.indexOf('<p>') === 0 ? h.substr(3, h.length - 8) : h);
const typeText = (s?: string): string => (s ? `<span class="type">${stripParagraph(md.render(s))}</span>` : '');

interface Stats { tests: number; passes: number; pending: number; failures: number; }
interface Test { id: string; title?: string; duration?: number; err?: Record<string, unknown>; }
interface TestSet { tests: Test[]; }
interface Component { componentName: string; stats: Stats; sets: Record<string, TestSet>; }
interface Version { version: string; date?: string; stats: Stats; components?: Component[]; }
interface TSection { id: string; title?: string; type?: string; description?: string; sections?: TSection[]; version?: Version; }

function statsTable (s: Stats, level: number): string {
	return `<h${level}>Summary</h${level}>` +
		'<table class="definitions">' +
		`<tr><th><strong>${s.tests}</strong></th><td><strong>tests total</strong></td></tr>` +
		`<tr><th>${s.passes}</th><td>✅ passing</td></tr>` +
		`<tr><th>${s.pending}</th><td>❓ pending</td></tr>` +
		`<tr><th>${s.failures}</th><td>❌ failing</td></tr>` +
		'</table>';
}

function statusIcon (t: Test): string {
	if (typeof t.duration === 'undefined') return '❓';
	if (t.err && Object.keys(t.err).length > 0) return '❌';
	return '✅';
}

function testRows (tests: Test[]): string {
	return tests.map((t) =>
		`<tr><td><span class="method-id"><span class="label">id</span><span class="label-value"><code>${t.id}</code></span></span></td>` +
		`<td style="text-align:center;">${statusIcon(t)}</td><td>${typeText(t.title)}</td></tr>`,
	).join('');
}

function testsets (sets: Record<string, TestSet>, level: number): string {
	let out = `<h${level}>Tests</h${level}><table><thead><tr><th>Id</th><th style="text-align:center;">Status</th><th>Test</th></tr></thead><tbody>`;
	for (const setTitle of Object.keys(sets)) {
		const codes = (setTitle.match(/\[([A-Z][A-Z0-9]+)\]/g) || []).map((s) => s.slice(1, -1));
		out += `<tr><td colspan="3">${codes.map((c) => `<span id="${c}"></span>`).join('')}<b>${capitalize(setTitle)}</b></td></tr>`;
		out += testRows(sets[setTitle].tests);
	}
	return out + '</tbody></table>';
}

function renderComponent (c: Component, parentDocId: string, level: number): string {
	const docId = getDocId(parentDocId, c.componentName);
	return `<section id="${docId}"><h${level}><code>${c.componentName}</code> component</h${level}>` +
		`<div class="content"><div class="meta"></div>${statsTable(c.stats, level + 1)}${testsets(c.sets, level + 1)}</div></section>`;
}

function renderVersion (v: Version, parentDocId: string, level: number): string {
	let out = statsTable(v.stats, level + 1);
	out += `<div class="intro">${renderMd('Date: ' + v.date)}</div>`;
	for (const c of v.components ?? []) out += renderComponent(c, parentDocId, level);
	return out;
}

function renderSection (section: TSection, parentDocId: string, level: number): string {
	const docId = getDocId(parentDocId, section.id);
	const cls = section.type || '';
	let html = `<section id="${docId}"${cls ? ` class="${cls}"` : ''}><h${level}>${section.title ?? ''}</h${level}>`;
	html += `<div class="content"><div class="meta"></div>${renderMd(section.description)}</div>`;
	for (const sub of section.sections ?? []) html += renderSection(sub, parentDocId, level + 1);
	if (section.version) html += renderVersion(section.version, parentDocId, level + 1);
	return html + '</section>';
}

export function renderTests (sections: TSection[]): string {
	let html = '';
	for (const s of sections) html += renderSection(s, s.id, 1);
	return assignHeadingIds(html);
}
