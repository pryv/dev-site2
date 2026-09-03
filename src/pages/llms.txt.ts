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
	lines.push(`- [OpenAPI 3.0](${base}/open-api/): api.yaml, api_open.yaml, api_system.yaml, api_admin.yaml`);
	lines.push(`- [Functional specifications](${base}/functional-specifications/)`);
	lines.push(`- [Full reference dump](${base}/llms-full.txt)`);
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
