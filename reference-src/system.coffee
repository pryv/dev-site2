examples = require("./examples")
helpers = require("./helpers")
_ = require("lodash")

# For use within the data declaration here; external callers use `getDocId` (which checks validity)
_getDocId = (sectionId, subsectionId, methodId) ->
  return helpers.getDocId("system", sectionId, subsectionId, methodId)

module.exports = exports =
  id: "system"
  title: "System-level API"
  sections: [
    id: "basics"
    title: "Basics"
    description: """
                 This document describes Pryv.io's **system-level** API, allowing developers to create and manage user accounts.
                 """
    sections: [
      id: "services-involved"
      title: "Services involved"
      description: """
                   Unlike user account data, which is fully managed by the core server hosting each account, managing the accounts themselves (e.g. retrieval, creation, deletion) is handled by the core servers *and* the central register server (AKA user account directory).
                   A color tag on the API method indicates the server to which you should make the request.

                   - The **core servers** own the account management processes, i.e. data creation and deletion
                   - The **register server** maintains the list of account usernames and their hosting locations; it helps account management by providing checks (for creation) and is notified of all relevant changes by the core servers.
                   """
    ,
      id: "endpoint-url"
      title: "API endpoint"
      description: """
                   The methods are called via HTTPS on the register or core server depending on the method:

                   - Register: `https://reg.{domain}` or `https://{hostname}/reg` for DNS-less setup.
                   - Core: `https://{core-subdomain}.{domain}` or `https://{hostname}` for DNS-less setup.

                   You can adapt the examples with "API" selector in the top navigation bar.
                  """
    ,
      id: "account-creation"
      title: "Account creation"
      description: """
                   The steps for creating a new Pryv.io account are the following:

                   1. The client calls the register server to get a list of available hostings (core server locations), see [Get Hostings](/reference-system/#get-hostings).
                   2. The client calls the URL under "availableCore" for the hosting it chose with the desired new account data, see [Create user](#create-user).
                   3. Data is verified.
                   4. If validation passes, the user is saved and an authenticated apiEndpoint is returned to the caller. See [app guidelines](/guides/app-guidelines/).

                  **(DEPRECATED)** Please use the new account creation flow described above.

                   1. Client calls the register server to get a list of available hostings (core server locations), see [Get Hostings](#get-hostings).
                   2. Client calls register server with desired new account data (including which core server should host the account), see [Create user](#create-user).
                   3. register server verifies data, hands it over to specified core server if OK
                   4. Core server verifies data, creates account if OK (sending welcome email to user), returns status (including created account id) to register server
                   5. register server updates directory if OK, returns status to client
                   """
    ]
  ,
    id: "api-methods"
    title: "API methods"
    description: """
                 """
    sections: [
      id: "admin"
      title: "Admin"
      adminOnly: true
      description: """
                  Methods for platform administration.

                  These calls are limited to accredited persons and are flagged as `Admin only`.

                  Admin api calls are tagged with <span class="admin-tag"><span title="Admin Only" class="label">A</span></span>

                  They must carry the admin key in the HTTP `Authorization` header.
                  This key is the platform setting `auth.adminAccessKey`. A call without it, or with another value, answers `404 unknown-resource`, as if the route did not exist.
                  """
      sections: [
        id: "users.get"
        type: "method"
        title: "Get users"
        http: "GET /system/admin/users"
        httpOnly: true
        server: "core"
        description: """
                    Get the list of all users registered on the platform.
                    """
        params:
          properties: []
        result:
          http: "200 OK"
          properties: [
            key: "users"
            type: "array of objects"
            description: """
                        One object per user: `username`, `id`, `email` and `language`, plus `core`, the URL of the core that hosts the account, on a multi-core platform.
                        """
          ]
        examples: [
          title: "Fetching the users list for a Pryv.io platform"
          params: {}
          result:
            users: [
              username: examples.users.three.username
              id: examples.users.three.id
              email: examples.users.three.email
              language: examples.users.three.language
            ,
              username: examples.users.four.username
              id: examples.users.four.id
              email: examples.users.four.email
              language: examples.users.four.language
            ]
        ]
      ,
        id: "servers.get"
        type: "method"
        title: "Get core servers"
        http: "GET /admin/servers"
        httpOnly: true
        server: "register"
        description: """
                    Get the list of all core servers with the number of users on them.
                    """
        params:
          properties: []
        result:
          http: "200 OK"
          properties: [
            key: "servers"
            type: "object"
            description: """
                        Object mapping each available core server to its user count.
                        """
          ]
        examples: [
          title: "Fetching the core servers list for a Pryv.io platform"
          params: {}
          result:
            servers: examples.register.usersCount
        ]
      ,
        id: "servers.users.get"
        type: "method"
        title: "Get users on core server"
        http: "GET /admin/servers/{serverName}/users"
        httpOnly: true
        server: "register"
        description: """
                    Get the list of all users registered on a specific core server.
                    """
        params:
          properties: [
            key: "serverName"
            type: "string"
            http:
              text: "set in request path"
            description: """
                        The name of the core server.
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "users"
            type: "array"
            description: """
                        Array of user data.
                        """
          ]
        examples: [
          title: "Fetching the users list for a specifc core server."
          params: {
            serverName: examples.users.three.server
          }
          result:
            users: [
                examples.users.three,
            ],
        ]
      ,
        id: "servers.rename"
        type: "method"
        title: "Rename core server"
        http: "GET /admin/servers/{srcServerName}/rename/{dstServerName}"
        httpOnly: true
        server: "register"
        description: """
                    Rename a core server, thus reassigning the users from srcServer to dstServer.
                    """
        params:
          properties: [
            key: "srcServerName"
            type: "string"
            http:
              text: "set in request path"
            description: """
                        The current name of the core server to rename.
                        """
          ,
            key: "dstServerName"
            type: "string"
            http:
              text: "set in request path"
            description: """
                        The new name of the core server.
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "count"
            type: "number"
            description: """
                        The count of reassigned users.
                        It can be 0 if `srcServerName` did not match any existing core server.
                        """
          ,
            key: "externalIds"
            type: "number"
            description: """
                        The number of [external-id](#external-ids) index rows moved to the new core name (from open-pryv.io 2.0.0-rc.60). Run the rename with the renamed core stopped: a claim it commits after the rename would still carry the old name.
                        """
          ]
        errors: [
          key: "INVALID_DATA"
          http: "400"
          description: """
                      The server name (source or destination) is invalid because of an unrecognized format.
                      """
        ]
        examples: [
          title: "Renaming a core server."
          params: {
            srcServerName: examples.register.servers[0]
            dstServerName: examples.register.servers[1]
          }
          result:
            count: 1
            externalIds: 0
        ]
      ,
        id: "external-ids"
        title: "External ids"
        adminOnly: true
        description: """
                    Namespaces of [external ids](/customer-resources/external-ids/) and the release of an id claimed by the wrong account. Served by every core under `/system/admin/` (not by the register server), with the admin key. The guide explains the model, the blinding and the procedures.
                    """
        sections: [
          id: "extIdNamespaces.list"
          type: "method"
          title: "List external-id namespaces"
          http: "GET /system/admin/ext-id-ns"
          httpOnly: true
          server: "core"
          description: """
                      Lists the namespaces of the platform (from open-pryv.io 2.0.0-rc.58). The salt of a namespace is never returned. Not audited (a read).
                      """
          params:
            properties: []
          result:
            http: "200 OK"
            properties: [
              key: "namespaces"
              type: "array of objects"
              description: """
                          One object per namespace, ordered by name: `namespace` (the name), `createdAt` (a [timestamp](/reference/#data-structure-timestamp)), `label` (shown to users on the auth page) and `defaultMode` (`hint` or `forced`).
                          """
            ]
          examples: [
            title: "Listing the namespaces"
            params: {}
            result:
              namespaces: [
                namespace: "clinic-ehr"
                createdAt: 1792800000
                label: "Clinic patient record"
                defaultMode: "hint"
              ]
          ]
        ,
          id: "extIdNamespaces.get"
          type: "method"
          title: "Get an external-id namespace"
          http: "GET /system/admin/ext-id-ns/{namespace}"
          httpOnly: true
          server: "core"
          description: """
                      Gets one namespace (from open-pryv.io 2.0.0-rc.58), never its salt. Not audited (a read).
                      """
          params:
            properties: [
              key: "namespace"
              type: "string"
              http:
                text: "set in request path"
              description: """
                          The namespace name.
                          """
            ]
          result:
            http: "200 OK"
            properties: [
              key: "namespace"
              type: "object"
              description: """
                          `namespace`, `createdAt`, `label` and `defaultMode`, as in the list.
                          """
            ]
          errors: [
            key: "invalid-parameters-format"
            http: "400"
            description: """
                        The name does not follow the namespace name rule.
                        """
          ,
            key: "unknown-resource"
            http: "404"
            description: """
                        No namespace has this name.
                        """
          ]
          examples: [
            title: "Getting a namespace"
            params:
              namespace: "clinic-ehr"
            result:
              namespace:
                namespace: "clinic-ehr"
                createdAt: 1792800000
                label: "Clinic patient record"
                defaultMode: "hint"
          ]
        ,
          id: "extIdNamespaces.set"
          type: "method"
          title: "Create or update an external-id namespace"
          http: "PUT /system/admin/ext-id-ns/{namespace}"
          httpOnly: true
          server: "core"
          description: """
                      Creates the namespace, or updates its label or default mode (from open-pryv.io 2.0.0-rc.58). On creation the server generates the namespace's salt; it never changes afterwards and is never returned. Answers `201 Created` on creation, `200 OK` on an update. Audited, without a user.
                      """
          params:
            properties: [
              key: "namespace"
              type: "string"
              http:
                text: "set in request path"
              description: """
                          The namespace name: 2 to 63 characters, lowercase letters, digits and `-`, starting with a letter or a digit (`^[a-z0-9][a-z0-9-]{1,62}$`).
                          """
            ,
              key: "label"
              type: "string"
              optional: true
              description: """
                          The name shown to users on the auth page, 1 to 80 characters. Defaults to the namespace name on creation; unchanged on an update when omitted.
                          """
            ,
              key: "defaultMode"
              type: "`hint`|`forced`"
              optional: true
              description: """
                          The mode of an auth request or a registration that carries an id of this namespace without a `mode`. Defaults to `hint` on creation; unchanged on an update when omitted. `forced` is honoured from open-pryv.io 2.0.0-rc.59.
                          """
            ]
          result:
            http: "201 Created"
            properties: [
              key: "namespace"
              type: "object"
              description: """
                          The namespace after the call: `namespace`, `createdAt`, `label` and `defaultMode` (no salt). The same body comes with `200 OK` on an update.
                          """
            ]
          errors: [
            key: "invalid-parameters-format"
            http: "400"
            description: """
                        The name, the label or the default mode does not follow the rules above.
                        """
          ]
          examples: [
            title: "Creating a namespace"
            params:
              namespace: "clinic-ehr"
              label: "Clinic patient record"
            result:
              namespace:
                namespace: "clinic-ehr"
                createdAt: 1792800000
                label: "Clinic patient record"
                defaultMode: "hint"
          ]
        ,
          id: "extIdNamespaces.delete"
          type: "method"
          title: "Delete an external-id namespace"
          http: "DELETE /system/admin/ext-id-ns/{namespace}"
          httpOnly: true
          server: "core"
          description: """
                      Deletes the namespace (from open-pryv.io 2.0.0-rc.58). Refused while any account holds an id of the namespace, unless `force` is set: then only the namespace row goes, and each core's reconcile (`bin/reconcile-user-cores.js --ext-ids`) reports its local ids of that namespace and keeps them. A deleted salt cannot be recovered: every id of the namespace is orphaned. Answers `204 No Content`. Audited, without a user.
                      """
          params:
            properties: [
              key: "namespace"
              type: "string"
              http:
                text: "set in request path"
              description: """
                          The namespace name.
                          """
            ,
              key: "force"
              type: "boolean"
              optional: true
              http:
                text: "query parameter"
              description: """
                          `true` to delete the namespace even though ids of it are held.
                          """
            ]
          result:
            http: "204 No Content"
          errors: [
            key: "invalid-parameters-format"
            http: "400"
            description: """
                        The name does not follow the namespace name rule.
                        """
          ,
            key: "unknown-resource"
            http: "404"
            description: """
                        No namespace has this name.
                        """
          ,
            key: "external-id-namespace-in-use"
            http: "409"
            description: """
                        Accounts hold ids of the namespace and `force` is not set.
                        """
          ]
          examples: []
        ,
          id: "extIdRelease"
          type: "method"
          title: "Release an external id claimed by the wrong account"
          http: "POST /system/admin/ext-id/release"
          httpOnly: true
          server: "core"
          description: """
                      Removes the link between an id and the account that holds it, so the right account can claim it (from open-pryv.io 2.0.0-rc.60). Send it to the core that holds the id; another core answers `307` with that core in `server` (and the `Location` header): send the call again there. The answer never names the account.

                      The account that held the id gets an `account.externalIds.adminRelease` entry in its own audit trail (the namespace and the reason, never the value) and, when the platform sends mail, the `external-id-released` mail with the namespace label and the reason (setting `services.email.enabled.externalIdReleased`, template `services.email.externalIdReleasedTemplate`). The holder reads the reason as written: keep it factual and free of anyone else's data. A failed mail does not undo the release. The call itself is audited without a user. See the guide, [Releasing an id claimed by the wrong account](/customer-resources/external-ids/#releasing-an-id-claimed-by-the-wrong-account).
                      """
          params:
            properties: [
              key: "namespace"
              type: "string"
              description: """
                          The namespace of the id.
                          """
            ,
              key: "blindedValue"
              type: "string"
              description: """
                          The blinded value of the id, computed as for a claim.
                          """
            ,
              key: "reason"
              type: "string"
              description: """
                          Why the id is released, 1 to 500 characters, shown to the account that held it.
                          """
            ]
          result:
            http: "200 OK"
            properties: [
              key: "released"
              type: "`true`"
              description: """
                          The id was released.
                          """
            ,
              key: "notified"
              type: "`mail`|`audit-only`"
              description: """
                          `mail` when the mail to the account was sent, `audit-only` when only its audit trail records the release: mail not configured, the notice switched off, the account has no email address, or the send failed.
                          """
            ]
          errors: [
            key: "invalid-parameters-format"
            http: "400"
            description: """
                        A parameter is missing or malformed, or the namespace does not exist (the value is never echoed).
                        """
          ,
            key: "unknown-resource"
            http: "404"
            description: """
                        No account holds this id. Also when this core's index names it for an account that no longer exists here: the reconcile (`bin/reconcile-user-cores.js --ext-ids`) cleans such a row.
                        """
          ]
          examples: [
            title: "Releasing an id"
            params:
              namespace: "clinic-ehr"
              blindedValue: "<blinded value>"
              reason: "Claimed by the wrong account; the patient will link it again."
            result:
              released: true
              notified: "mail"
          ]
        ]
      ]
    ,
      id: "service"
      title: "Service"
      description: """
                  Methods for collecting service information such as details about the platform and the API, connected apps or hostings (core server locations).
                  """
      sections: [
        id: "hostings.get"
        type: "method"
        title: "Get hostings"
        http: "GET /hostings"
        httpOnly: true
        server: "register"
        description: """
                    Get the list of all available hostings for data storage locations.
                    """
        params:
          properties: []
        result:
          http: "200 OK"
          properties: [
            key: "regions"
            type: "Object"
            description: """
                        Object containing multiple regions, containing themselves multiple zones, containing themselves multiple **hostings**.
                        You need to use the `availableCore` URL as endpoint for the [Create user API method](#create-user).
                        """
          ]
        examples: [
          title: "Fetching the hostings for a Pryv.io platform"
          params: {}
          result:
            examples.register.hostings[0]
        ]
      ,
        id: "apps.get"
        type: "method"
        title: "Get apps"
        http: "GET /apps"
        httpOnly: true
        server: "register"
        description: """
                    Retrieve the list of applications connected to the platform.
                    """
        params:
          properties: []
        result:
          http: "200 OK"
          properties: [
            key: "apps"
            type: "array"
            description: """
                        An array listing all the applications connected to the Pryv.io platform.
                        """
          ]
        examples: [
          title: "Retrieving the list of applications connected to the platform."
          params: {}
          result:
            "apps": examples.register.apps
        ]
      ,
        id: "apps.getOne"
        type: "method"
        title: "Get app"
        http: "GET /apps/{appid}"
        httpOnly: true
        server: "register"
        description: """
                    Retrieve information about a given application.
                    """
        params:
          properties: [
            key: "appid"
            type: "string"
            http:
              text: "set in request path"
            description: """
                        The id of the application to look for.
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "app"
            type: "object"
            description: """
                        An object listing information about the given application.
                        """
          ]
        examples: [
          title: "Retrieving information about a given application."
          params: {}
          result:
            "app": examples.register.apps[0]
        ]
      ]
    ,
      id: "users"
      title: "Users"
      description: """
                  Methods for managing users.
                  """
      sections: [
        id: "users.create"
        type: "method"
        title: "Create user"
        http: "POST /users"
        httpOnly: true
        server: "core"
        description: """
                    Creates a new user account. The method's parameters can be customized with the [system streams configuration](/customer-resources/system-streams/).
                    Enforces password complexity rules if enabled (set via the corresponding platform settings).

                    Before Pryv.io 1.6, this route was served by the register server on `/user`
                    """
        params:
          properties: [
            key: "appId"
            type: "string"
            description: """
                        Your app's unique identifier.
                        """
          ,
            key: "username"
            type: "string"
            description: """
                        The user's username.
                        """
          ,
            key: "password"
            type: "string"
            description: """
                        The user's password.
                        """
          ,
            key: "email"
            type: "string"
            description: """
                          The user's e-mail address, used for password retrieval.
                          """
          ,
            key: "invitationToken"
            type: "string"
            optional: true
            description: """
                          An invitation token, necessary when users registration is limited to a specific set of users.
                          Platform administrators may limit users registration by configuring a list of authorized invitation tokens.
                          If this is not the case, users registration is open to everyone and this parameter can be omitted.

                          """
          ,
            key: "language"
            type: "string"
            optional: true
            description: """
                          The user's preferred language as a 2-letter ISO language code.
                          """
          ,
            key: "referer"
            type: "string"
            optional: true
            description: "A referer id potentially used for analytics."
          ,
            key: "externalId"
            type: "object"
            optional: true
            description: """
                          A record id of your system to link to the new account: `{ namespace, blindedValue, mode? }`, as in the `externalId` of the [auth request](/reference/#auth-request) (see [External ids](/customer-resources/external-ids/)). An id nobody holds is linked to the new account. An id another account holds leaves the new account unlinked in `hint` mode (send the user to sign in with the account that holds it), and refuses the registration with `409 external-id-already-claimed` in `forced` mode, before anything is reserved. A malformed value or an unknown namespace refuse the registration before anything is reserved. Requires an open-pryv.io release later than 2.0.0-rc.56, and 2.0.0-rc.59 or later for the `forced` mode (an older core refuses it with `invalid-parameters-format`).
                          """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "username"
            type: "string"
            description: """
                          A confirmation of the user's username.
                          """
          ,
            key: "apiEndpoint"
            type: "string"
            description: """
                         The apiEndpoint to reach this account. It includes a personal access token.
                         """
          ,
            key: "externalIdLinked"
            type: "boolean"
            optional: true
            description: """
                         Present when the registration carried an `externalId`: `true` when the id is now linked to the new account, `false` when another account holds it or it could not be linked.
                         """
          ]
        errors: [
          key: "invalid-parameters-format"
          http: "400"
          description: """
                      The password does not match password complexity rules (if enabled), or the `externalId` is malformed or names an unknown namespace (`data.param` names the field, never the value).
                      """
        ,
          key: "external-id-already-claimed"
          http: "409"
          description: """
                      (`externalId` in `forced` mode) Another account holds the id (`data: { namespace, reason: 'value-taken' }`, never which account). Nothing is reserved: send the user to sign in with the account that holds it.
                      """
        ,
          key: "cross-core-registration-failed"
          http: "503"
          description: """
                      (Multi-core platform) The registration landed on one core for another core's hosting, and that core could not take it: it is unreachable, or it refused the forward itself. Nothing is created; retry later. A refusal of the registration by that core (e.g. `409 item-already-exists`) is answered as that core answered it. From an open-pryv.io release later than 2.0.0-rc.61 (earlier releases answer `500 unexpected-error` in these cases, and for any refusal by the other core).
                      """
        ]
        examples: [
          title: "Creating a user."
          params:
            appId: examples.register.appids[0]
            username: examples.users.two.username
            password: examples.users.two.password
            email: examples.users.two.email
            invitationToken: examples.register.invitationTokens[0]
            language: examples.register.languageCodes[0]
            referer: examples.register.referers[0]
          result:
            username: examples.users.two.username
            apiEndpoint: examples.users.two.apiEndpoint.pryvLab
        ]
      ,
        id: "username.check"
        type: "method"
        title: "Check username"
        http: "GET /{username}/check_username"
        httpOnly: true
        server: "register"
        description: """
                    For the single node mode please use [this](/reference/#check-username) API endpoint.

                    Check the availability and validity of a given username.
                    """
        params:
          properties: [
            key: "username"
            type: "string"
            http:
              text: "set in request path"
            description: """
                        The username to check.
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "reserved"
            type: "boolean"
            description: """
                        Set to `true` if the given username is already taken, `false` otherwise.
                        """
          ,
            key: "reason"
            type: "string"
            optional: true
            description: """
                        Optional indication of the reason why the username is reserved.
                        If it mentions `RESERVED_USER_NAME`, this means that the given username is part of
                        the reserved usernames list configured within the register service.
                        """
          ]
        errors: [
          key: "INVALID_USERNAME"
          http: "400"
          description: """
                      The given username is invalid because of an unrecognized format.
                      """
        ]
        examples: [
          title: "Checking availability and validity of a given username"
          params: {
            username: examples.users.two.username
          }
          result:
            reserved: false
        ,
          title: "Special case where the username is part of the reserved list."
          params: {
            username: examples.users.reserved.username
          }
          result:
            reserved: true
            reason: "RESERVED_USER_NAME"
        ]
      ,
        id: "emails.check"
        type: "method"
        title: "Check email existence"
        http: "GET /{email}/check_email"
        httpOnly: true
        server: "register"
        description: """
                    Check the existence of an account's email.
                    """
        params:
          properties: [
            key: "email"
            type: "string"
            http:
              text: "set in request path"
            description: """
                        The email address to check.
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "exists"
            type: "boolean"
            description: """
                        Set to `true` if the email address is already registered, `false` otherwise.
                        """
          ]
        errors: [
          key: "INVALID_EMAIL"
          http: "400"
          description: """
                      The email address is invalid because of an unrecognized format.
                      """
        ]
        examples: [
          title: "Checking the existence of an account's email address."
          params: {
            email: examples.users.two.email
          }
          result:
            exists: false
        ]
      ,
        id: "email.username.get"
        type: "method"
        title: "Get username from email"
        http: "GET /{email}/username"
        httpOnly: true
        server: "register"
        description: """
                    Get the username of a Pryv.io account according to the given email. This API method can be disabled in the [platform configuration](https://pryv.github.io/reference-admin/#platform-settings).

                    On multi-node platforms that store identifiers pseudonymised, a node that does not host the requested account answers with a `307` redirect to the account's home node — the home node URL is also returned in a `{ "server": "<url>" }` JSON body for clients that do not follow redirects automatically. The home node resolves and returns the username. Clients that follow redirects (including the official libraries) handle this transparently; single-node platforms answer directly without a redirect.
                    """
        params:
          properties: [
            key: "email"
            type: "string"
            http:
              text: "set in request path"
            description: """
                        The email address to look for.
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "username"
            type: "string"
            description: """
                        The username linked to the given email.
                        """
          ]
        errors: [
          key: "UNKNOWN_EMAIL"
          http: "404"
          description: """
                      The given email address is unknown (unregistered).
                      """
        ]
        examples: [
          title: "Retrieving a username from a given email."
          params: {
            email: examples.users.two.email
          }
          result:
            "username": examples.users.two.username
        ]
      ,

        id: "cores.get"
        type: "method"
        title: "Get core"
        http: "GET /cores"
        httpOnly: true
        server: "register"
        description: """
                    Get the core of a Pryv.io account according to the given username or email. You must provide **only** one of them.
                    """
        params:
          properties: [
            key: "username"
            type: "string"
            description: """
                        The username to look for.
                        """
          ,
            key: "email"
            type: "string"
            description: """
                        The email to look for. When using the email parameter, you will always get a core returned, even if no such email is registered.
                        This is meant to prevent email discovery.
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "core"
            type: "object"
            description: "The core by username"
          ]
        examples: [
          title: "Retrieving the core URL for a given username."
          params: {
            username: "trench"
          }
          result:
            core:
              url: "https://co1.pryv.me/"
        ,
          title: "Retrieving the core URL for a non-existing email."
          params: {
            email: "adam-gibson@replacement.tech"
          }
          result:
            core:
              url: "https://co3.pryv.me/"
        ]
      ,

        id: "extIdCores.get"
        type: "method"
        title: "Get core holding an external id"
        http: "POST /ext-id/cores"
        httpOnly: true
        server: "register"
        description: """
                    Get the base URL of the core holding an [external id](/customer-resources/external-ids/): the core of the one account that claimed it. It never tells which account. No authentication. On a DNS-less setup the route is `https://{hostname}/reg/ext-id/cores`.

                    It is a `POST` so the blinded value never appears in a URL. An unknown namespace and an id nobody claimed give the same answer, `404 unknown-resource`.

                    Every lookup counts toward a budget per client address (an IPv4 address, or the /64 of an IPv6 address), kept by each core and shared with the refused claims of [claim an external id](/reference/#claim-an-external-id): at most 10 in a one-minute window opened by the first. Past it the lookup is refused with `429 too-many-attempts` until the window ends. The address is read through `http.trustedProxies`.
                    """
        params:
          properties: [
            key: "namespace"
            type: "string"
            description: """
                        The namespace of the id.
                        """
          ,
            key: "blindedValue"
            type: "string"
            description: """
                        The blinded value of the record id, `HMAC(K_namespace, recordId)`: base64url without padding, 16 to 64 bytes once decoded.
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "server"
            type: "string"
            description: """
                        The base URL of the core holding the id.
                        """
          ]
        errors: [
          key: "invalid-parameters-format"
          http: "400"
          description: """
                      The blinded value is malformed. The error never echoes the value.
                      """
        ,
          key: "unknown-resource"
          http: "404"
          description: """
                      The namespace is unknown, or no account holds the id.
                      """
        ,
          key: "too-many-attempts"
          http: "429"
          description: """
                      More than 10 lookups or refused claims within one minute from this client address on this core. The id is not looked up. Retry after the `Retry-After` header (seconds), also given as `error.data.retryAfterSeconds`.
                      """
        ]
        examples: [
          title: "Finding the core that holds an external id."
          params:
            namespace: "clinic-ehr"
            blindedValue: "5axJiZtfRrrFmLoDoJc9LWUadGJBz-ByjoE8SAAHBz4"
          result:
            server: "https://co1.pryv.me/"
        ]
      ,

        id: "users.delete"
        type: "method"
        title: "Delete user"
        http: "DELETE /users/{username}"
        httpOnly: true
        trustedOnly: true
        server: "core"
        description: """
                    Deletes a user account. This method must be enabled in the platform configuration. You should fetch the URL of the core where the user data is stored using the [Get core](#get-core) method.
                    - When performed by the account owner, this method requires a personal token.
                    - For platform administrators, please refer to [its Delete user method](/reference-admin/#delete-user).
                    - For Open Pryv.io users, this method requires to provide the [auth:adminAccessKey](https://github.com/pryv/open-pryv.io#config) as `Authorization` header.
                    """
        params:
          properties: [
            key: "username"
            type: "string"
            http:
              text: "set in request path"
            description: """
                          The username of the account to delete.
                          """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "userDeletion"
            type: "object"
            description: """
                          The deleted user.
                          """
          ]
        examples: [
          title: "Deleting a user."
          params:
            username: "mark-kaminski"
          result:
            userDeletion:
              username: "mark-kaminski"
        ]

      ,

        id: "access.create"
        type: "method"
        title: "Create access request"
        http: "POST /reg/access"
        httpOnly: true
        server: "register"
        description: """
                    Creates a new access authorization request. The requesting app calls this method, then polls
                    the returned URL until the user accepts or refuses the request.
                    This implements the Pryv.io OAuth-like authorization flow.
                    """
        params:
          properties: [
            key: "requestingAppId"
            type: "string"
            description: """
                        The id of the app requesting access.
                        """
          ,
            key: "requestedPermissions"
            type: "array of permission objects"
            description: """
                        The permissions requested by the app.
                        """
          ,
            key: "returnURL"
            type: "string"
            optional: true
            description: """
                        An optional URL to redirect the user to after accepting or refusing.
                        """
          ,
            key: "clientData"
            type: "object"
            optional: true
            description: """
                        Optional metadata the requesting app wants to attach to the request.
                        """
          ,
            key: "credentialHandoff"
            type: "string"
            optional: true
            description: """
                        Ask that the token be delivered through a one-time shared secret rather than returned in the poll. The only accepted value is `shared-secret`; anything else is a `400 invalid-parameters`. When the server understands it, the `ACCEPTED` poll carries a `handoff` key instead of `token` (see [Poll access request](#poll-access-request)) and the 201 echoes `credentialHandoff` back. An older core drops the field and echoes nothing, so the request degrades to inline `token` delivery.
                        """
          ,
            key: "cmcInvites"
            type: "array of invite objects"
            optional: true
            description: """
                        [Cross-account messaging](/guides/cross-account-messaging/#consent-invites-in-the-authorisation-request) invites the user should answer on the auth page, next to the app access: 1 to 8 entries `{ capabilityUrl, mandatory?, for?, accessName? }`, with no other key. `capabilityUrl` is an absolute `http` or `https` URL of at most 2048 characters; `mandatory` a boolean (default `false`); `for` `self` (default) or `target` (the account the access is granted for, when the user acts for an account they manage); `accessName` the name of the data grant minted by accepting the invite, 1 to 256 characters, stored as sent (the server does not use it; the auth page passes it to the accept). A malformed list is a `400 invalid-parameters`. The request's size ceiling (`access:maxRequestBytes`) still applies. The 201 echoes the normalised list only when the server understood it; an older core drops the field. Requires open-pryv.io 2.0.0-rc.32 or later; `accessName` requires open-pryv.io 2.0.0-rc.36 or later, and an older core refuses an entry carrying it with `400 invalid-parameters`.
                        """
          ,
            key: "actAs"
            type: "string"
            optional: true
            description: """
                        Who the access may be granted for, when the user controls other accounts through [account delegation](/guides/account-delegation/#granting-an-app-access-for-a-controlled-account): `allow` (the default behaviour when omitted), `deny` (the signed-in account only) or a username to preselect. Any other value is a `400 invalid-parameters`.
                        """
          ,
            key: "actAsManagedOnly"
            type: "boolean"
            optional: true
            description: """
                        `true` when the access must be granted for an account the user manages, never for the signed-in account. Requires `actAs` (`allow` or a username): `true` without `actAs` or with `actAs: 'deny'`, or a value that is not a boolean, is a `400 invalid-parameters`; `false` is the same as not sending it. A hint the auth page enforces, not the server: the reference auth page lists only managed accounts and, when none can be used, refuses with `reasonId: 'MANAGED_ACCOUNT_UNAVAILABLE'`. The 201 echoes `actAsManagedOnly: true` only when the server understood it; an older core drops the field. Requires open-pryv.io 2.0.0-rc.36 or later.
                        """
          ]
        result:
          http: "201 Created"
          properties: [
            key: "status"
            type: "string"
            description: """
                        The current status of the request (`NEED_SIGNIN`).
                        """
          ,
            key: "key"
            type: "string"
            description: """
                        The polling key. Use it to poll and to build the auth URL.
                        """
          ,
            key: "poll"
            type: "string"
            description: """
                        The full URL to poll for status updates.
                        """
          ,
            key: "poll_rate_ms"
            type: "number"
            description: """
                        The recommended polling interval in milliseconds.
                        """
          ,
            key: "credentialHandoff"
            type: "string"
            optional: true
            description: """
                        Echoed as `shared-secret` only when the request carried it and the server understood it. Its absence tells the app it will receive inline `token` delivery.
                        """
          ,
            key: "cmcInvites"
            type: "array of invite objects"
            optional: true
            description: """
                        Echoed, normalised (`mandatory` and `for` filled in, `accessName` only on an entry that carried it), only when the request carried `cmcInvites` and the server understood them. The `NEED_SIGNIN` poll carries the same list for the auth page.
                        """
          ,
            key: "actAsManagedOnly"
            type: "`true`"
            optional: true
            description: """
                        Echoed as `true` only when the request carried `actAsManagedOnly: true` and the server understood it. The `NEED_SIGNIN` poll carries it too, for the auth page.
                        """
          ]

      ,

        id: "access.poll"
        type: "method"
        title: "Poll access request"
        http: "GET /reg/access/{key}"
        httpOnly: true
        server: "register"
        description: """
                    Polls the status of a pending access request. The requesting app calls this periodically
                    until it receives `ACCEPTED`, `REFUSED`, or `ERROR`.

                    Possible statuses: `NEED_SIGNIN` (waiting), `ACCEPTED` (token issued), `REFUSED`, `ERROR`.
                    """
        params:
          properties: [
            key: "key"
            type: "string"
            http:
              text: "set in request path"
            description: """
                        The polling key returned by [Create access request](#create-access-request).
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "status"
            type: "string"
            description: """
                        The current status.
                        """
          ,
            key: "username"
            type: "string"
            description: """
                        (When `ACCEPTED`) The username that granted the access.
                        """
          ,
            key: "token"
            type: "string"
            description: """
                        (When `ACCEPTED`, inline delivery) The personal or app token. Absent when the request asked for `credentialHandoff: 'shared-secret'` and the server delivers a `handoff` instead.
                        """
          ,
            key: "apiEndpoint"
            type: "string"
            description: """
                        (When `ACCEPTED`) The API endpoint for subsequent requests. Token-less when a `handoff` is delivered.
                        """
          ,
            key: "handoff"
            type: "object"
            optional: true
            description: """
                        (When `ACCEPTED` and the request asked for `credentialHandoff`) A one-time credential hand-off in place of `token`, shaped `{ "type": "shared-secret", "key": "<eventId>.<random>" }`. Retrieve the credential exactly once with `POST {apiEndpoint}shared-secrets/retrieve` (body `{ "key": "<key>" }`, unauthenticated), which returns `{ "secret": { "username", "token", "apiEndpoint" } }`; a second retrieve answers `403 shared-secret-unavailable`. See [Shared secrets](#shared-secrets).
                        """
          ,
            key: "cmcInvites"
            type: "array"
            optional: true
            description: """
                        (When `NEED_SIGNIN`) The request's normalised `cmcInvites`, with `accessName` on the entries that carried it, for the auth page. (When `ACCEPTED`) The outcome the auth page posted for each invite, in the request's order: `{ acceptEventId, dataGrantAccessId?, acceptedFor?: 'self' }`, `{ declined: true }` or `{ reason }`, carried with inline and hand-off delivery alike. The outcomes are a hint from the auth page, not verified by the server; each requester learns the truth from its own inbox. Absent when the request carried no invites or the page posted no outcomes.
                        """
          ,
            key: "actAsManagedOnly"
            type: "`true`"
            optional: true
            description: """
                        (When `NEED_SIGNIN`) `true` when the request asked that the access be granted for an account the user manages only. Absent otherwise, and never on `ACCEPTED`.
                        """
          ,
            key: "reasonId"
            type: "string"
            optional: true
            description: """
                        (When `REFUSED` or `ERROR`) The reason code the auth page posted. `REFUSED_MANDATORY_CONSENT` means the user declined a mandatory invite of `cmcInvites`; `MANDATORY_CONSENT_FAILED` that a mandatory invite could not be accepted (`message` names the invite and the error id); `MANAGED_ACCOUNT_UNAVAILABLE` that the request asked for `actAsManagedOnly` and the user had no managed account to grant the access for (`message` names the cause).
                        """
          ]

      ,

        id: "access.update"
        type: "method"
        title: "Accept/Refuse access request"
        http: "POST /reg/access/{key}"
        httpOnly: true
        server: "register"
        description: """
                    Updates the state of an access request. Called by the auth page after the user has
                    signed in and accepted or refused the permissions.

                    On a request whose `externalId` is in `forced` mode, `ACCEPTED` is checked before anything is written: the token must be an app access of `username` and that account must hold the id (see the `externalId` of the [auth request](/reference/#auth-request)). The token is posted inline; a `handoff` or `externalIdDeclined` field is refused with `invalid-parameters` (HTTP 400). A refused acceptance leaves the request `NEED_SIGNIN`.
                    """
        params:
          properties: [
            key: "key"
            type: "string"
            http:
              text: "set in request path"
            description: """
                        The polling key.
                        """
          ,
            key: "status"
            type: "string"
            description: """
                        The new status: `ACCEPTED`, `REFUSED` or `ERROR`. Any other value is refused with `invalid-parameters` (HTTP 400); `REDIRECTED` is no longer accepted since open-pryv.io 2.0.0-rc.36.
                        """
          ,
            key: "username"
            type: "string"
            description: """
                        (Required when `ACCEPTED`) The username granting the access.
                        """
          ,
            key: "token"
            type: "string"
            description: """
                        (Required when `ACCEPTED`) The token for the access.
                        """
          ,
            key: "cmcInvites"
            type: "array of outcome objects"
            optional: true
            description: """
                        (Only with `ACCEPTED`, only on a request that carried `cmcInvites`) One outcome per invite of the request, in its order: `{ acceptEventId, dataGrantAccessId?, acceptedFor?: 'self' }`, `{ declined: true }` or `{ reason }` (ids and reasons at most 256 characters). A list of the wrong length or shape, or one sent with another status or on a request without invites, is a `400 invalid-parameters` and the request is left unchanged. Served back as `cmcInvites` in the `ACCEPTED` bodies.
                        """
          ,
            key: "reasonId"
            type: "string"
            optional: true
            description: """
                        (With `REFUSED` or `ERROR`) A reason code, stored as given. The reference auth page posts `REFUSED_MANDATORY_CONSENT` when the user declined a mandatory invite of `cmcInvites`, before it writes anything, `MANDATORY_CONSENT_FAILED` when a mandatory invite could not be accepted, with a `message` naming the invite and the platform's error id, and `MANAGED_ACCOUNT_UNAVAILABLE` when the request carried `actAsManagedOnly` and no account the user manages could be used, with a `message` naming the cause.
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "status"
            type: "string"
            description: """
                        The updated status.
                        """
          ]
        errors: [
          key: "external-id-mismatch"
          http: "400"
          description: """
                      (`forced` mode) The token is not an app access of `username` (`data.reason: 'token-invalid'`), or the account does not hold the id (`data.reason: 'not-holder'`, which counts in the [external id lookup](#get-core-holding-an-external-id) budget).
                      """
        ,
          key: "external-id-check-unavailable"
          http: "503"
          description: """
                      (`forced` mode) The holder check could not run (`data.reason` says why). Retry.
                      """
        ,
          key: "too-many-attempts"
          http: "429"
          description: """
                      (`forced` mode) The client address is over the external id budget. The request is left unchanged.
                      """
        ]

      ,

        id: "invitationtoken.check"
        type: "method"
        title: "Check invitation token"
        http: "POST /access/invitationtoken/check"
        httpOnly: true
        server: "register"
        description: """
                    Checks whether an invitation token is valid. Returns plain text `true` or `false`.
                    Used when user registration is limited to holders of valid invitation tokens.

                    Every check counts toward a budget per client address (an IPv4 address, or the /64 of an IPv6 address), kept by each core: at most 10 checks in a one-minute window opened by the first. Past it the check is refused with `429 too-many-attempts` until the window ends. The address is read through `http.trustedProxies`.
                    """
        params:
          properties: [
            key: "invitationtoken"
            type: "string"
            description: """
                        The invitation token to verify.
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: ""
            type: "string"
            description: """
                        Plain text: `true` if valid, `false` otherwise.
                        """
          ]
        errors: [
          key: "too-many-attempts"
          http: "429"
          description: """
                      More than 10 checks within one minute from this client address (an IPv6 address counts toward its /64) on this core. The token is not checked. Retry after the `Retry-After` header (seconds), also given as `error.data.retryAfterSeconds`.
                      """
        ]

      ,

        id: "invitations.list"
        type: "method"
        title: "List invitation tokens"
        http: "GET /reg/admin/invitations"
        httpOnly: true
        adminOnly: true
        server: "register"
        description: """
                    Lists all invitation tokens configured on the platform. Requires admin authorization.
                    """
        result:
          http: "200 OK"
          properties: [
            key: "invitations"
            type: "array"
            description: """
                        The list of invitation tokens.
                        """
          ]

      ,

        id: "invitations.generate"
        type: "method"
        title: "Generate invitation tokens"
        http: "GET /reg/admin/invitations/post"
        httpOnly: true
        adminOnly: true
        server: "register"
        description: """
                    Generates new invitation tokens. Requires admin authorization.
                    """
        params:
          properties: [
            key: "count"
            type: "number"
            http:
              text: "query parameter"
            description: """
                        Number of tokens to generate (default: 1).
                        """
          ,
            key: "message"
            type: "string"
            optional: true
            http:
              text: "query parameter"
            description: """
                        Optional description for the generated tokens.
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "data"
            type: "object"
            description: """
                        The generated invitation tokens.
                        """
          ]

      ,

        id: "dns.records"
        type: "method"
        title: "Update DNS records"
        http: "POST /reg/records"
        httpOnly: true
        adminOnly: true
        server: "register"
        description: """
                    Admin endpoint for updating runtime DNS entries (e.g. ACME challenge records for SSL
                    certificate provisioning). Records are persisted to PlatformDB and propagated to all
                    cores in a multi-core deployment. Requires admin authorization.

                    DNS records are answered before usernames, so a new record under the name of an
                    existing account is refused with `409 item-already-exists` (an existing record can
                    still be updated), and a record name cannot be registered as a username.
                    """
        params:
          properties: [
            key: "subdomain"
            type: "string"
            description: """
                        The subdomain to set records for.
                        """
          ,
            key: "records"
            type: "object"
            description: """
                        The DNS records to set (e.g. `{ "TXT": "challenge-value" }`).
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "subdomain"
            type: "string"
            description: """
                        The subdomain.
                        """
          ,
            key: "status"
            type: "string"
            description: """
                        `ok` on success.
                        """
          ]
      ]
    ,

    ]
  ]
