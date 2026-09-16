const _ = require('lodash');

module.exports = {
  printJSON: (content) => {
    return JSON.stringify(content, null, 2);
  },

  /**
   * Generic function to determine the in-doc id of a given section.
   */
  getDocId: (...args) => {
    return args.join('-').replace('.', '-');
  },

  capitalize: (str) => {
    return str.charAt(0).toUpperCase() + str.slice(1);
  },

  getApiEndpoint: (token, username, domain) => {
    if (domain == null) { domain = 'pryv.me'; }
    return `https://${token}@${username}.${domain}/`;
  },

  getRestCall: (params, http) => {
    const method = http.split(' ')[0];
    const myParams = _.clone(params);
    // we can remove {id} & {username} as it is exposed in the rest PATH
    delete myParams.id;
    delete myParams.username;

    if (myParams.update != null && method === 'PUT') {
      const updateParams = myParams.update;
      delete myParams.update;
      _.merge(myParams, updateParams);
    }

    return JSON.stringify(myParams, null, 2);
  },

  getWebsocketCall: (params) => {
    return JSON.stringify(params);
  },

  getCurlCall: (params, http, server, hasQueryAuth) => {
    let [method, path] = http.split(' ');
    if (!server) {
      server = 'core';
    }

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
      } else {
        if (hasQueryAuth) {
          queryString = '?auth={token}';
        } else {
          basicAuth = '{token}@';
        }
      }
    }

    const processedParams = _.clone(params);
    Object.keys(params).forEach((k) => {
      const newPath = path.replace(`{${k}}`, params[k]);
      if (path !== newPath) {
        path = newPath;
        delete processedParams[k];
      }
    });

    let data = '';
    const hasData = ((method === 'POST') || (method === 'PUT'));
    if (hasData) {
      headers += "-H 'Content-Type: application/json' ";
      if ((method === 'PUT') && processedParams.update) {
        data += `-d '${JSON.stringify(processedParams.update)}' `;
      } else {
        data += `-d '${JSON.stringify(processedParams)}' `;
      }
    } else {
      Object.keys(processedParams).forEach((k) => {
        if (queryString === '') {
          queryString += `?${k}=${processedParams[k]}`;
        } else {
          queryString += `&${k}=${processedParams[k]}`;
        }
      });
    }

    let call = '';
    if (path.startsWith('/users') && server === 'core') {
      call = `curl -i ${request}${headers}${data}"https://<span class="core-reg-curl">{core-subdomain}</sapan>.pryv.me</span>${path}${queryString}"`;
    } else if (server === 'core') {
      call = `curl -i ${request}${headers}${data}"https://${basicAuth}<span class="api-curl">{username}.pryv.me</span>${path}${queryString}"`;
    } else if (server === 'register') {
      call = `curl -i ${request}${headers}${data}"https://<span class="api-reg-curl">reg.pryv.me</span>${path}${queryString}"`;
    } else if (server === 'admin') {
      call = `curl -i ${request}${headers}${data}"https://<span class="api-admin-curl">lead.pryv.me</span>${path}${queryString}"`;
    }

    // use shell variable format to help with quick copy-paste
    return call.replace(/({\w+?})/g, match => `$${match}`);
  },

  getBatchBlock: (methodId, params) => {
    return JSON.stringify({ method: methodId, params: params }, null, 2);
  },

  httpOnly: () => {
    return 'Only available for HTTP REST';
  }
};
