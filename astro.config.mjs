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
			customCss: ['./src/styles/tokens.css'],
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/pryv' },
			],
			// Audience-first navigation. URLs are preserved from the legacy site; only the
			// grouping changes. Reference/event-types/tests/agents/ecosystem entries are
			// added as those content areas are ported.
			sidebar: [
				{
					label: 'Get started',
					items: [{ slug: 'getting-started' }],
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
					// API / admin / system reference, event-types, OpenAPI and specs join here.
					items: [{ slug: 'change-log' }],
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
