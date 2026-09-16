dataStructure = require("./data-structure.coffee")
examples = require("./examples")
helpers = require("./helpers")
_ = require("lodash")
timestamp = require('unix-timestamp')

# For use within the data declaration here; external callers use `getDocId` (which checks validity)
_getDocId = (sectionId) ->
  return helpers.getDocId("basics", sectionId)

module.exports = exports =
  id: "basics"
  title: "Basics"
  sections: [
    id: "endpoint-url"
    title: "API endpoint"
    description: """
                 Depending on the Pryv.io setup or distribution, the root endpoint can have the following formats:

                 Pryv Lab: `https://{username}.pryv.me`
                 Own Domain: `https://{username}.{domain}`
                 DNS-less (Open): `https://{hostname}/{username}`

                 Each user account has a dedicated root API endpoint as it is potentially served from a different location. The API endpoint format may vary, so check your platform's [service information](#service-info) if needed.

                 You can adapt the examples with "API" selector in the top navigation bar.

                 """
    examples: [
      title: "For instance, user '#{examples.users.one.username}' would be served from

              `https://#{examples.users.one.username}.pryv.me` or `https://host.your-domain.io/#{examples.users.one.username}`"
    ]

  ,

    id: "call-with-http"
    title: "Call with HTTP"
    description: """
                 The API serves regular REST-like HTTP requests, with the usual verbs for reading and manipulating data:

                 - **GET** (parameters: query string)<br>
                   for reading resources
                 - **POST** (parameters: request body)<br>
                   for creating new resources and other methods modifying data
                 - **PUT** (parameters: request body)<br>
                   for modifying resources
                 - **DELETE** (parameters: query string)<br>
                   for removing resources; logical deletion (trashing) is supported for some resources such as events and streams
                 """
    examples: [
      title: "Example request"
      content: """
               Pryv Lab:
               ```http
               GET /events HTTP/1.1
               Host: {username}.pryv.me
               Authorization: {token}
               ```

               DNS-less:
               ```http
               GET /{username}/events HTTP/1.1
               Host: host.your-domain.io
               Authorization: {token}
               ```
               """
    ]
    sections: [
      id: "alternative-http-request-method"
      title: "Alternative HTTP request method"
      description: """
                   For those having trouble with [HTTP access control (CORS) rules](https://developer.mozilla.org/en-US/docs/HTTP/Access_control_CORS), the API allows web apps to fake POST, PUT and DELETE requests through `application/x-www-form-urlencoded` POST requests with the following fields (all optional):
                   """
      properties: [
        key: "_method"
        description: """
                     The HTTP override method to use (usually `PUT` or `DELETE`; `POST` is used if not set).
                     """
      ,
        key: "_auth"
        description: """
                     The `Authorization` header value (alternative to sending the header itself).
                     """
      ,
        key: "_json"
        description: """
                     Considered as the JSON request body if set (overriding all other body content, if any).
                     """
      ]
    ]

  ,

    id: "call-with-websockets"
    title: "Call with websockets"
    description: """
                 The API supports real-time interaction by accepting websocket connections via [Socket.io 2.0](http://socket.io)

                 For API versions prior to 1.5.8, use Socket.io 0.9.
                 """
    sections: [
      id: "connecting"
      title: "Connecting"
      description: """
                   First, load the right Socket.IO client library.

                   Then initialize the connection with the URL:

                   Pryv Lab:
                   ```
                   https://{username}.pryv.me/{username}?auth={accessToken}
                   ```

                   Own Domain:
                   ```
                   https://{username}.{domain}/{username}?auth={accessToken}
                   ```

                   DNS-less:
                   ```
                   https://host.your-domain.io/{username}/{username}?auth={accessToken}
                   ```
                   *Yes, the username is quoted 2 times..*

                   For API versions prior to 1.5.8, append `&resource={username}`.
                   """
      examples: [
        title: "In a web app"
        content: """
                 Pryv.me:
                 ```html
                 <script>
                 var socket = io("https://#{examples.users.one.username}.pryv.me/#{examples.users.one.username}?auth=#{examples.accesses.app.token}");
                 </script>
                 ```
                 Own domain:
                 ```html
                 <script>
                 var socket = io("https://#{examples.users.one.username}.{domain}/#{examples.users.one.username}?auth=#{examples.accesses.app.token}");
                 </script>
                 ```
                 DNS-less:
                 ```html
                 <script>
                 var socket = io("https://host.your-domain.io/#{examples.users.one.username}/#{examples.users.one.username}?auth=#{examples.accesses.app.token}");
                 </script>
                 ```
                 """
      ]
    ,
      id: "call-methods"
      title: "Call methods"
      description: """
                   You call API methods by sending a corresponding Socket.IO [`{method-id}`](#method-ids) message, passing a parameters object and a callback:

                   ```javascript
                   // javascript
                   socket.emit('{method-id}', {/*parameters*/}, function (error, result) {
                     // handle result
                   });
                   ```

                   See [methods ids](#method-ids)
                   """
      errors: [
        key: "invalid-method"
        http: "404"
        description: """
                     The given method id is invalid.
                     """
      ]
      examples: [
        title: "Retrieving events (Javascript)"
        content: """
                 ```javascript
                 socket.emit('events.get', {sortAscending: true}, function (error, result) {
                   // ...
                 });
                 ```
                 """
      ]
    ]
  ,

    id: "subscribe-to-changes"
    title: "Subscribe to changes"
    description: """
                  Get notified when data changes by subscribing to messages.
                  Available messages are:
                    - `eventsChanged`
                    - `streamsChanged`
                    - `accessesChanged`
                    - `systemBoot` (webhooks only)

                  Messages do not include the content of the changes, but they describe what type of resource has been changed (created, updated or deleted).
                  They inform the server that it needs to fetch new or updated data through the API by doing a HTTP GET request with a valid access token.
                  The `systemBoot` message is executed when the notifications system is started in order to query possibly missed data changes.

                  Both transports can be narrowed to **named scopes** so you are notified only of matching changes — see [scoped subscriptions](#scoped-subscriptions-websockets) for websockets and the [webhook](#webhook) `scopes` field for webhooks. A scoped subscription replaces the coarse messages above with the matched scope keys.
                  """
    sections: [
      id: "with-websockets"
      title: "With websockets"
      description: """
                  Get notified of data changes in a web application using websockets.
                  """
      examples: [
        title: "Subscribe to events changes (Javascript)"
        content: """
                  ```javascript
                  socket.on('eventsChanged', function() {
                    // retrieve latest changes and act accordingly
                  });
                  ```
                  """
      ]
    ,
      id: "scoped-subscriptions"
      title: "Scoped subscriptions (websockets)"
      description: """
                  By default a websocket connection receives the coarse `eventsChanged` / `streamsChanged` / `accessesChanged` messages above for **every** change in the account. You can instead register one or more **named scopes** so the server wakes you only when a *matching* change occurs.

                  Manage scopes by emitting these messages (each takes a callback that receives an acknowledgement):

                  - `subscribe` — register scopes. Payload is a single `{ key, kind, query }` or a bulk `{ scopes: { key: { kind, query } } }`. `kind` is one of `events` (default), `streams` or `accesses`; `query` is shaped like the parameters of the matching read method (an [events.get](#get-events) query for `events`, `{ streams }` for `streams`, an accesses filter for `accesses`). Acknowledged with `{ ok: true, keys: [...] }`.
                  - `unsubscribe` — remove scopes. Payload is `{ key }`, `{ keys: [...] }` or `{ all: true }`. Acknowledged with `{ ok: true, keys: [...] }`.
                  - `getSubscriptions` — list the active scopes. Acknowledged with `{ scopes: { key: { kind, query } } }`.

                  As soon as a connection holds at least one scope, it **opts out** of the coarse broadcasts and instead receives a single `notificationsChanged` message whose payload is `{ keys: [...] }` — the matched scope keys. Older servers that don't support scoped subscriptions reject `subscribe` (treating it as an unknown method); clients should fall back to the coarse messages in that case.
                  """
      examples: [
        title: "Subscribe to a scoped events stream (Javascript)"
        content: """
                  ```javascript
                  socket.emit('subscribe', {
                    scopes: {
                      newReadings: { kind: 'events', query: { streams: ['measurements'], types: ['mass/kg'] } },
                      structure:   { kind: 'streams', query: { streams: ['measurements'] } }
                    }
                  }, function (ack) {
                    // ack === { ok: true, keys: ['newReadings', 'structure'] }
                  });

                  socket.on('notificationsChanged', function (payload) {
                    // payload.keys lists which scopes matched, e.g. ['newReadings']
                    // retrieve the latest matching data and act accordingly
                  });
                  ```
                  """
      ]
    ,
      id: "with-webhooks"
      title: "With webhooks"
      description: """
                  Get notified of data changes in a web service using [webhooks](#webhook).

                  An unfiltered webhook reports the coarse change types (`eventsChanged`, `streamsChanged`, …). A [scoped webhook](#webhook) (one created with a `scopes` map) instead reports the **matched scope keys** in the same `messages` array — see the second example below.
                  """
      examples: [
        title: "Webhooks data changes payload"
        content: """
                ```json
                {
                  "messages": [
                    "eventsChanged",
                    "streamsChanged"
                  ],
                  "meta": {
                    "apiVersion": "1.4.11",
                    "serial": "20190802",
                    "serverTime": #{timestamp.now()}
                  }
                }
                ```
                """
      ,
        title: "Scoped webhook data changes payload"
        content: """
                The `messages` array carries the matched scope keys (here a webhook created with scopes `newReadings` and `structure`):
                ```json
                {
                  "messages": [
                    "newReadings"
                  ],
                  "meta": {
                    "apiVersion": "1.4.11",
                    "serial": "20190802",
                    "serverTime": #{timestamp.now()}
                  }
                }
                ```
                """
      ]
    ]

  ,

    id: "method-ids"
    title: "Method ids"
    description: """
                 Pryv.io API methods have ids that are available at each method's doc. For example, the id of the [Get events](#get-events) method is `events.get`.
                 This id is useful in the following:

                 - when calling an API method [using websockets](#call-with-websockets)
                 - when making a [batch call](#call-batch)
                 - for filtering per method id when fetching [audit logs](/guides/audit-logs/)
                 """
    sections: [

    ]

  ,

    id: "service-info"
    title: "Service info"
    http: "GET /service/info"

    description: """
                 Service information provides a unified way for third party services to access the necessary information related to a Pryv.io platform as this route is served by any Pryv.io API endpoint.

                 For many applications, the first step is to authenticate a user. For this you need to know the path to **access** which is usually set to `https://access.{domain}/` or `https://{hostname}/access/`.
                 Fetching the path `/service/info` on any valid URL endpoint will return you a list of useful informations, such as **access**, containing the URL to access.

                 See [Auto-Configuration](/guides/app-guidelines/#auto-configuration) in the guide *App Guidelines*.
                 """
    params:
      properties: []
    result:
      http: "200 OK"
      properties: [

        key: "register"
        type: "string"
        description: """
                    The URL of the register service.
                    """
      ,
        key: "access"
        type: "string"
        description: """
                    The URL to perform [authentication requests](#auth-request).
                    """
      ,
        key: "api"
        type: "string"
        description: """
                    The API endpoint format.
                    """
      ,
        key: "name"
        type: "string"
        description: """
                    The platform name.
                    """
      ,
        key: "home"
        type: "string"
        description: """
                    The URL of the platform's home page.
                    """
      ,
        key: "support"
        type: "string"
        description: """
                    The email or URL of the support page.
                    """
      ,
        key: "terms"
        type: "string"
        description: """
                    The terms and conditions, in plain text or the URL displaying them.
                    """
      ,
        key: "eventTypes"
        type: "string"
        description: """
                    The URL of the list of validated event types.
                    """
      ,
        key: "version"
        type: "string"
        description: """
                    The API version.
                    """
      ]
    examples: [
          title: "Retrieving service information."
          params: {}
          result:
            examples.serviceInfo.info
        ]

  ,

    id: "data-format"
    title: "Data format"
    description: """
                 The API exchanges data with clients in JSON (MIME type `application/json`), except when uploading/downloading attached files.

                 As input, the API accepts JSON payloads of maximum 10MB.
                 """
    examples: [
      title: "Example event"
      content: examples.events.position
    ]

  ,

    id: "authorization"
    title: "Authorization"
    description: """
                 All requests for retrieving and manipulating activity data must carry a valid [access token](##{dataStructure.getDocId("access")}).
                 The preferred method is to use the HTTP `Authorization` header.

                 Access tokens are obtained via the [app authentication](#authenticate-your-app) or from sharing.

                 **Alternative methods:**

                 1. Pryv.io supports the **Basic HTTP** Authorization Scheme This allows to present
                    a Pryv.io endpoint as a single URL without exposing the token in query parameters:

                    <pre><code>curl https://{token}@<span class="api">{username}.pryv.me</span>/access-info
                    </code></pre>

                    This method is not supported by modern browsers but by tools such as [cURL](https://curl.haxx.se), the Node.js library [superagent](https://www.npmjs.com/package/superagent)
                    or [Postman](https://www.getpostman.com).
                    These tools implicitly translate the `${token}@` part of the URL to the `Authorization` header in basic auth format. Please use the main authorization method for tools that do not operate this translation, such as Grafana.

                    Note that Pryv.io does not require a username, so only the token should be Base64 encoded. For more information see [RFC671](https://tools.ietf.org/html/rfc7617 ).

                 2. The access token can be provided in the query string's `auth` parameter, for example during the Socket.IO handshake or for a direct HTTP GET call in a browser:

                    <pre><code>curl https://<span class="api">{username}.pryv.me</span>/access-info?auth={token}
                    </code></pre>

                 """
    examples: [
      title: "HTTP `Authorization` header"
      content: """
               <pre><code>GET <span class='api-user'></span>/events HTTP/1.1
               Host: <span class='api-host'>{username}.pryv.me</span>
               Authorization: {token}
               </code></pre>
               """
    ,
      title: "HTTP `Basic HTTP` authorization header"
      content: """
               <pre><code>GET <span class='api-user'></span>/events HTTP/1.1
               Host: <span class='api-host'>{username}.pryv.me</span>
               Authorization: Basic {Base64 encoded token}
               </code></pre>
               """
    ,
      title: "HTTP `auth` query string parameter"
      content: """
               <pre><code>GET <span class='api-user'></span>/events?auth={token} HTTP/1.1
               Host: <span class='api-host'>{username}.pryv.me</span>
               Authorization: Basic {Base64 encoded token}
               </code></pre>
               """
    ]

  ,

    id: "trusted-apps-verification"
    title: "Trusted apps verification"
    trustedOnly: true
    description: """
                 These API methods require that the `appId` parameter and `Origin` (or `Referer`) header are trusted.

                 Only Apps that need to use a Personal token are be registered as "Trusted Apps".

                 These are usually:
                  1. The web app for the Authentication and Consent process such as [app-web-user-account](https://github.com/pryv/app-web-user-account)
                  2. An admin panel for the end-user to manage Access Tokens and Profile.

                 Trusted app api methods are tagged with <span class="trusted-tag"><span title="Trusted Apps Only" class="label">T</span></span>

                 This setting can be adapted in the Pryv.io service configuration.
                 By default, any valid `appId` works and the `Origin` (or `Referer`) header must be in the form `https://*.{domain}`, ex.: `https://login.{domain}`.
                 """
    examples: [
      title: "HTTP `Origin` header"
      content: """
                <pre><code>POST <span class='api-user'></span>/auth/login HTTP/1.1
               Host: <span class='api-host'>{username}.pryv.me</span>
               Authorization: Basic {Base64 encoded token}
               Origin: https://sw.{domain}</code></pre>
               """
    ,
      title: "HTTP `Referer` header"
      content: """
                <pre><code>POST <span class='api-user'></span>/auth/login HTTP/1.1
               Host: <span class='api-host'>{username}.pryv.me</span>
               Authorization: Basic {Base64 encoded token}
               Referer: https://sw.{domain}/something</code></pre>
               """
    ]
  ,

    id: "v2-badge"
    title: "v2 additions and changes"
    description: """
                 API methods added or whose semantics changed in **Pryv.io v2** (open-pryv.io ≥ 2.0.0-pre.X) are tagged with <span class="v2-tag"><span title="Added or changed in v2" class="label">v2</span></span>

                 v2 is backwards-compatible by default: existing v1 clients continue to work against a v2 server, and v1 servers ignore v2-only request parameters they don't recognise. The badge highlights the surfaces where behaviour or shape changed between major versions, so SDK authors and integrators can scope their compatibility work.

                 See the [change log](/change-log/) for the full per-release breakdown.
                 """
  ,

    id: "authenticate-your-app"
    title: "Authenticate your app"
    description: """
                 To authenticate users in your app, and thus for users to grant your app access to their data, you must:

                 1. Choose an app identifier (min. length 6 chars)
                 2. Fetch the [service information](#service-info)
                 3. Send an [auth request](#auth-request) to the URL exposed by the **access** parameter of the service information
                 4. Open the `authUrl` field of the HTTP response in a browser or webframe. The web page will prompt the user to sign in using her Pryv.io credentials (or to create an account if she doesn't have one).
                 5. The result of the sign-in process: an authenticated Pryv API endpoint or a refusal can be obtained in two ways:

                    - by [polling the URL](#poll-request) obtained in the `poll` field of the HTTP response to the auth request (preferred method)
                    - by being redirected to the `returnURL` provided in the auth request with the result in query parameters

                 #### Generate token app

                 The **Access token generator** is a simple web application that allows its user to enter the parameters of the [Auth request](#auth-request) and performs it. It is accessible at the following URL:

                 ```
                 https://pryv.github.io/app-web-access/?pryvServiceInfoUrl=${pryvServiceInfoUrl}
                 ```

                 For example:

                 [https://pryv.github.io/app-web-access/?pryvServiceInfoUrl=https://reg.pryv.me/service/info](https://pryv.github.io/app-web-access/?pryvServiceInfoUrl=https://reg.pryv.me/service/info)



                 """
    sections: [
      id: "auth-request"
      title: "Auth request"
      type: "method"
      description: """
                   The API endpoint to use is given by the [service information's](#service-info) `access` property.
                   """
      http:
        text: "POST to `{serviceInfo.access}`"
      httpOnly: true
      params:
        properties: [
          key: "requestingAppId"
          type: "string"
          description: """
                       Your app's identifier.
                       """
        ,
          key: "requestedPermissions"
          type: "array of permission request objects"
          description: """
                       The requested permissions. Each permission request has properties:
                       """
          properties: [
            key: "streamId"
            type: "[identifier](##{dataStructure.getDocId("identifier")})"
            description: """
                         The id of the requested stream.
                         """
          ,
            key: "level"
            type: "`read`|`contribute`|`manage`"
            description: """
                         The required permission level.
                         """
          ,
            key: "defaultName"
            type: "string"
            description: """
                         The name to create the stream if needed (in the language of the user).
                         """
          ]
        ,
          key: "languageCode"
          type: "string"
          optional: true
          description: """
                       The two-letter ISO (639-1) code of the language in which to display user instructions, if possible. Default: `en`.
                       """
        ,
          key: "returnURL"
          type: "string"
          optional: true
          description: """
                       The URL to redirect the user to after authentication completes.
                       Required if you are not using polling to retrieve the authentication result (see Result below).
                       """
        ,
          key: "clientData"
          type: "[key-value](##{dataStructure.getDocId("key-value")})"
          optional: true
          description: """
                       Additional client data that will be transmitted alongside the auth request (see Result below).
                       """
        ,
          key: "authUrl"
          type: "string"
          optional: true
          description: """
                       Custom authentication-page URL for this request (your own auth UI instead of the platform's default page).
                       Honored only when it matches one of the operator-configured `access.trustedAuthUrls` entries: same protocol and host, and the path must equal the entry's path or extend it on a `/` segment boundary.
                       A non-matching `authUrl` (or any `authUrl` when the platform configures no trusted entries) fails the request with `invalid-parameters` (HTTP 400) — it is never silently ignored.
                       """
        ,
          key: "serviceInfo"
          type: "object"
          optional: true
          description: """
                       Overrides the default [service information](#service-info) object that will be transmitted in the polling responses.
                       """
        ,
          key: "deviceName"
          type: "string"
          optional: true
          description: """
                       See [access data structure](##{dataStructure.getDocId("access")})
                       """
        ,
          key: "expireAfter"
          type: "number"
          optional: true
          description: """
                       See [access data structure](##{dataStructure.getDocId("access")})
                       """
        ,
          key: "referer"
          type: "string"
          optional: true
          description: """
                       Used when creating a user in the process of authentication. See [Create user method](/reference-system/#create-user).
                       """
        ]
      result: [
        title: "Result: need sign-in"
        http: "200"
        properties: [
          key: "status"
          type: "`NEED_SIGNIN`"
          description: """
                       Authentication in progress.
                       """
        ,
          key: "url"
          type: "string"
          description: """
                       **(DEPRECATED)** Please use the `authUrl` parameter.

                       The URL of the authentication page to show the user from your app as popup or webframe.
                       """
        ,
          key: "authUrl"
          type: "string"
          description: """
                       The URL of the authentication page to show the user from your app as popup or webframe.
                       """
        ,
          key: "key"
          type: "string"
          description: """
                       The key used to identify the auth request. It is also part of the poll URL described just below.
                       """
        ,
          key: "poll"
          type: "string"
          description: """
                       The poll URL to use for retrieving the auth result via an HTTP GET request.
                       Responses to polling requests are the same as those from the auth request.
                       """
        ,
          key: "poll_rate_ms"
          type: "number"
          description: """
                       The rate at which the poll URL can be polled, in milliseconds.
                       """
        ,
          key: "requestingAppId"
          type: "string"
          description: """
                       The app identifier provided during the auth request.
                       """
        ,
          key: "requestedPermissions"
          type: "string"
          description: """
                       The permissions provided during the auth request.
                       """
        ,
          key: "lang"
          type: "string"
          optional: true
          description: """
                       The language code provided during the auth request.
                       """
        ,
          key: "returnURL"
          type: "string"
          optional: true
          description: """
                       The return URL provided during the auth request.
                       """
        ,
          key: "clientData"
          type: "[key-value](##{dataStructure.getDocId("key-value")})"
          optional: true
          description: """
                       The client data provided during the auth request.
                       """
        ,
          key: "serviceInfo"
          type: "string"
          optional: true
          description: """
                       The [service information](#service-info).
                       """
        ]
      ]
      examples: [
        title: "Auth request on Pryv Lab"
        content: """
                 ```http
                 POST https://access.pryv.me/access HTTP/1.1
                 Host: access.pryv.me

                 {
                   "requestingAppId": "test-app-id",
                   "requestedPermissions": [
                     {
                       "streamId": "diary",
                       "level": "read",
                       "defaultName": "Journal"
                     },
                     {
                       "streamId": "position",
                       "level": "contribute",
                       "defaultName": "Position"
                     }
                   ],
                   "languageCode": "fr"
                 }
                 ```
                 """
        result:
          status: 'NEED_SIGNIN'
          authUrl: 'https://pryv.github.io/app-web-user-account/auth?lang=fr&key=6CInm4R2TLaoqtl4&requestingAppId=test-app-id&poll=https%3A%2F%2Faccess.pryv.me%2Faccess%2F6CInm4R2TLaoqtl4&poll_rate_ms=1000&serviceInfo=https%3A%2F%2Freg.pryv.me%2Fservice%2Finfo'
          key: '6CInm4R2TLaoqtl4'
          poll: 'https://access.pryv.me/access/6CInm4R2TLaoqtl4',
          poll_rate_ms: 1000,
          requestingAppId: 'test-app-id',
          requestedPermissions: [
              {
                  streamId: 'diary',
                  level: 'read',
                  defaultName: 'Journal'
              },
              {
                  streamId: 'position',
                  level: 'contribute',
                  defaultName: 'Position'
              }
          ],
          lang: 'fr',
          serviceInfo: {}

      ,
        title: 'Auth request using cURL'
        content: """
                 ```bash
                 curl -i -H 'Content-Type: application/json' -X POST -d '{"requestingAppId": "my-app-id","requestedPermissions": [{"streamId": "diary","level": "read","defaultName": "Journal"},{"streamId": "position","level": "contribute","defaultName": "Position"}]}' "https://access.pryv.me/access"
                 ```
                 """
      ]
    ,
      id: "poll-request"
      title: "Poll request"
      type: "method"
      http:
        text: "GET `{needSignInResponse.poll}`"
      httpOnly: true
      description: """
                   The polling URL is given by the `poll` parameter in the result the [Auth Request](#auth-request) or a Poll request.
                   """
      ,
      result: [
        title: "Result: need sign-in"
        http: "200"
        description: """
                     indentical to `RESULT: SIGN-IN` from [Auth Request](#auth-request)
                     """
      ,
        title: "Result: accepted"
        http: "200"
        properties: [
          key: "status"
          type: "`ACCEPTED`"
          description: """
                       Authentication successful.
                       """
        ,
          key: "username"
          type: "string"
          description: """
                       **(DEPRECATED)** Please use the `apiEndpoint` parameter.

                       The authenticated user's username.
                       """
        ,
          key: "token"
          type: "string"
          description: """
                       **(DEPRECATED)** Please use the `apiEndpoint` parameter.

                       Your app's API access token.
                       """
        ,
          key: "apiEndpoint"
          type: "string"
          description: """
                       The API endpoint containing the authorization token. See [app guidelines](/guides/app-guidelines/).
                       """
        ,
          key: "serviceInfo"
          type: "object"
          optional: true
          description: """
                       The [service information](#service-info).
                       """
        ]
      ,
        title: "Result: refused"
        http: "403"
        properties: [
          key: "status"
          type: "`REFUSED`"
          description: """
                       Authentication failed.
                       """
        ,
          key: "reasonID"
          type: "string"
          description: """
                       A code indicating the reason for the failure.
                       """
        ,
          key: "message"
          type: "string"
          description: """
                       A message indicating the reason for the failure.
                       """
        ,
          key: "serviceInfo"
          type: "object"
          optional: true
          description: """
                       The [service information](#service-info).
                       """
        ]
      ]
      examples: [
        title: 'Polling request on Pryv Lab'
        content: """
                 ```http
                 GET /access/6CInm4R2TLaoqtl4 HTTP/1.1
                 Host: access.pryv.me
                 ```
                 """
      ,
        title: '**"Need sign-in"** response'
        content: """
                 identical to `RESULT: NEED SIGN-IN` from [Auth Request](#auth-request)
                 ```
                 {
                   "status": "NEED_SIGNIN",
                   ...
                 }
                 ```
                 """
      ,
        title: '**"Accepted"** response'
        content: """
                 ```json
                 {
                    "status": "ACCEPTED",
                    "apiEndpoint": "#{helpers.getApiEndpoint(examples.accesses.app.token, examples.users.one.username)}",
                    "serviceInfo": {...}
                }
                 ```
                 """
      ,
        title: '**"Refused"** response'
        content: """
                 ```json
                 {
                    "status": "REFUSED",
                    "resonID": "REASON_UNDEFINED",
                    "message": "...."
                    "serviceInfo": {...}
                }
                 ```
                 """
      ]
    ]

  ,

    id: "common-metadata"
    title: "Common metadata"
    description: """
                 General API and server information.
                 """
    sections: [
      id: "http"
      title: "In HTTP headers"
      description: """
                   Every HTTP response has header:
                   """
      properties: [
        key: "API-Version"
        description: """
                     The version of the API in the form `{major}.{minor}.{revision}`. Mirrored in method results as `meta.apiVersion`.
                     """
      ,
        key: "Pryv-Access-Id"
        optional: true
        description: """
                     The id of the [Access](##{dataStructure.getDocId("access")}) used for the API call.
                     Only present if a valid access token has been provided.
                     """
      ]
    ,
      id: "method-results"
      title: "In method results"
      description: """
                   Every JSON method result has properties:
                   """
      properties: [
        key: "meta.apiVersion"
        description: """
                     The version of the API in the form `{major}.{minor}.{revision}`. Mirrored in HTTP header `API-Version`.
                     """
      ,
        key: "meta.serverTime"
        description: """
                     The current server time as a [timestamp](##{dataStructure.getDocId("timestamp")}). Keeping track of server time is necessary to properly handle time in API calls.
                     """
      ,
        key: "meta.serial"
        description: """
                     The serial will change every time the core or register is updated. If you compare it with the serial of a previous response and notice a difference, you should reload the service information.
                     """
      ]
      examples: [
        title: "Metadata in API Response"
        content: examples.metadata.apiResponse
      ]
    ]


  ,

    id: "errors"
    title: "Errors"
    description: """
                 When an error occurs, the API returns a response with an `error` object (see [error](##{dataStructure.getDocId("error")}) detailing the cause. (Over HTTP, the response status is set to 4xx or 5xx.) In this documentation, errors are identified by their `id`.
                 """
    examples: [
      content: examples.errors.invalidAccessToken
    ]
    sections: [
      id: "usual-errors"
      title: "Usual errors"
      description: """
                   See also [error data structure](##{dataStructure.getDocId("error")}).
                   """
      properties: [
        key: "invalid-request-structure"
        http: "400"
        description: """
                     The request's structure is not that expected; for example: invalid JSON syntax, unexpected multipart structure when uploading file attachments.
                     """
      ,
        key: "invalid-parameters-format"
        http: "400"
        description: """
                     The request's parameters do not follow the expected format. The error's `data` contains an array of validation errors.
                     """
      ,
        key: "unknown-referenced-resource"
        http: "400"
        description: """
                     One or more referenced resource(s) can't be found. The error's `data.{method-parameter-key}` (e.g. `data.streamId`) contains the unknown reference(s).
                     """
      ,
        key: "invalid-access-token"
        http: "401"
        description: """
                     The access token is missing or invalid.
                     """
      ,
        key: "forbidden"
        http: "403"
        description: """
                     The given access token does not grant permission for this operation. See [accesses](##{dataStructure.getDocId("access")}) for more details about accesses and permissions.
                     """
      ,
        key: "unknown-resource"
        http: "404"
        description: """
                     The resource can't be found.
                     """
      ,
        key: "removed-method"
        http: "410"
        description: """
                     The resource or method has been removed from the API.
                     """
      ,
        key: "too-many-results"
        http: "413"
        description: """
                     The `events.get` method in batch or websocket call yielded too many results. Call the API method directly, narrow the request scope or page the request.
                     """
      ,
        key: "user-account-relocated"
        http: "301"
        description: """
                     The user has relocated her account to another server. Both the `Location` header and the error's `data` contain the equivalent URL pointing to the physical server now hosting the user's account. This error can only occur between the moment the account is relocated and the moment your DNS is updated to point to the new server. So we're stretching the HTTP convention a little, in that the returned URL should not be used permanently (only until `{username}.pryv.me` points to the correct server again). It's up to you to decide whether to keep it for the duration of the session (if you use sessions), for a given time, etc.
                     """
      ,
        key: "user-intervention-required"
        http: "402"
        description: """
                     The request cannot be served temporarily because the user's account has exceeded its limits. The user must log into her account and fix the issue.
                     """
      ,
        key: "wrong-core"
        http: "421"
        description: """
                     **Multi-core deployments only.** The request reached a core that does not host the requested user account.
                     The error's `data.coreUrl` contains the correct API endpoint for this user. Clients MUST retry the
                     request directly against `coreUrl`. An HTTP redirect is not used because cross-origin redirects strip
                     the `Authorization` header.
                     """
      ]
    ]
  ]

# Returns the in-doc id of the given type, for safe linking from other doc sections
exports.getDocId = (typeId) ->
  typeSection = _.find(exports.sections, (type) -> type.id == typeId)
  if typeSection
    return helpers.getDocId(exports.id, typeId)
  else
    throw new Error("Unknown type id")
