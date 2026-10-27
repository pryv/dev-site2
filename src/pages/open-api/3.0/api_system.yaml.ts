import type { APIRoute } from 'astro';
import { renderOpenApiYaml, yamlResponse } from '../../../reference-data/openapi-yaml';

// Generated at build from the system API reference (see src/reference-data/openapi.ts).
export const GET: APIRoute = ({ site }) => yamlResponse(renderOpenApiYaml('system', site?.toString()));
