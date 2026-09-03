// Ported from the legacy reference helpers. Behaviour is preserved verbatim EXCEPT two
// malformed-HTML bugs in the cURL host span are fixed (a `</sapan>` typo and an extra
// nested span in the /users core branch). The `api-*` marker-span class convention is
// unchanged, so the environment switcher keeps working.

type Params = Record<string, unknown>;

export function printJSON (content: unknown): string {
	return JSON.stringify(content, null, 2);
}

/** In-document id for a section (hierarchical). Mirrors the legacy first-dot-only rule. */
export function getDocId (...args: string[]): string {
	return args.join('-').replace('.', '-');
}

export function capitalize (str: string): string {
	return str.charAt(0).toUpperCase() + str.slice(1);
}

export function getApiEndpoint (token: string, username: string, domain = 'pryv.me'): string {
	return `https://${token}@${username}.${domain}/`;
}

function isPlainObject (v: unknown): v is Params {
	return typeof v === 'object' && v !== null && !Array.isArray(v);
}

/** Deep-merge source into target (objects recurse; arrays and primitives overwrite). */
function deepMerge (target: Params, source: Params): Params {
	for (const key of Object.keys(source)) {
		const sv = source[key];
		const tv = target[key];
		if (isPlainObject(sv) && isPlainObject(tv)) deepMerge(tv, sv);
		else target[key] = sv;
	}
	return target;
}

export function getRestCall (params: Params, http: string): string {
	const method = http.split(' ')[0];
	const myParams: Params = { ...params };
	// {id} & {username} live in the REST path, not the body.
	delete myParams.id;
	delete myParams.username;

	if (myParams.update != null && method === 'PUT') {
		const updateParams = myParams.update as Params;
		delete myParams.update;
		deepMerge(myParams, updateParams);
	}

	return JSON.stringify(myParams, null, 2);
}

export function getWebsocketCall (params: Params): string {
	return JSON.stringify(params);
}

export function getCurlCall (params: Params, http: string, server?: string, hasQueryAuth?: boolean): string {
	let [method, path] = http.split(' ');
	if (!server) server = 'core';

	const request = method !== 'GET' ? `-X ${method} ` : '';
	let headers = '';
	let queryString = '';
	let basicAuth = '';
	if (server === 'core') {
		if (method === 'POST' &&
			(path === '/auth/login' ||
			 path === '/account/request-password-reset' ||
			 path === '/account/reset-password' ||
			 path === '/mfa/recover')) {
			headers = "-H 'Origin: https://sw.pryv.me' ";
		} else if (hasQueryAuth) {
			queryString = '?auth={token}';
		} else {
			basicAuth = '{token}@';
		}
	}

	const processedParams: Params = { ...params };
	Object.keys(params).forEach((k) => {
		const newPath = path.replace(`{${k}}`, String(params[k]));
		if (path !== newPath) {
			path = newPath;
			delete processedParams[k];
		}
	});

	let data = '';
	const hasData = (method === 'POST') || (method === 'PUT');
	if (hasData) {
		headers += "-H 'Content-Type: application/json' ";
		if (method === 'PUT' && processedParams.update) {
			data += `-d '${JSON.stringify(processedParams.update)}' `;
		} else {
			data += `-d '${JSON.stringify(processedParams)}' `;
		}
	} else {
		Object.keys(processedParams).forEach((k) => {
			queryString += queryString === '' ? `?${k}=${processedParams[k]}` : `&${k}=${processedParams[k]}`;
		});
	}

	let call = '';
	if (path.startsWith('/users') && server === 'core') {
		call = `curl -i ${request}${headers}${data}"https://<span class="core-reg-curl">{core-subdomain}.pryv.me</span>${path}${queryString}"`;
	} else if (server === 'core') {
		call = `curl -i ${request}${headers}${data}"https://${basicAuth}<span class="api-curl">{username}.pryv.me</span>${path}${queryString}"`;
	} else if (server === 'register') {
		call = `curl -i ${request}${headers}${data}"https://<span class="api-reg-curl">reg.pryv.me</span>${path}${queryString}"`;
	} else if (server === 'admin') {
		call = `curl -i ${request}${headers}${data}"https://<span class="api-admin-curl">lead.pryv.me</span>${path}${queryString}"`;
	}

	// shell variable format for quick copy-paste ({token} -> ${token})
	return call.replace(/({\w+?})/g, (match) => `$${match}`);
}

export function getBatchBlock (methodId: string, params: Params): string {
	return JSON.stringify({ method: methodId, params }, null, 2);
}

export function httpOnly (): string {
	return 'Only available for HTTP REST';
}
