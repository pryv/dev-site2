// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Canonical publish target is the org page (served at the domain root, no base path).
// `build.format: 'directory'` reproduces the legacy trailing-slash directory URLs so
// existing links (e.g. /guides/webhooks/) keep resolving after the cutover.
// https://astro.build/config
export default defineConfig({
	site: 'https://pryv.github.io',
	build: { format: 'directory' },
	integrations: [
		starlight({
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
					// lib-js and app-web-user-account overview pages join here.
					items: [{ slug: 'external-resources' }],
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
