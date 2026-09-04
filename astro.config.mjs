// @ts-check
import { readFile, writeFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLinksValidator from 'starlight-links-validator';

// Staging/preview builds (project-pages subpath, e.g. pryv.github.io/dev-site2) set
// SITE_BASE=/dev-site2. Astro's `base` prefixes assets and Starlight-managed links, but
// NOT absolute links authored in content markdown or in the custom components. This
// integration prefixes those remaining root-absolute links post-build, and makes the
// preview noindex (own robots.txt) so it never competes with the live site's SEO.
const SITE_BASE = process.env.SITE_BASE ? process.env.SITE_BASE.replace(/\/$/, '') : '';

// Site-wide structured data (schema.org) for rich results + AI-search grounding. URLs
// point at the canonical root deploy (the preview is noindex, so its URLs are moot).
const STRUCTURED_DATA = JSON.stringify({
	'@context': 'https://schema.org',
	'@graph': [
		{
			'@type': 'WebSite',
			'@id': 'https://pryv.github.io/#website',
			name: 'Pryv developer documentation',
			description: 'API reference, guides and setup documentation for Pryv.io, the middleware for personal and health data.',
			url: 'https://pryv.github.io/',
			publisher: { '@id': 'https://www.pryv.com/#organization' },
		},
		{
			'@type': 'Organization',
			'@id': 'https://www.pryv.com/#organization',
			name: 'Pryv',
			url: 'https://www.pryv.com/',
			logo: 'https://pryv.github.io/assets/images/logo-256.png',
			sameAs: ['https://github.com/pryv'],
		},
	],
});

function stagingSubpath () {
	const baseName = SITE_BASE.replace(/^\//, '');
	return {
		name: 'staging-subpath-rewrite',
		hooks: {
			'astro:build:done': async ({ dir }) => {
				if (!SITE_BASE) return;
				const root = fileURLToPath(dir);
				// Prefix root-absolute urls that Astro/Starlight did not already base:
				// skip protocol-relative (//) and anything already under the base.
				const skip = new RegExp('^/' + baseName + '(/|$)');
				const rewrite = (s) => s
					.replace(/(href|src|action|poster|content)="(\/[^"/][^"]*|\/)"/g, (m, attr, url) =>
						skip.test(url) ? m : `${attr}="${SITE_BASE}${url}"`)
					// meta-refresh redirect targets, e.g. content="0;url=/reference"
					.replace(/content="(\d+;\s*url=)(\/[^"]*)"/g, (m, prefix, url) =>
						skip.test(url) ? m : `content="${prefix}${SITE_BASE}${url}"`)
					.replace(/location(\.href)?\s*=\s*'(\/[^'/][^']*)'/g, (m, p1, url) =>
						skip.test(url) ? m : `location${p1 || ''}='${SITE_BASE}${url}'`);
				const walk = async (d) => {
					for (const e of await readdir(d, { withFileTypes: true })) {
						const p = path.join(d, e.name);
						if (e.isDirectory()) await walk(p);
						else if (e.name.endsWith('.html')) await writeFile(p, rewrite(await readFile(p, 'utf8')));
					}
				};
				await walk(root);
				await writeFile(path.join(root, 'robots.txt'), 'User-agent: *\nDisallow: /\n');
			},
		},
	};
}

