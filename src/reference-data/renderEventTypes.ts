// Renders the event-types reference from the data-types `event-types.json` snapshot,
// ported from the legacy event-types.pug. Emits the same About + Directory structure with
// recursive JSON-schema definition tables.
import MarkdownIt from 'markdown-it';
import { assignHeadingIds } from './render';

const md = new MarkdownIt({ typographer: true, html: true });
const escapeHtml = (s: string): string => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

interface Schema {
	type?: string;
	description?: string;
	properties?: Record<string, Schema>;
	patternProperties?: Record<string, Schema>;
	example?: unknown;
	required?: string[];
	[key: string]: unknown;
}
interface ClassDef { description?: string; formats: Record<string, Schema>; }
interface EventTypes { version: string; classes: Record<string, ClassDef>; }

const ABOUT = `You are free to use any type in your app, but for the sake of interoperability we heavily recommend that you extend the standard types listed here.

To customize your own Pryv.io setup, clone the [Data Types repository](https://github.com/pryv/data-types) and follow the guide there.

## Basics

An event's type is defined by its \`type\` property that indicates how to handle its \`content\` (if any).
The type itself is specified as \`{class}/{format}\`, lowercase (e.g. \`note/html\`). Rationale:

- The class usually specifies the "nature" or "kind" of data represented by the event.
  Events of the same class are assumed to be comparable and convertible, and will likely be displayed similarly.
- The format usually specifies how the data is structured. For example, a basic note may just be a single string value, while a rich-text note could be a more complex object structure.

## Format specification

For each of the types described below, the event content's structure is specified with [JSON-schema](http://json-schema.org/specification.html). Notes:

- A "null" content type means that the event has no \`content\` property (because the core event structure is sufficient).
- Any content type other than "null" implies that the event must have a \`content\` property of the specified JSON-schema type.
- If the content is an object, its (sub-)properties are assumed to be optional unless otherwise specified by JSON-schema's "required" field.

## JSON file

This directory is available as a JSON file for automated processing:

- [Hierarchical structure](hierarchical.json): \`classes['{class}'].formats['{format}']\`
- [Flat structure](flat.json): \`types['{class}/{format}']\`

## Submitting types & issues

This directory will keep evolving to match the needs of Pryv apps: [issues and pull requests are welcome](https://github.com/pryv/data-types).`;

function attribute (header: string, value: unknown): string {
	if (!value) return '';
	const v = header === 'enum' && Array.isArray(value) ? value.join(', ') : String(value);
	return `, <span class="attribute"><strong>${header}:&nbsp;</strong>${v}</span>`;
}

function definition (name: string, schema: Schema): string {
	let td = '';
	if (schema.type && schema.type !== 'null') td += schema.type;
	else td += '<span class="label label-default">no content</span>&nbsp;';

	for (const key of Object.keys(schema)) {
		if (['type', 'description', 'properties', 'patternProperties', 'example'].includes(key)) continue;
		const value = schema[key];
		if (key === 'pattern') td += attribute(key, '<code>' + value + '</code>');
		else if (key === 'required' && Array.isArray(value)) td += attribute(key, value.map((k) => '<code>' + k + '</code>').join(', '));
		else if (key === 'attachmentRequired' && value) td += '<span class="label label-default">attachment required</span>';
		else if (key === 'additionalProperties') td += attribute('additional properties', value ? 'allowed' : 'forbidden');
		else td += attribute(key, value);
	}
	if (schema.description) td += `<div class="description">${md.render(schema.description)}</div>`;
	if (schema.properties) {
		td += `<table class="definitions"><tbody>${Object.keys(schema.properties).map((k) => definition(k, schema.properties![k])).join('')}</tbody></table>`;
	}
	if (schema.patternProperties) {
		td += '<p>Properties unspecified above must match the following pattern:</p>';
		td += `<table class="definitions"><tbody>${Object.keys(schema.patternProperties).map((k) => definition(k, schema.patternProperties![k])).join('')}</tbody></table>`;
	}
	if (schema.example !== undefined) {
		td += `<div class="example"><strong>Example:</strong><pre><code>${escapeHtml(JSON.stringify(schema.example, null, 2))}</code></pre></div>`;
	}
	return `<tr><th><code>${name}</code></th><td>${td}</td></tr>`;
}

const cap = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1);

export function renderEventTypes (data: EventTypes): string {
	const classes = data.classes;
	const complex: Record<string, ClassDef> = {};
	const numerical: Record<string, ClassDef> = {};
	for (const className of Object.keys(classes)) {
		const classDef = classes[className];
		const numberOnly = Object.keys(classDef.formats).every((f) => classDef.formats[f].type === 'number');
		(numberOnly ? numerical : complex)[className] = classDef;
	}

	let html = `<section id="about"><h1>About types</h1>${md.render(ABOUT)}</section>`;
	html += '<section id="directory"><h1>Directory</h1>';
	html += `<p class="version">Version: <strong>${data.version}</strong></p>`;

	html += '<h2>Complex types</h2>';
	for (const className of Object.keys(complex)) {
		const classDef = classes[className];
		html += `<h3>${cap(className)}</h3>`;
		html += `<div class="description">${classDef.description ?? ''}</div>`;
		html += '<table class="definitions"><tbody>';
		for (const formatName of Object.keys(classDef.formats)) {
			html += definition(`${className}/${formatName}`, classDef.formats[formatName]);
		}
		html += '</tbody></table>';
	}

	html += '<h2>Numerical types</h2>';
	for (const className of Object.keys(numerical)) {
		const classDef = numerical[className];
		html += `<h3>${cap(className)}</h3>`;
		html += `<div class="description">${classDef.description ?? ''}</div>`;
		html += '<table class="definitions"><tbody>';
		for (const formatName of Object.keys(classDef.formats)) {
			html += `<tr><th><code>${className}/${formatName}</code></th><td>${classDef.formats[formatName].description ?? ''}</td></tr>`;
		}
		html += '</tbody></table>';
	}
	html += '</section>';

	return assignHeadingIds(html);
}
