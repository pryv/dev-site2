// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightLinksValidator from 'starlight-links-validator';

// Canonical publish target is the org page (served at the domain root, no base path).
// `build.format: 'directory'` reproduces the legacy trailing-slash directory URLs so
// existing links (e.g. /guides/webhooks/) keep resolving after the cutover.
// https://astro.build/config
export default defineConfig({
	site: 'https://pryv.github.io',
	build: { format: 'directory' },
	// Legacy /reference-full/ was itself a redirect to the reference; preserve it.
	redirects: { '/reference-full': '/reference' },
	integrations: [
		starlight({
			// The reference / event-types / functional-specs pages are custom (non-collection)
			// routes, so their in-page anchors cannot be introspected here; they are covered
			// by a dedicated anchor-parity check instead. Exclude them from link validation.
			plugins: [starlightLinksValidator({
				errorOnRelativeLinks: false,
				exclude: [
					// /tests (test results) is not built yet; it needs the external results repo.
					'/tests', '/tests/',
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
				{ tag: 'meta', attrs: { property: 'og:image', content: '/assets/images/logo-256.png' } },
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
					// tests results page joins here.
					items: [{ slug: 'roadmap' }],
				},
			],
		}),
	],
});
