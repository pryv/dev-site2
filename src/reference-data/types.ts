// Types for the API reference data (single source, also consumed by the OpenAPI
// generator). Shapes mirror the legacy reference objects exactly; unused-but-supported
// flags are kept optional.

export interface Property {
	key: string | string[];
	type?: string;
	optional?: boolean | string;
	unique?: boolean | string;
	readOnly?: boolean | string;
	http?: string | { code?: string; text?: string };
	description?: string;
	properties?: Property[];
}

export interface ResultObject {
	title?: string;
	http?: string;
	description?: string;
	properties?: Property[];
}

export interface Example {
	title?: string;
	content?: unknown;
	// `params` is usually an object (call form) but may be a string (prose form).
	params?: Record<string, unknown> | string;
	result?: unknown;
	resultHTTP?: string;
}

export interface Section {
	id: string;
	title?: string;
	type?: 'method' | string;
	description?: string;
	sections?: Section[];
	// visibility gates / badges
	trustedOnly?: boolean;
	previewOnly?: boolean;
	adminOnly?: boolean;
	v2Tag?: boolean;
	entrepriseOnly?: boolean;
	// method-only fields (type === 'method')
	http?: string;
	httpOnly?: boolean;
	server?: string;
	params?: { title?: string; description?: string; properties?: Property[] };
	result?: ResultObject | ResultObject[];
	errors?: Property[];
	examples?: Example[];
}

export interface ApiReference {
	sections: Section[];
	version: string;
	system: Section;
	admin: Section;
}

/** Which API surface a reference page renders. */
export type ReferenceSource = 'default' | 'system' | 'admin';

export interface ReferenceFlavor {
	source: ReferenceSource;
	showTrustedOnlyContent?: boolean;
	showPreviewOnlyContent?: boolean;
}
