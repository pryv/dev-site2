// v2 Admin / system API reference data. Authored (not converted from the legacy v1 admin
// data) to document the current `/system/*` HTTP surface, which replaced the v1
// config-leader / admin-panel. Rendered by /reference-admin.
import type { Section } from './types';

const authNote = 'Requires the operator admin key in the `Authorization` header (the raw `auth.adminAccessKey` value, not a `Bearer` token). A missing or invalid key returns `404 unknown-resource` (deliberately, to avoid confirming the endpoint exists).';

export const adminSections: Section[] = [
	{
		id: 'overview',
		title: 'Admin API',
		description: `The admin (or "system") API is the operator-facing surface of a Pryv.io core. In v2 it is a set of token-authenticated \`/system/*\` HTTP routes served by the core itself, complemented by the \`bin/*.js\` operator CLIs.

This replaces the v1 admin service entirely: there is **no** config-leader, **no** admin-panel GUI, and **no** JWT admin login. Platform-wide settings now live in the platform database and are managed through the CLIs and the routes below.

All \`/system/*\` routes are always mounted; access is purely key-gated (there is no enable/disable switch).`,
	},
	{
		id: 'authentication',
		title: 'Authentication',
		description: `Every \`/system/*\` request carries the operator admin key **verbatim** in the \`Authorization\` header:

\`\`\`bash
curl -i -H 'Authorization: <adminAccessKey>' \\
  "https://<span class="api-host">{username}.pryv.me</span>/system/admin/cores"
\`\`\`

The key is the \`auth.adminAccessKey\` config value, which is required at boot and must be identical across every core in a cluster. On a missing or wrong key the core answers \`404 unknown-resource\`. The one exception is \`POST /system/admin/cores/ack\`, which authenticates with a one-time join token in the request body instead.`,
	},
	{
		id: 'cores',
		title: 'Cluster and cores',
		sections: [
			{
				id: 'list-cores', type: 'method', title: 'List cores', http: 'GET /system/admin/cores',
				description: `Lists the cluster's cores with a per-core user count. ${authNote}`,
				result: { http: '200 OK', properties: [
					{ key: 'cores', type: 'array of objects', description: 'One entry per core: `id`, `url`, `hosting` (or null), `available` (boolean), `userCount`.' },
				] },
			},
			{
				id: 'ack-core', type: 'method', title: 'Acknowledge a core (bootstrap)', http: 'POST /system/admin/cores/ack',
				description: 'Called by a freshly bootstrapped core to acknowledge joining the cluster. Flips the core to `available: true` and returns a cluster snapshot. **Authenticated by a one-time join token in the request body**, not the admin key. Operators normally trigger this indirectly via `bin/bootstrap.js`.',
				result: { http: '200 OK', description: 'Cluster snapshot from the bootstrap handler.' },
			},
		],
	},
	{
		id: 'certificates',
		title: 'TLS certificates',
		sections: [
			{
				id: 'list-certs', type: 'method', title: 'List certificates', http: 'GET /system/admin/certs',
				description: `Lists TLS certificate metadata. Never returns certificate or key material. ${authNote}`,
				result: { http: '200 OK', properties: [
					{ key: 'certs', type: 'array of objects', description: 'One entry per certificate: `hostname`, `issuedAt`, `expiresAt`, `daysUntilExpiry` (integer or null).' },
				] },
			},
			{
				id: 'force-renew', type: 'method', title: 'Force certificate renewal', http: 'POST /system/admin/certs/force-renew',
				description: `Triggers an operator-initiated ACME certificate rollover on the renewer core. ${authNote}`,
				params: { properties: [
					{ key: 'hostname', type: 'string', optional: true, description: 'The host to renew; defaults to the core\'s primary host.' },
				] },
				result: { http: '200 OK', properties: [
					{ key: 'ok', type: 'boolean' },
					{ key: 'hostname', type: 'string' },
					{ key: 'issuedAt', type: 'timestamp' },
					{ key: 'expiresAt', type: 'timestamp' },
				] },
				errors: [
					{ key: 'invalid-request', http: '400', description: '`hostname` must be a string when provided.' },
					{ key: 'renewal-failed', http: '400', description: '`{ ok: false, error }` when this core is not the renewer, Let\'s Encrypt is disabled, or ACME fails.' },
				],
			},
		],
	},
	{
		id: 'users',
		title: 'Users',
		sections: [
			{
				id: 'list-users', type: 'method', title: 'List users', http: 'GET /system/admin/users',
				description: `Lists all users. ${authNote}`,
				result: { http: '200 OK', properties: [
					{ key: 'users', type: 'array of objects', description: 'Per user: `username`, `id`, `email`, `language`, and `core` (only on multi-core).' },
				] },
			},
			{
				id: 'create-user', type: 'method', title: 'Create user', http: 'POST /system/create-user',
				description: `Registers a new user. ${authNote}`,
				params: { properties: [
					{ key: 'username', type: 'string' },
					{ key: 'password', type: 'string' },
					{ key: 'email', type: 'string' },
					{ key: 'appId', type: 'string' },
				] },
				result: { http: '201 Created', properties: [{ key: 'id', type: 'string', description: 'The new user id.' }] },
			},
			{
				id: 'user-info', type: 'method', title: 'Get user info', http: 'GET /system/user-info/{username}',
				description: `Per-user usage statistics and storage. ${authNote}`,
				params: { properties: [{ key: 'username', type: 'string' }] },
				result: { http: '200 OK', properties: [
					{ key: 'userInfo', type: 'object', description: '`username`, `storageUsed`, `lastAccess`, `callsTotal`, `callsDetail`, `callsPerAccess`.' },
				] },
				errors: [{ key: 'unknown-resource', http: '404', description: 'Unknown user.' }],
			},
			{
				id: 'deactivate-mfa', type: 'method', title: 'Deactivate a user\'s MFA', http: 'DELETE /system/users/{username}/mfa',
				description: `Clears the user's multi-factor authentication. ${authNote}`,
				params: { properties: [{ key: 'username', type: 'string' }] },
				result: { http: '204 No Content' },
			},
			{
				id: 'update-user', type: 'method', title: 'Update user platform fields', http: 'PUT /system/users',
				description: `Updates a user's indexed / unique platform fields. The username cannot be changed. ${authNote}`,
				params: { properties: [
					{ key: 'username', type: 'string' },
					{ key: 'user', type: 'object', description: 'Fields to set.' },
					{ key: 'fieldsToDelete', type: 'object', optional: true },
				] },
				result: { http: '200 OK', properties: [{ key: 'user', type: 'boolean' }] },
			},
			{
				id: 'validate-user', type: 'method', title: 'Reserve a user (pre-registration)', http: 'POST /system/users/validate',
				description: `Reserves a username and unique fields ahead of registration, verifying an invitation token. ${authNote}`,
				params: { properties: [
					{ key: 'username', type: 'string' },
					{ key: 'invitationToken', type: 'string' },
					{ key: 'uniqueFields', type: 'object', optional: true },
					{ key: 'core', type: 'string', optional: true },
				] },
				result: { http: '200 OK', properties: [{ key: 'reservation', type: 'boolean' }] },
				errors: [{ key: 'reservation-refused', http: '400', description: '`{ reservation: false, error }` with id `invitationToken-invalid` or `item-already-exists`.' }],
			},
			{
				id: 'registry-delete', type: 'method', title: 'Delete a user\'s platform fields', http: 'DELETE /system/users/{username}',
				description: `Deletes only the platform-side unique / indexed fields for a user (NOT their stored data). ${authNote}`,
				params: { properties: [
					{ key: 'username', type: 'string' },
					{ key: 'onlyReg', type: 'boolean', description: 'Required (`?onlyReg=true`); this route never touches base storage.' },
					{ key: 'dryRun', type: 'boolean', optional: true },
				] },
				result: { http: '200 OK', properties: [{ key: 'result', type: 'object', description: '`dryRun`, `deleted`.' }] },
				errors: [
					{ key: 'invalid-operation', http: '400', description: 'Missing `onlyReg=true`.' },
					{ key: 'unknown-resource', http: '404', description: 'Unknown user.' },
				],
			},
			{
				id: 'full-delete', type: 'method', title: 'Delete a user (full)', http: 'DELETE /users/{username}',
				description: 'Full cascading delete of a user on their home core: base storage, attachments, high-frequency series, audit, sessions, platform and index entries. Served on the user\'s core (not under `/system`). Accepts either the admin key or the user\'s own personal token in the `Authorization` header (when `user-account.delete` includes `adminToken`, the default).',
				params: { properties: [{ key: 'username', type: 'string' }] },
				result: { http: '200 OK' },
			},
			{
				id: 'get-access', type: 'method', title: 'Resolve an access', http: 'GET /system/accesses/{accessId}',
				description: `Resolves an access id to its owning user and metadata (used for breach scoping). ${authNote}`,
				params: { properties: [{ key: 'accessId', type: 'string' }] },
				result: { http: '200 OK', properties: [{ key: 'accessIndex', type: 'object', description: 'Owning user and access metadata; includes `deleted` for deleted accesses.' }] },
				errors: [{ key: 'unknown-resource', http: '404', description: 'Access not found.' }],
			},
		],
	},
	{
		id: 'mail-templates',
		title: 'Mail templates',
		description: 'Manage the in-core email templates stored in the platform database. The CLI complement is `bin/mail.js`.',
		sections: [
			{
				id: 'list-templates', type: 'method', title: 'List templates', http: 'GET /system/admin/mail/templates',
				description: authNote,
				result: { http: '200 OK', properties: [{ key: 'templates', type: 'array of objects', description: '`type`, `lang`, `part`, `length`.' }] },
			},
			{
				id: 'get-template', type: 'method', title: 'Get a template', http: 'GET /system/admin/mail/templates/{type}/{lang}/{part}',
				description: `Returns the raw Pug of one template as \`text/plain\`. ${authNote}`,
				result: { http: '200 OK' },
				errors: [{ key: 'unknown-resource', http: '404', description: 'Unknown template.' }],
			},
			{
				id: 'put-template', type: 'method', title: 'Upsert a template', http: 'PUT /system/admin/mail/templates/{type}/{lang}/{part}',
				description: `Creates or replaces a template. ${authNote}`,
				params: { properties: [{ key: 'pug', type: 'string', description: 'The template source.' }] },
				result: { http: '204 No Content' },
				errors: [{ key: 'invalid-request-structure', http: '400', description: 'Body must be `{ pug }`.' }],
			},
			{
				id: 'delete-template', type: 'method', title: 'Delete a template', http: 'DELETE /system/admin/mail/templates/{type}/{lang}/{part}',
				description: authNote,
				result: { http: '204 No Content' },
			},
			{
				id: 'send-test', type: 'method', title: 'Send a test mail', http: 'POST /system/admin/mail/send-test',
				description: `Sends a test email using a template. Requires SMTP to be configured. ${authNote}`,
				params: { properties: [
					{ key: 'type', type: 'string' },
					{ key: 'lang', type: 'string' },
					{ key: 'recipient', type: 'string | object', description: 'An email string, or `{ name, email }`.' },
				] },
				result: { http: '200 OK', properties: [{ key: 'sent', type: 'boolean' }] },
			},
		],
	},
	{
		id: 'integrity',
		title: 'Integrity',
		sections: [
			{
				id: 'check-platform-integrity', type: 'method', title: 'Check platform integrity', http: 'GET /system/check-platform-integrity',
				description: `Runs the platform and user-index integrity checks. ${authNote}`,
				result: { http: '200 OK', properties: [{ key: 'checks', type: 'array', description: 'The platform and users-index check results.' }] },
			},
		],
	},
	{
		id: 'operator-clis',
		title: 'Operator CLIs',
		description: `The \`bin/*.js\` scripts complement the HTTP surface (they open the storages / platform database directly). Key ones:

- **bootstrap.js** - cluster bootstrap: \`new-core\`, \`init-ca-holder\`, \`list-tokens\`, \`revoke-token\`, \`promote-core\`.
- **dns-records.js** - manage persistent DNS records: \`list\`, \`load\`, \`delete\`, \`export\`.
- **observability.js** - OpenTelemetry posture: \`show\`, \`enable\`, \`disable\`, \`set-endpoint\`, \`set-header\`, \`set-interval\`, \`set-app-name\`.
- **mail.js** - mail templates: \`templates list|get|set|delete|seed\`, \`send-test\`.
- **oauth-client.js** - OAuth2 app-account management: \`create\`, \`list\`, \`show\`, \`update\`, \`revoke\`, key revocation.
- **backup.js** / **migrate.js** / **migrate-platform.js** - backup/restore and database/platform migrations.
- **integrity-check.js**, **backfill-access-index.js**, **breach-scope.js**, **reconcile-user-cores.js** - maintenance.
- **check-config.js**, **config-to-env.js**, **init.js** - configuration and install.

Run each with \`--help\` for its full options.`,
	},
];
