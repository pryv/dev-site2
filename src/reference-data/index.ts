// Typed surface over the API reference data. The JSON is generated deterministically
// from the canonical reference source by scripts/build-reference-data (see the repo
// README), never hand-edited. This module is the single source consumed by both the
// reference pages and the OpenAPI generator.
import data from './reference.json';
import type { ApiReference, Section } from './types';

export const apiReference = data as unknown as ApiReference;
export const version: string = apiReference.version;

/** The three user-API root sections (basics, methods, data-structure). */
export const userSections: Section[] = apiReference.sections;
export const systemSection: Section = apiReference.system;
export const adminSection: Section = apiReference.admin;

export type { ApiReference, Section } from './types';
