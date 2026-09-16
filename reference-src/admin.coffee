examples = require("./examples")
helpers = require("./helpers")
_ = require("lodash")

# For use within the data declaration here; external callers use `getDocId` (which checks validity)
_getDocId = (sectionId, subsectionId, methodId) ->
  return helpers.getDocId("admin", sectionId, subsectionId, methodId)

module.exports = exports =
  id: "admin"
  title: "Admin API"
  sections: [
    id: "basics"
    title: "Basics"
    description: """
                 This document describes Pryv.io's **administration** API, allowing to configure the platform parameters and manage platform users.
                 """
    sections: [
      id: "admin-service"
      title: "Administration service"
      description: """
                   The administration service has its own API and authentication mechanism.
                   """
    ,
      id: "authorization"
      title: "Authorization"
      description: """
                   All requests for retrieving and manipulating admin data must carry a valid JSON web token that is obtained at login.

                   It must be assigned to the `authorization` header.
                   """
    ]
  ,
    id: "api-methods"
    title: "API methods"
    description: """
              The methods are called via HTTPS on the administration server: `https://lead.{domain}`.
              """
    sections: [
      id: "auth"
      title: "Authentication"
      description: """
                  Methods for authenticating admin users.
                  """
      sections: [
        id: "auth.login"
        type: "method"
        title: "Login user"
        http: "POST /auth/login"
        httpOnly: true
        server: "admin"
        description: """
                    Authenticates the user against the provided credentials.
                    """
        params:
          properties: [
            key: "username"
            type: "string"
            description: """
                        The user's username
                        """
          ,
            key: "password"
            type: "string"
            description: """
                        The user's password
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "token"
            type: "string"
            description: """
                        JSON web token to use for further API calls.
                        """
          ]
        examples: [
          title: "Authenticating admin user"
          params: {
            username: "quaid",
            password: "my-secret-password"
          }
          result:
            token: "eyJ1c2VybmFtZSI6ImlsaWEiLCJwZXJtaXNzaW9ucyI6eyJ1c2VycyI6WyJyZWFkIiwiY3JlYXRlIiwiZGVsZXRlIiwicmVzZXRQYXNzd29yZCIsImNoYW5nZVBlcm1pc3Npb25zIl0sInNldHRpbmdzIjpbInJlYWQiLCJ1cGRhdGUiXX0sImlhdCI6MTU5OTIyNDM4MywiZXhwIjoxNTk5MzEwNzgzfQ"
        ]
      ,
        id: "auth.logout"
        type: "method"
        title: "Logout user"
        http: "POST /auth/logout"
        httpOnly: true
        server: "admin"
        description: """
                     Terminates a session by invalidating its JSON web token (the user will have to login again). Simply provide the JSON web token in own of the [the supported ways](/reference-admin/#authorization), no request body is required.
                    """
        result:
          http: "200 OK"
        examples: [
          params: {}
          result: {}
        ]
      ]

    ,

      id: "admin-users"
      title: "Admin users"
      description: """
                   Methods for managing admin users.
                   """
      sections: [
        id: "adminUsers.get"
        type: "method"
        title: "Retrieve admin users information"
        http: "GET /users"
        httpOnly: true
        server: "admin"
        description: """
                     Retrieves the admin users information.
                     """
        params: {}
        result:
          http: "200 OK"
          properties: [
            key: "users"
            type: "Array of [admin users](#admin-user)"
            description: """
                         The admin users information.
                         """
          ]
        examples: [
          title: "Fetching admin users."
          params: {}
          result:
            users: [
              examples.adminUsers.admin,
              examples.adminUsers.harrytasker,
            ]
        ]

      ,
        id: "adminUsers.getOne"
        type: "method"
        title: "Retrieve admin user information"
        http: "GET /users/{username}"
        httpOnly: true
        server: "admin"
        description: """
                     Retrieves the admin user's information.
                     """
        params:
          properties: [
            key: "username"
            type: "string"
            http:
              text: "set in request path"
            description: """
                         The username of the admin user.
                         """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "user"
            type: "[admin user](#admin-user)"
            description: """
                        The admin user's information.
                        """
          ]
        examples: [
          title: "Fetching one admin user's information."
          params:
            username: 'harrytasker'
          result:
            user:
              examples.adminUsers.harrytasker
        ]
      ,

        id: "adminUsers.create"
        type: "method"
        title: "Create an admin user"
        http: "POST /users"
        httpOnly: true
        server: "admin"
        description: """
                     Creates an admin user.
                     """
        params:
          properties: [
            key: "username"
            type: "string"
            description: """
                         The username of the admin user.
                         """
          ,
            key: "password"
            type: "string"
            description: """
                         The password of the admin user.
                         """
          ,
            key: "permissions"
            type: "string"
            description: """
                         The [permissions of the admin user](#admin-permissions).
                         """
          ,
          ]
        result:
          http: "200 OK"
          properties: [
            key: "user"
            type: "[admin user](#admin-user)"
            description: """
                        The created admin user's information.
                        """
          ]
        examples: [
          title: "Creating an admin user."
          params:
            examples.adminUsers.harrytasker
          result:
            user:
              examples.adminUsers.harrytasker
        ]

      ,

        id: "adminUsers.updatePermissions"
        type: "method"
        title: "Update an admin user's permissions"
        http: "PUT /users/{username}/permissions"
        httpOnly: true
        server: "admin"
        description: """
                     Updates an admin user's permissions.
                     """
        params:
          properties: [
            key: "permissions"
            type: "[admin permissions](#admin-permissions)"
            description: """
                         The permissions of the admin user.
                         """
          ,
          ]
        result:
          http: "200 OK"
          properties: [
            key: "user"
            type: "[admin user](#admin-user)"
            description: """
                        The updated admin user's information.
                        """
          ]
        examples: [
          title: "Updating an admin user's permissions."
          params:
            permissions: examples.adminUsers.harrytasker.permissions
          result:
            user:
              examples.adminUsers.harrytasker
        ]

      ,

        id: "adminUsers.resetPassword"
        type: "method"
        title: "Reset an admin user's password"
        http: "POST /users/{username}/reset-password"
        httpOnly: true
        server: "admin"
        description: """
                     Resets an admin user's password.
                     """
        params:
          properties: [
            key: "username"
            type: "string"
            http:
              text: "set in request path"
            description: """
                         The username of the admin user for whom to reset the password.
                         """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "password"
            type: "string"
            description: """
                        The admin user's new password.
                        """
          ]
        examples: [
          title: "Resetting an admin user's password."
          params:
            username: "harrytasker"
          result:
            password: "d89786faffda5c9"
        ]

      ,

        id: "adminUsers.delete"
        type: "method"
        title: "Delete admin user"
        http: "DELETE /users/{username}"
        httpOnly: true
        server: "admin"
        description: """
                    Delete admin account.
                    """
        params:
          properties: [
            key: "username"
            type: "string"
            http:
              text: "set in request path"
            description: """
                         The username of the admin user to delete.
                         """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "username"
            type: "string"
            description: """
                         The username of the deleted platform user.
                         """
          ]
        examples: [
          title: "Deleting an admin user"
          params:
            username: 'harrytasker'
          result:
            username: 'harrytasker'
        ]
      ]

    ,
      id: "platform-settings"
      title: "Platform settings"
      description: """
                  Methods for managing platform settings.
                  """
      sections: [
        id: "settings.get"
        type: "method"
        title: "Retrieve platform settings"
        http: "GET /admin/settings"
        httpOnly: true
        server: "admin"
        description: """
                     Retrieves the platform settings.
                     """
        result:
          http: "200 OK"
          properties: [
            key: "settings"
            type: "object"
            description: """
                         The platform settings.
                         """
          ]
        examples: [
          title: "Fetching the platform settings. The result hereafter only display a small part of the settings."
          params: {}
          result:
            settings:
              API_SETTINGS:
                name: "API settings"
                settings:
                  EVENT_TYPES_URL:
                    value: "https://my-service/event-types/flat.json"
                    description: "URL of the file listing the validated Event types. See: https://pryv.github.io/faq-api/#event-types"
                  TRUSTED_APPS:
                    value: "*@https://*.DOMAIN*, *@https://pryv.github.io*, *@https://*.rec.la*",
                    description: "Web pages authorized to run login API call.  See https://pryv.github.io/reference-full/#trusted-apps-verification.  You can remove the ones not related to your platform if you are not using Pryv's default apps The format is comma-separated list of {trusted-app-id}@{origin} pairs. Origins and appIds accept '*' wildcards, but never use wildcard appIds in production. Example: *@https://*.DOMAIN*, *@https://pryv.github.io*, *@https://*.rec.la*"
        ]
      ,

        id: "settings.update"
        type: "method"
        title: "Update platform settings"
        http: "PUT /admin/settings"
        httpOnly: true
        server: "admin"
        description: """
                     Updates the platform settings and saves them.
                     """
        params:
          properties: [
            key: "update"
            type: "object"
            http:
              text: "request body"
            description: """
                         New values for the platform settings.
                         """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "settings"
            type: "object"
            description: """
                        The updated platform settings.
                        """
          ],
        errors: [
          key: "invalid-input"
          http: "400"
          description: """
                      The configuration format is invalid.
                      """
        ],
        examples: [
          title: "Updating the [event types](/event-types/) URL. The result hereafter only highlights the modified setting."
          params:
            API_SETTINGS:
              settings:
                EVENT_TYPES_URL:
                  value: "https://my-service/event-types/flat.json"
          result:
            settings:
              API_SETTINGS:
                name: "API settings"
                settings:
                  EVENT_TYPES_URL:
                    value: "https://my-service/event-types/flat.json"
                    description: "URL of the file listing the validated Event types. See: https://pryv.github.io/faq-api/#event-types"
        ]
      ,
        id: "settings.notify"
        type: "method"
        title: "Apply settings changes"
        http: "POST /admin/notify"
        httpOnly: true
        server: "admin"
        description: """
                     Reboots desired services with latest platform settings.
                     """
        params:
          properties: [
            key: "services"
            optional: true
            type: "array of strings"
            description: """
                        The Pryv.io services to reboot. If empty, reboots all Pryv.io services. See your configuration's docker-compose file for the list of services.
                        """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "successes"
            type: "array of machines"
            description: """
                        Machines successfully updated.
                        """
            properties: [
              key: "url"
              type: "string"
              description: """
                          The url of the machine.
                          """
            ,
              key: "role"
              type: "string"
              description: """
                          The role of the machine (core, static, reg).
                          """
            ]
          ,
            key: "failures"
            type: "array of machines"
            description: """
                        Machines failed to update.
                        """
            properties: [
              key: "url"
              type: "string"
              description: """
                          The url of the machine.
                          """
            ,
              key: "role"
              type: "string"
              description: """
                          The role of the machine (core, static, reg).
                          """
            ,
              key: "error"
              type: "object"
              description: """
                          The error information.
                          """
            ]
          ]
        examples: [
          title: "Rebooting the DNS service with the latest settings."
          params:
            services: [
              "dns"
            ]
          result:
            successes: [
              url: "https://co1.pryv.li"
              role: "core"
            ,
              url: "config-follower:6000"
              role: "reg-master"
            ,
              url: "https://sw.pryv.li"
              role: "static"
            ]
            failures: []
        ]
      ,
        id: "migrations.get"
        type: "method"
        title: "Retrieve platform migrations"
        http: "GET /admin/migrations"
        httpOnly: true
        server: "admin"
        description: """
                     Retrieves the available platform settings migrations. To apply them use [Apply configuration migrations](#apply-configuration-migrations).
                     """
        result:
          http: "200 OK"
          properties: [
            key: "migrations"
            type: "array of migrations"
            description: """
                         Available migrations.
                         """
            properties: [
              key: "versionsFrom"
              type: "array of versions"
              description: """
                           The list of versions it upgrades from.
                           """
            ,
              key: "versionTo"
              type: "string"
              description: """
                           The version it upgrades to.
                           """
            ]
          ]
        examples: [
          title: "Fetching available migrations for platform version 1.6.17"
          params: {}
          result:
            migrations: [
              versionsFrom: ['1.6.15', '1.6.16', '1.6.17', '1.6.18', '1.6.19', '1.6.20']
              versionTo: '1.6.21'
            ,
              versionsFrom: ['1.6.21']
              versionTo: '1.6.22'
            ,
              versionsFrom: ['1.6.22']
              versionTo: '1.6.23'
            ,
              versionsFrom: ['1.6.23']
              versionTo: '1.7.0'
          ]
        ]
      ,
        id: "migrations.apply"
        type: "method"
        title: "Apply configuration migrations"
        http: "POST /admin/migrations/apply"
        httpOnly: true
        server: "admin"
        description: """
                     Apply the available platform configuration migrations. This will upgrade your platform.yml file to the latest available version. Use [Retrieve platform migrations](#retrieve-platform-migrations) to see available migrations.
                     """
        result:
          http: "200 OK"
          properties: [
            key: "migrations"
            type: "array of migrations"
            description: """
                         Available migrations.
                         """
            properties: [
              key: "versionsFrom"
              type: "array of versions"
              description: """
                           The list of versions it upgrades from.
                           """
            ,
              key: "versionTo"
              type: "string"
              description: """
                           The version it upgrades to.
                           """
            ]
          ]
        examples: [
          title: "Applying available migrations from platform version 1.6.17 to 1.7.0"
          params: {}
          result:
            migrations: [
              versionsFrom: ['1.6.15', '1.6.16', '1.6.17', '1.6.18', '1.6.19', '1.6.20']
              versionTo: '1.6.21'
            ,
              versionsFrom: ['1.6.21']
              versionTo: '1.6.22'
            ,
              versionsFrom: ['1.6.22']
              versionTo: '1.6.23'
            ,
              versionsFrom: ['1.6.23']
              versionTo: '1.7.0'
          ]
        ]
      ]

    ,

      id: "platform-users"
      title: "Platform users"
      description: """
                   Methods for managing platform users.
                   """
      sections: [
        id: "platformUsers.getOne"
        type: "method"
        title: "Retrieve platform user information"
        http: "GET /platform-users/{username}"
        httpOnly: true
        server: "admin"
        description: """
                     Retrieves the platform user's information.
                     """
        params:
          properties: [
            key: "username"
            type: "string"
            http:
              text: "set in request path"
            description: """
                         The username of the platform user.
                         """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "user"
            type: "[platform user](#platform-user)"
            description: """
                        The platform user's information.
                        """
          ]
        examples: [
          title: "Fetching the platform settings. The result hereafter only display a small part of the settings."
          params: {}
          result:
            user:
              username: "aiuwvd981b298dn8",
              email: "jericho@pryv.io",
              language: "en",
              invitationToken: "undefined",
              referer: "null",
              id: "ck6j759f000011ps2octzo1ds",
              registeredTimestamp: "1581504836193",
              server: "co1.pryv.li",
              registeredDate: "Wed, 12 Feb 2020 10:53:56 GMT"
        ]

      ,

        id: "platformUsers.delete"
        type: "method"
        title: "Delete user"
        http: "DELETE /platform-users/{username}"
        httpOnly: true
        server: "admin"
        description: """
                    Delete user account from the Pryv.io platform. **This deletion is final**.
                    """
        params:
          properties: [
            key: "username"
            type: "string"
            http:
              text: "set in request path"
            description: """
                         The username of the platform user to delete.
                         """
          ]
        result:
          http: "200 OK"
          properties: [
            key: "username"
            type: "string"
            description: """
                         The username of the deleted platform user.
                         """
          ]
        examples: [
          title: "Deleting a platform user"
          params:
            username: 'dutch'
          result:
            username: 'dutch'
        ]

      ,

        id: "platformUsers.deactivateMFA"
        type: "method"
        title: "Deactivate MFA for user"
        http: "DELETE /platform-users/{username}/mfa"
        httpOnly: true
        server: "admin"
        description: """
                    Deactivate MFA for a user account from the Pryv.io platform.
                    """
        params:
          properties: [
            key: "username"
            type: "string"
            http:
              text: "set in request path"
            description: """
                         The username of the platform user for whom to deactivate MFA.
                         """
          ]
        result:
          http: "204 No Content"
        examples: [
          title: "Deactivating MFA for a platform user"
          params:
            username: 'palmer'
          result: {}
        ]
      ]
    ]
  ,

    id: "data-structure"
    title: "Data structure"
    description: ""
    sections: [
      id: "admin-user"
      title: "Admin user"
      description: """
                   An admin user's information.
                   """
      properties: [
        key: "username"
        type: "string"
        description: """
                     An admin user's username.
                     """
      ,
        key: "permissions"
        type: "array of strings"
        description: """
                     An [admin user's permissions](#admin-permissions)
                     """
      ]
      examples: [
        title: "An admin user."
        content: examples.adminUsers.admin
      ]
    ,
      id: "admin-permissions"
      title: "Admin permissions"
      description: """
                   An admin user's permissions.
                   """
      properties: [
        key: "users"
        type: "array of strings"
        description: """
                     Permissions over admin users.
                     Available permissions: `read`, `create`, `delete`, `resetPassword`, `changePermissions`.
                     """
      ,
        key: "settings"
        type: "array of strings"
        description: """
                     Permissions over platform settings.
                     Available permissions: `read`, `update`.
                     """
      ,
        key: "platformUsers"
        type: "array of strings"
        description: """
                     Permissions over platform users.
                     Available permissions: `read`, `delete`.
                     """
      ]
      examples: [
        title: "An admin user."
        content: examples.adminUsers.admin
      ]
    ,
      id: "platform-user"
      title: "Platform user"
      description: """
                   A platform user's information.
                   """
      properties: [
        key: "username"
        type: "string"
        description: """
                      The platform user's username.
                      """
      ,
        key: "email"
        type: "string"
        description: """
                      The platform user's email.
                      """
      ,
        key: "language"
        type: "string"
        description: """
                      The platform user's preferred language.
                      """
      ,
        key: "invitationToken"
        type: "string"
        description: """
                      The invitation token provided at registration by the platform user.
                      """
      ,
        key: "referer"
        type: "string"
        description: """
                      The referer provided at registration by the platform user.
                      """
      ,
        key: "registeredTimestamp"
        type: "string"
        description: """
                      The UNIX timestamp of the platform user's registration.
                      """
      ,
        key: "server"
        type: "string"
        description: """
                      The URL of the core machine where the platform user's data is stored.
                      """
      ,
        key: "registeredDate"
        type: "string"
        description: """
                      The readable timestamp of the platform user's registration.
                      """
      ]
      examples: [
        title: "A platform user."
        content:
          username: "aiuwvd981b298dn8",
          email: "jericho@pryv.io",
          language: "en",
          invitationToken: "undefined",
          referer: "null",
          id: "ck6j759f000011ps2octzo1ds",
          registeredTimestamp: "1581504836193",
          server: "co1.pryv.li",
          registeredDate: "Wed, 12 Feb 2020 10:53:56 GMT"
      ]
    ]
  ]
