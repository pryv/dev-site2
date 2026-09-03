// Heading id slugs, reproducing the legacy metalsmith-headings-identifier algorithm and
// its per-page dedup, so in-page anchors match the previous site exactly.

/** Slugify one heading's (already plain-text) content. Order of operations matters. */
export function headingSlug (text: string): string {
	return text
		.replace(/&.*?;/g, '') // strip HTML entities
		.replace(/\s+/g, '-') // whitespace runs -> single dash
		.replace(/[^\w\-]/g, '') // drop everything except [A-Za-z0-9_] and dash
		.toLowerCase();
}

/**
 * A per-page slugger with the legacy dedup: first occurrence keeps the bare slug, later
 * ones get `-1`, `-2`, ... A fresh slugger MUST be created per rendered page (counters
 * reset per page, as in the legacy build).
 */
export function createSlugger (): (text: string) => string {
	const seen = new Map<string, number>();
	return (text: string): string => {
		const base = headingSlug(text);
		const count = seen.get(base);
		if (count === undefined) {
			seen.set(base, 0);
			return base;
		}
		const next = count + 1;
		seen.set(base, next);
		return `${base}-${next}`;
	};
}
