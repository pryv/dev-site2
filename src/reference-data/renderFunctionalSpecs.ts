// Renders the functional specifications, ported from functional-specifications.pug.
// Sections are auto-numbered (1., 3.1., ...) and requirements carry stable REQ_ ids.
import MarkdownIt from 'markdown-it';
import { getDocId } from './helpers';
import { assignHeadingIds } from './render';

const md = new MarkdownIt({ typographer: true, html: true });
const renderMd = (s?: string): string => (s ? md.render(s) : '');
const stripParagraph = (h: string): string => (h.indexOf('<p>') === 0 ? h.substr(3, h.length - 8) : h);

interface Ref { url?: string; description?: string; }
interface Requirement { reqid: string; title?: string; description?: string; refs?: Ref[]; ignore?: boolean; }
interface FSection {
	id: string;
	reqid?: string;
	type?: string;
	title?: string;
	description?: string;
	sections?: FSection[];
	requirements?: Requirement[];
	ignore?: boolean;
}

function requirementId (id: string): string {
	return `<span class="method-id"><span class="label">id</span><span class="label-value"><code>${id}</code></span></span>`;
}
function typeText (s?: string): string {
	if (!s) return '';
	return `<span class="type">${stripParagraph(md.render(s))}</span>`;
}
function reference (ref: Ref): string {
	return ref.url ? `<a href="${ref.url}">${ref.description ?? ''}</a>` : '';
}

function renderRequirements (requirements: Requirement[] | undefined, reqid: string): string {
	if (!requirements) return '';
	let out = '';
	for (const r of requirements) {
		if (r.ignore) continue;
		const myId = reqid + r.reqid;
		const docId = getDocId(myId);
		let table = `<table class="definitions"><tr><th><code>Title</code></th><td><div class="header">${typeText(r.title)}</div></td></tr>`;
		table += `<tr><th><code>Desc</code></th><td><div class="description">${renderMd(r.description || '')}</div></td></tr>`;
		if (r.refs) table += `<tr><th><code>Refs</code></th><td><ol>${r.refs.map((ref) => `<li>${reference(ref)}</li>`).join('')}</ol></td></tr>`;
		table += '</table>';
		out += `<div class="requirement" id="${docId}">${requirementId(myId)}${table}</div>`;
	}
	return out;
}

function renderSection (section: FSection, parentDocId: string, level: number, nreqid: string, nsectionHeader: string): string {
	if (section.ignore) return '';
	let reqid = 'REQ_';
	if (nreqid) reqid = '' + nreqid;
	if (section.reqid) reqid = reqid + section.reqid + '_';
	const sectionHeader = nsectionHeader || '';
	const sectionTitle = sectionHeader + ' ' + (section.title ?? '');
	const docId = getDocId(parentDocId, section.id);
	const cls = section.type || '';

	let html = `<section id="${docId}"${cls ? ` class="${cls}"` : ''}>`;
	html += `<h${level}>${sectionTitle}</h${level}>`;
	html += `<div class="content"><div class="meta"></div>${renderMd(section.description)}${renderRequirements(section.requirements, reqid)}</div>`;
	if (section.sections) {
		let n = 0;
		for (const sub of section.sections) {
			n++;
			html += renderSection(sub, parentDocId, level + 1, reqid, sectionHeader + n + '.');
		}
	}
	return html + '</section>';
}

export function renderFunctionalSpecs (sections: FSection[]): string {
	let html = '';
	let n = 0;
	for (const s of sections) {
		n++;
		html += renderSection(s, s.id, 1, '', n + '.');
	}
	return assignHeadingIds(html);
}