// Canonical publish target is the org page (served at the domain root, no base path).
// `build.format: 'directory'` reproduces the legacy trailing-slash directory URLs so
// existing links (e.g. /guides/webhooks/) keep resolving after the cutover.
// https://astro.build/config
export default defineConfig({
	site: 'https://pryv.github.io',
	// Root cutover serves at '/'. A staging/preview deploy under a subpath (project pages,
	// e.g. pryv.github.io/dev-site2) sets SITE_BASE=/dev-site2 so links resolve there.
	base: process.env.SITE_BASE || undefined,
	build: { format: 'directory' },
	// Legacy /reference-full/ was itself a redirect to the reference; preserve it.
	redirects: { '/reference-full': '/reference' },
	integrations: [
		starlight({
			// The reference / event-types / functional-specs pages are custom (non-collection)
			// routes, so their in-page anchors cannot be introspected here; they are covered
			// by a dedicated anchor-parity check instead. Exclude them from link validation.
			// Skipped on staging builds: absolute links are base-prefixed post-build, which
			// the in-build validator cannot see (root builds keep full validation).
			plugins: SITE_BASE ? [] : [starlightLinksValidator({
				errorOnRelativeLinks: false,
				exclude: [
					// Custom (non-collection) routes: anchors validated by the anchor-parity check.
					'/tests/**', '/tests/',
					'/reference/**', '/reference/',
					'/reference-light/**', '/reference-light/',
					'/reference-preview/**', '/reference-preview/',
					'/reference-system/**', '/reference-system/',
					'/reference-admin/**', '/reference-admin/',
					'/event-types/**', '/event-types/',
					'/functional-specifications/**', '/functional-specifications/',
				],
			})],
			title: 'Pryv API',
			components: {
				// Adds a primary "API" entry point in the top bar (see the component).
				SiteTitle: './src/components/SiteTitle.astro',
				// The reference pages get their own left-hand navigation (the API outline);
				// the rest of the site keeps the default sidebar.
				Sidebar: './src/components/Sidebar.astro',
			},
			logo: {
				light: './src/assets/logo-256-black.png',
				dark: './src/assets/logo-256-white.png',
				replacesTitle: true,
			},
			favicon: '/assets/images/favicon-black.ico',
			head: [
				{ tag: 'link', attrs: { rel: 'apple-touch-icon', sizes: '180x180', href: '/assets/images/apple-touch-icon-180x180-black.png' } },
				{ tag: 'link', attrs: { rel: 'apple-touch-icon', sizes: '152x152', href: '/assets/images/apple-touch-icon-152x152-black.png' } },
				{ tag: 'link', attrs: { rel: 'apple-touch-icon', sizes: '120x120', href: '/assets/images/apple-touch-icon-120x120-black.png' } },
				{ tag: 'meta', attrs: { property: 'og:image', content: 'https://pryv.github.io/assets/images/logo-256.png' } },
				{ tag: 'script', attrs: { type: 'application/ld+json' }, content: STRUCTURED_DATA },
				// Staging/preview: keep it out of every search index so it never competes
				// with the live site (belt-and-braces with the Disallow robots.txt).
				...(SITE_BASE ? [{ tag: 'meta', attrs: { name: 'robots', content: 'noindex, nofollow' } }] : []),
			],
			customCss: [
				// Self-hosted Roboto (body) + Roboto Condensed (headings), matching the
				// legacy site typography. Weights mirror the legacy Google Fonts request.
				'@fontsource/roboto/300.css',
				'@fontsource/roboto/400.css',
				'@fontsource/roboto/400-italic.css',
				'@fontsource/roboto/500.css',
				'@fontsource/roboto/700.css',
				'@fontsource/roboto-condensed/300.css',
				'@fontsource/roboto-condensed/400.css',
				'@fontsource/roboto-condensed/700.css',
				'./src/styles/tokens.css',
			],
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/pryv' },
			],
			// Audience-first navigation. URLs are preserved from the legacy site; only the
			// grouping changes. Reference/event-types/tests/agents/ecosystem entries are
			// added as those content areas are ported.
			sidebar: [
				{
					label: 'Get started',
					items: [
						{ slug: 'getting-started' },
						{ slug: 'customer-resources/quickstart-docker' },
					],
				},
				{
					label: 'Understand',
					items: [
						{ slug: 'concepts' },
						{ slug: 'data-in-pryv' },
						{ slug: 'guides/data-modelling' },
					],
				},
				{
					label: 'Guides',
					items: [
						{ slug: 'guides/app-guidelines' },
						{ slug: 'guides/audit-logs' },
						{ slug: 'guides/consent' },
						{ slug: 'guides/cross-account-messaging' },
						{ slug: 'guides/custom-auth' },
						{ slug: 'guides/privacy-by-design' },
						{ slug: 'guides/webhooks' },
					],
				},
				{
					label: 'Reference',
					// event-types, OpenAPI and specs join here as they are ported.
					items: [
						{ label: 'API reference', link: '/reference/' },
						{ label: 'API reference (light)', link: '/reference-light/' },
						{ label: 'System API', link: '/reference-system/' },
						{ label: 'Admin API', link: '/reference-admin/' },
						{ label: 'Event types', link: '/event-types/' },
						{ slug: 'open-api' },
						{ label: 'Functional specifications', link: '/functional-specifications/' },
						{ slug: 'change-log' },
					],
				},
				{
					label: 'Setup & operate',
					items: [
						{ slug: 'customer-resources' },
						{ slug: 'customer-resources/pryv.io-setup' },
						{ slug: 'customer-resources/dns-config' },
						{ slug: 'customer-resources/ssl-certificate' },
						{ slug: 'customer-resources/emails-setup' },
						{ slug: 'customer-resources/mfa' },
						{ slug: 'customer-resources/auth-oauth2' },
						{ slug: 'customer-resources/system-streams' },
						{ slug: 'customer-resources/audit-setup' },
						{ slug: 'customer-resources/observability' },
						{ slug: 'customer-resources/healthchecks' },
						{ slug: 'customer-resources/platform-validation' },
						{ slug: 'customer-resources/backup' },
						{ slug: 'customer-resources/subject-account-backup' },
						{ slug: 'customer-resources/infrastructure-procurement' },
						{ slug: 'customer-resources/single-node-to-cluster' },
						{ slug: 'customer-resources/core-migration' },
						{ slug: 'customer-resources/register-migration' },
					],
				},
				{
					label: 'FAQ',
					items: [{ slug: 'faq-api' }, { slug: 'faq-infra' }],
				},
				{
					label: 'Ecosystem',
					items: [
						{ slug: 'external-resources' },
						{ slug: 'libraries/lib-js' },
						{ slug: 'apps/app-web-user-account' },
					],
				},
				{
					label: 'For agents',
					items: [
						{ slug: 'agents' },
						{ label: 'llms.txt', link: '/llms.txt' },
						{ label: 'llms-full.txt', link: '/llms-full.txt' },
					],
				},
				{
					label: 'Project',
					items: [
						{ slug: 'roadmap' },
						{ label: 'Test results', link: '/tests/' },
					],
				},
			],
		}),
		stagingSubpath(),
	],
});
