// Build-time syntax highlighting for the reference example code blocks. render.ts emits
// each block as `<pre><code data-lang data-raw(base64)></code></pre>`; this pass decodes
// the raw source, highlights it with Shiki (dual light/dark theme), and swaps the block in.
//
// The cURL panes embed `api-*` environment-marker <span>s that the client-side environment
// switcher rewrites at runtime. Shiki works on plain text, so before tokenizing we replace
// each marker span with a plain-word placeholder, then restore the original span markup in
// the highlighted output, keeping the switcher's targets intact.
import { createHighlighter, type Highlighter } from 'shiki';

const THEMES = { light: 'github-light', dark: 'github-dark' } as const;

let highlighterPromise: Promise<Highlighter> | undefined;
function getHighlighter (): Promise<Highlighter> {
	if (!highlighterPromise) {
		highlighterPromise = createHighlighter({
			themes: [THEMES.light, THEMES.dark],
			langs: ['json', 'bash', 'javascript', 'http'],
		});
	}
	return highlighterPromise;
}

// Only the environment-marker spans (api-* / core-*) are preserved across highlighting;
// anchoring the class prevents an incidental `<span class="x">` in a future code sample
// from being re-injected as live HTML.
const MARKER_RE = /<span class="((?:api|core)[\w-]*)">([^<]*)<\/span>/g;
const BLOCK_RE = /<pre><code data-lang="([^"]+)" data-raw="([^"]*)"><\/code><\/pre>/g;

function highlightOne (hl: Highlighter, raw: string, lang: string): string {
	const markers: Array<{ token: string; html: string }> = [];
	const prepared = raw.replace(MARKER_RE, (html) => {
		const token = `PRYVMARKER${markers.length}END`;
		markers.push({ token, html });
		return token;
	});
	let out = hl.codeToHtml(prepared, { lang, themes: THEMES, defaultColor: false });
	for (const { token, html } of markers) out = out.split(token).join(html);
	// Fail the build loudly if a placeholder ever survived (e.g. Shiki split it across
	// tokens) rather than shipping a literal PRYVMARKER token silently.
	if (markers.length && out.includes('PRYVMARKER')) {
		throw new Error('highlight.ts: an environment-marker placeholder was not restored after highlighting');
	}
	return out;
}

/** Replace every tagged example code block in `html` with highlighted markup. */
export async function highlightExamples (html: string): Promise<string> {
	if (!html.includes('data-raw=')) return html;
	const hl = await getHighlighter();
	const outs: string[] = [];
	html.replace(BLOCK_RE, (_m, lang: string, b64: string) => {
		outs.push(highlightOne(hl, Buffer.from(b64, 'base64').toString('utf8'), lang));
		return _m;
	});
	let i = 0;
	return html.replace(BLOCK_RE, () => outs[i++]);
}
