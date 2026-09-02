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
			// The full audience-first sidebar is built out with the ported content.
			// Until then Starlight auto-generates the sidebar from src/content/docs/.
		}),
	],
});
