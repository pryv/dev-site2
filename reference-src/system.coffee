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
                  This key is defined within the platform configuration: `REGISTER_ADMIN_KEY`.
                  """
      sections: [
        id: "users.get"
        type: "method"
        title: "Get users"
        http: "GET /admin/users"
        httpOnly: true
        server: "register"
        description: """
                    Get the list of all users registered on the platform.
                    """
        params:
          properties: [
            key: "toHTML"
            type: "boolean"
            optional: true
            description: """
                        If `true`, format the resulting users list as HTML tables.
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
          title: "Fetching the users list for a Pryv.io platform"
          params: {}
          result:
            users: [
              examples.users.three,
              examples.users.four
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
          ]
        errors: [
          key: "invalid-parameters-format"
          http: "400"
          description: """
                      The password does not match password complexity rules (if enabled).
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
                        (When `ACCEPTED`) The personal or app token.
                        """
          ,
            key: "apiEndpoint"
            type: "string"
            description: """
                        (When `ACCEPTED`) The API endpoint for subsequent requests.
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
                        The new status: `ACCEPTED`, `REFUSED`, `ERROR`, or `REDIRECTED`.
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
