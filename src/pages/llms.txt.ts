import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';

// Generated at build from the content collection + the generated reference pages.
export const GET: APIRoute = async ({ site }) => {
	const base = (site?.toString() ?? 'https://pryv.github.io/').replace(/\/$/, '');
	const docs = (await getCollection('docs')).sort((a, b) => a.id.localeCompare(b.id));

	const lines: string[] = [];
	lines.push('# Pryv.io developer documentation');
	lines.push('');
	lines.push('> API reference, guides and setup documentation for Pryv.io, the middleware for privacy-compliant personal and health data.');
	lines.push('');
	lines.push('## Reference');
	lines.push(`- [API reference](${base}/reference/): all API methods with request and response examples`);
	lines.push(`- [System API](${base}/reference-system/)`);
	lines.push(`- [Admin API](${base}/reference-admin/)`);
	lines.push(`- [Event types](${base}/event-types/): flat.json at ${base}/event-types/flat.json`);
	lines.push(`- [OpenAPI 3.0.3](${base}/open-api/): ${base}/open-api/3.0/api.yaml and ${base}/open-api/3.0/api_system.yaml, generated from the reference (api_open.yaml is a legacy alias of api.yaml)`);
	lines.push(`- [Functional specifications](${base}/functional-specifications/)`);
	lines.push(`- [Full reference dump](${base}/llms-full.txt)`);
	lines.push('');
	// The compliance matrix is a separate site under the same origin (pryv/compliance-matrix).
	const cm = 'https://pryv.github.io/compliance-matrix';
	const regulationIds = ['gdpr', 'hipaa-privacy', 'hipaa-security', 'hipaa-breach', 'swiss-nlpd', 'ccpa', 'pipeda', 'diga', 'mdr', 'hds', 'iso-27001', 'iso-27701', 'iso-13485', 'soc2', 'data-governance'];
	lines.push('## Compliance');
	lines.push(`- [Compliance matrix](${cm}/): how 15 regulations and standards map onto Pryv.io (what it handles, what is configurable, what it facilitates, what stays with the implementer); one regulation at ${cm}/#/scope/<id>`);
	lines.push(`- [Compliance matrix llms.txt](${cm}/llms.txt): agent index of the matrix`);
	lines.push(`- [Compliance matrix llms-full.txt](${cm}/llms-full.txt): the whole matrix in one text file`);
	lines.push(`- Per-regulation Markdown: ${cm}/regulations/<id>.md, one file per regulation, with <id> one of ${regulationIds.join(', ')}`);
	lines.push(`- [compliance.json](${cm}/compliance.json): the matrix as machine-readable JSON`);
	lines.push('');
	lines.push('## Docs');
	for (const d of docs) {
		if (d.id === 'index') continue;
		const url = `${base}/${d.id}/`;
		const desc = d.data.description ? `: ${d.data.description}` : '';
		lines.push(`- [${d.data.title}](${url})${desc}`);
	}
	lines.push('');

	return new Response(lines.join('\n'), { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
};
