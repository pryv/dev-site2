import type { APIRoute } from 'astro';
import { userSections, systemSection, adminSection } from '../reference-data';
import type { Section, Property } from '../reference-data/types';

function firstLine (s?: string): string {
	if (!s) return '';
	return s.replace(/\s+/g, ' ').trim().slice(0, 240);
}
function keyList (props?: Property[]): string {
	if (!props || !props.length) return '';
	return props.map((p) => (Array.isArray(p.key) ? p.key.join('|') : p.key)).join(', ');
}

function walk (section: Section, out: string[], depth: number): void {
	const h = '#'.repeat(Math.min(depth, 6));
	out.push(`${h} ${section.title || section.id}`);
	if (section.type === 'method' && section.http) out.push('`' + section.http + '`');
	if (section.description) out.push(firstLine(section.description));
	const params = keyList(section.params?.properties);
	if (params) out.push(`Parameters: ${params}`);
	out.push('');
	for (const sub of section.sections ?? []) walk(sub, out, depth + 1);
}

// Dense single-file dump of the reference, generated at build from the reference data.
export const GET: APIRoute = async () => {
	const out: string[] = [];
	out.push('# Pryv.io API reference (full)');
	out.push('');
	out.push('> Dense machine-readable dump of the API reference. Full HTML version: https://pryv.github.io/reference/');
	out.push('');
	for (const s of userSections) walk(s, out, 1);
	out.push('# System API', '');
	for (const s of systemSection.sections ?? []) walk(s, out, 1);
	out.push('# Admin API', '');
	for (const s of adminSection.sections ?? []) walk(s, out, 1);
	return new Response(out.join('\n'), { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
};
