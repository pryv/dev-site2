// YAML rendering of the generated OpenAPI documents, shared by the build-time endpoints
// under src/pages/open-api/3.0/ and the gate (scripts/gate-openapi.mjs).
import { execFileSync } from 'node:child_process';
import { stringify } from 'yaml';
import { apiReference } from './index';
import { buildOpenApi, type OpenApiSource } from './openapi';

/** Short commit of the checkout being built, or undefined outside a git checkout. */
function currentCommit (): string | undefined {
	try {
		return execFileSync('git', ['rev-parse', '--short', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() || undefined;
	} catch {
		return undefined;
	}
}

export function renderOpenApiYaml (source: OpenApiSource, siteUrl?: string): string {
	const doc = buildOpenApi(source, apiReference, { siteUrl, commit: currentCommit() });
	// No anchors/aliases: some OpenAPI tools do not resolve them.
	return stringify(doc, { aliasDuplicateObjects: false, lineWidth: 0 });
}

export function yamlResponse (body: string): Response {
	return new Response(body, { headers: { 'Content-Type': 'text/yaml; charset=utf-8' } });
}
