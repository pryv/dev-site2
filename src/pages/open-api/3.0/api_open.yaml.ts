import type { APIRoute } from 'astro';
import { renderOpenApiYaml, yamlResponse } from '../../../reference-data/openapi-yaml';

// Legacy alias of api.yaml, kept so existing links and Postman imports keep working.
export const GET: APIRoute = ({ site }) => yamlResponse(renderOpenApiYaml('default', site?.toString()));
