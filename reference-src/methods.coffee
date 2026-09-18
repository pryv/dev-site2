basics = require('./basics')
dataStructure = require('./data-structure.coffee')
examples = require("./examples")
helpers = require("./helpers")
timestamp = require("unix-timestamp")
_ = require("lodash")
generateId = require("cuid")

# For use within the data declaration here; external callers use `getDocId` (which checks validity)
_getDocId = (sectionId, methodId) ->
  return helpers.getDocId("methods", sectionId, methodId)

module.exports = exports =
  id: "methods"
  title: "API methods"
  sections: [
      id: "registration"
      title: "Registration"
      description: """
                  Method for user registration. This documentation has been moved to [System reference](/reference-system).
                  """
      sections: [
      ]
    ,
    id: "auth"
    title: "Authentication"
    trustedOnly: true
    description: """
                 Methods for trusted apps to login/logout users.
                 """
    sections: [
      id: "auth.login"
      type: "method"
      title: "Login user"
      http: "POST /auth/login"
      httpOnly: true
      description: """
                   Authenticates the user against the provided credentials, opening a personal access session. By default, the session is valid for 14 days after the last token usage. This duration is configurable in the platform parameters.
                   This is one of the only API methods that do not expect an [auth parameter](#basics-authorization).
                   This method requires that the `appId` and `Origin` (or `Referer`) header comply with the [trusted app verification](##{basics.getDocId("trusted-apps-verification")}).
                   """
      params:
        properties: [
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
          key: "appId"
          type: "string"
          description: """
                       Your app's unique identifier.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "apiEndpoint"
          type: "string"
          description: """
                       The API endpoint containing the authorization token. See [app guidelines](/guides/app-guidelines/).
                       """
        ,
          key: "token"
          type: "string"
          description: """
                       The personal access token to use for further API calls.
                       """
        ,
          key: "preferredLanguage"
          type: "string"
          description: """
                       The user's preferred language as a 2-letter ISO language code.
                       """
        ,
          key: "passwordExpires"
          type: "[timestamp](##{dataStructure.getDocId("timestamp")})"
          description: """
                       _If password maximum age rule is enabled_: The time the password will expire, according to platform setting `PASSWORD_AGE_MAX_DAYS`.
                       """
        ,
          key: "passwordCanBeChanged"
          type: "[timestamp](##{dataStructure.getDocId("timestamp")})"
          description: """
                       _If password minimum age rule is enabled_: The time after which the password can be changed, according to platform setting `PASSWORD_AGE_MIN_DAYS`. Can be in the past.
                       """
        ]
      examples: [
        params:
          username: examples.users.one.username
          password: examples.users.one.password
          appId: "my-app-id"
        result:
          apiEndpoint: helpers.getApiEndpoint(examples.accesses.personal.token, examples.users.one.username)
          token: examples.accesses.personal.token
          preferredLanguage: examples.users.one.language
      ]

    ,

      id: "auth.logout"
      type: "method"
      httpOnly: true
      title: "Logout user"
      http: "POST /auth/logout"
      description: """
                   Terminates a personal access session by invalidating its access token (the user will have to login again).
                   Simply provide the Authorization token in own of [the supported ways](/reference/#authorization), no request body is required.
                   """
      result:
        http: "200 OK"
      examples: [
        params: {}
        result: {}
      ]
    ]

  ,

    id: "mfa"
    title: "Multi-factor authentication"
    trustedOnly: true
    description: """
                 Methods for handling multi-factor authentication (MFA) on top of the usual [Login method](##{_getDocId("auth", "auth.login")}).
                 """
    sections: [
      id: "mfa.login"
      type: "method"
      title: "Login with MFA"
      httpOnly: true
      http: "POST /auth/login"
      description: """
                   Proxied [Login](##{_getDocId("auth", "auth.login")}) call that initiates MFA authentication,
                   when MFA is activated for the current user.
                   """
      params:
        description: """
                       Similar to the usual [Login](##{_getDocId("auth", "auth.login")}) parameters.
                       """
      result:
        http: "302 Found"
        properties: [
          key: "mfaToken"
          type: "string"
          description: """
                       An expiring MFA session token to be used all along the MFA flow (challenge, verification).
                       """
        ]
      examples: [
        title: "Login when MFA is activated."
        params:
          username: examples.users.one.username
          password: examples.users.one.password
          appId: "my-app-id"
        result:
          mfaToken: '215bcc40-1296-11ea-9ff7-453ff2437834'
      ]

    ,

      id: "mfa.activate"
      type: "method"
      title: "Activate MFA"
      httpOnly: true
      http: "POST /mfa/activate"
      description: """
                   Initiates the MFA activation flow for a given Pryv.io user, triggering the MFA challenge.

                   Requires a personal token as [authorization](#basics-authorization), which should be obtained during a prior [Login call](##{_getDocId("auth", "auth.login")}).
                   """
      params:
        description: """
              The parameters depend entirely on the chosen MFA method and will be forwarded as-is to the service generating the challenge. Make sure to URL encode parameters if they appear in query parameters.
              """
      result:
        http: "302 Found"
        properties: [
          key: "mfaToken"
          type: "string"
          description: """
                       An expiring MFA session token to be used all along the MFA flow (challenge, verification).
                       """
        ]
      examples: [
        title: "Initiating the MFA activation using a phone number."
        params:
          phone_number: '41791234567'
        result:
          mfaToken: '215bcc40-1296-11ea-9ff7-453ff2437834'
      ]

    ,

      id: "mfa.confirm"
      type: "method"
      title: "Confirm MFA activation"
      httpOnly: true
      http: "POST /mfa/confirm"
      description: """
                   Confirms the MFA activation by verifying the MFA challenge triggered by a prior [MFA activation call](##{_getDocId("mfa", "mfa.activate")}).

                   Requires a MFA session token as [authorization](#basics-authorization).
                   """
      params:
        description: """
              The parameters depend entirely on the chosen MFA method and will be forwarded to the service verifying the challenge.
              """
      result:
        http: "200 OK"
        properties: [
          key: "recoveryCodes"
          type: "array of strings"
          description: """
                       An array of recovery codes that can be used for the [MFA recover method](##{_getDocId("mfa", "mfa.recover")}).
                       """
        ]
      errors: [
        key: "forbidden"
        http: "403"
        description: """
                     Invalid MFA session token.
                     """
      ]
      examples: [
        title: "Finalizing the MFA activation."
        params:
          code: '1234'
        result:
          recoveryCodes: [
            'fba6e1f6-9f8f-4a0a-9c4f-8cf3458b4c55',
            'eb81be18-3168-4a44-8914-d97187df991c',
            'f7d7e863-0589-4779-8ddd-6c7e33df66af',
            'fb1d579f-2b92-42e3-82fa-8d7154c334f6',
            '52d3f019-3712-41d3-8c13-4924c3a7a703',
            'ac9de48c-a47d-46db-b276-e045ba693672',
            'de1072aa-6ed9-46a7-962c-1f8bb88ece2e',
            'cb5277cf-af86-47c3-a03e-7cc5011314ac',
            '16055dff-bc09-4262-b276-d70df82a9a2b',
            '36c7dd9b-5d23-4fb9-8504-c3e04aeb62c0'
            ]
      ]

    ,

      id: "mfa.challenge"
      type: "method"
      title: "Trigger MFA challenge"
      http: "POST /mfa/challenge"
      description: """
                   Triggers the MFA challenge, depending on the chosen MFA method (e.g. send a verification code by SMS).

                   Requires a MFA session token as [authorization](#basics-authorization).
                   """
      result:
        http: "200 OK"
        properties: [
          key: "message"
          type: "string"
          description: """
                       "Please verify the MFA challenge."
                       """
        ]
      errors: [
        key: "forbidden"
        http: "403"
        description: """
                     Invalid MFA session token.
                     """
      ]
    ,

      id: "mfa.verify"
      type: "method"
      title: "Verify MFA challenge"
      httpOnly: true
      http: "POST /mfa/verify"
      description: """
                   Verifies the MFA challenge triggered by a prior [MFA challenge call](##{_getDocId("mfa", "mfa.challenge")}).

                   Requires a MFA session token as [authorization](#basics-authorization).
                   """
      params:
        description: """
              The parameters depend entirely on the chosen MFA method and will be forwarded to the service verifying the challenge.
              """
      result:
        http: "200 OK"
        properties: [
          key: "token"
          type: "string"
          description: """
                       The personal access token to use for further API calls.
                       """
        ]
      errors: [
        key: "forbidden"
        http: "403"
        description: """
                     Invalid MFA session token.
                     """
      ]
      examples: [
        title: "Verifying the MFA challenge."
        params:
          code: '1234'
        result:
          token: examples.accesses.personal.token
      ]
    ,

      id: "mfa.deactivate"
      type: "method"
      title: "Deactivate MFA"
      httpOnly: true
      http: "POST /mfa/deactivate"
      description: """
                   Deactivate MFA for a given Pryv.io user.

                   Requires a personal token as [authorization](#basics-authorization).
                   """
      result:
        http: "200 OK"
        properties: [
          key: "message"
          type: "string"
          description: """
                       "MFA deactivated."
                       """
        ]
    ,

      id: "mfa.recover"
      type: "method"
      title: "Recover MFA"
      http: "POST /mfa/recover"
      description: """
                   Deactivate MFA for a given Pryv.io user using a MFA recovery code.

                   This is useful when [Deactivate MFA](##{_getDocId("mfa", "mfa.deactivate")}) can not be used (in case of 2nd factor loss).
                   Instead, requires a MFA recovery code (obtained when [confirming the MFA activation](##{_getDocId("mfa", "mfa.confirm")})), as well as the usual [Login](##{_getDocId("auth", "auth.login")}) parameters.
                   """
      params:
        description: """
                     Similar to the usual [Login](##{_getDocId("auth", "auth.login")}) parameters, as well as:
                     """
        properties: [
          key: "recoveryCode"
          type: "string"
          description: """
                       One MFA recovery code.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "message"
          type: "string"
          description: """
                       "MFA deactivated."
                       """
        ]
      errors: [
        key: "missing-parameter"
        http: "400"
        description: """
                     Missing parameter: recoveryCode.
                     """
      ,
        key: "invalid-parameter"
        http: "400"
        description: """
                     Invalid recovery code.
                     """
      ]
      examples: [
        title: "Deactivate MFA using a recovery code."
        params:
          recoveryCode: 'fba6e1f6-9f8f-4a0a-9c4f-8cf3458b4c55'
          username: examples.users.one.username
          password: examples.users.one.password
          appId: "my-app-id"
        result:
          message: "MFA deactivated."
      ]
    ]

  ,

    id: "callBatch"
    type: "method"
    title: "Call batch"
    http: "POST /"
    description: """
                  Sends a batch of API methods calls in one go (e.g. for syncing offline changes when resuming connectivity).
                  """
    params:
      description: """
                    Array of method call objects, each defined as follows:
                    """
      properties: [
        key: "method"
        type: "string"
        description: """
                      The method id.
                      """
      ,
        key: "params"
        type: "object or array"
        description: """
                      The call parameters as required by the method.
                      """
      ]
    result:
      http: "200 OK"
      properties: [
        key: "results"
        type: "array of call results"
        description: "The results of each method call, in order."
      ]
    examples: [
      title: "Ensure stream path for a new event. In this example the 'health' stream already exists."
      params: [
        method: "streams.create"
        params: _.pick(examples.streams.health[0], "id", "name")
      ,
        method: "streams.create"
        params: _.pick(examples.streams.healthSubstreams[1], "id", "name", "parentId")
      ,
        method: "events.create"
        params: _.pick(examples.events.heartRate, "streamIds", "type", "content")
      ]
      result:
        results: [
          error:
            id: 'item-already-exists'
            message: 'A stream with id \"health\" already exists'
            data:
              id: 'health'
        ,
          stream:
            examples.streams.healthSubstreams[1]
        ,
          event:
            examples.events.heartRate
        ]
    ]
  ,

    id: "events"
    title: "Events"
    description: """
                 Methods to retrieve and manipulate [events](##{dataStructure.getDocId("event")}).
                 """
    sections: [
      id: "events.get"
      type: "method"
      title: "Get events"
      http: "GET /events"
      description: """
                   Queries accessible events.
                   """
      params:
        properties: [
          key: "fromTime"
          type: "[timestamp](##{dataStructure.getDocId("timestamp")})"
          optional: true
          description: """
                       The start time of the timeframe you want to retrieve events for. Default is 24 hours before `toTime` if the latter is set; otherwise it is not taken into account.
                       """
        ,
          key: "toTime"
          type: "[timestamp](##{dataStructure.getDocId("timestamp")})"
          optional: true
          description: """
                       The end time of the timeframe you want to retrieve events for. Default is the current time if `fromTime` is set. We recommend to set both `fromTime` and `toTime` (for example by choosing a very small number for `fromTime` or a large one for `toTime` if you want to retrieve all events). Note: events are considered to be within a given timeframe based on their `time` and `duration`.
                       """
        ,
          key: "streams"
          type: "array of stream [identifiers](##{dataStructure.getDocId("identifier")}) or [streams query](##{dataStructure.getDocId("streams-query")})"
          optional: true
          description: """

                       **Array of streamIds:** Events assigned to any of the specified streams or their children will be returned.

                       or

                       **[Streams query](##{dataStructure.getDocId("streams-query")})**: Object used for filtering events by complex streamIds relations.

                       By default, all accessible events are returned regardless of their stream.
                       """
        ,
          key: "tags"
          type: "array of strings"
          optional: true
          description: """
                       **(DEPRECATED)** Please use [streams query](##{dataStructure.getDocId("streams-query")}) instead.

                       If set, only events assigned to any of the listed tags will be returned.
                       """
        ,
          key: "types"
          type: "array of strings"
          optional: true
          description: """
                       If set, only events of any of the listed types will be returned.
                       """
        ,
          key: "content"
          type: "array of [content query](##{dataStructure.getDocId("content-query")}) conditions"
          optional: true
          description: """
                       If set, only events whose `content` matches all the conditions will be returned. See [content query](##{dataStructure.getDocId("content-query")}) for the condition syntax, supported operators and availability. Server support is advertised by `features.contentQueries` in [service info](#service-info).
                       """
        ,
          key: "clientData"
          type: "array of [content query](##{dataStructure.getDocId("content-query")}) conditions"
          optional: true
          description: """
                       Same as `content`, applied to the events' `clientData`. Conditions from both parameters must all match.
                       """
        ,
          key: "running"
          type: "boolean"
          optional: true
          description: """
                       If `true`, only running period events will be returned.
                       """
        ,
          key: "sortAscending"
          type: "boolean"
          optional: true
          description: """
                       If `true`, events will be sorted from oldest to newest. Default: false (sort descending).
                       """
        ,
          key: "skip"
          type: "number"
          optional: true
          description: """
                       The number of items to skip in the results.
                       """
        ,
          key: "limit"
          type: "number"
          optional: true
          description: """
                       The number of items to return in the results. A default value of 20 items is used if no other range limiting parameter is specified (`fromTime`, `toTime`).
                       """
        ,
          key: "state"
          type: "`default`|`trashed`|`all`"
          optional: true
          description: """
                       Indicates what items to return depending on their state. By default, only items that are not in the trash are returned; `trashed` returns only items in the trash, while `all` return all items regardless of their state.
                       """
        ,
          key: "modifiedSince"
          type: "[timestamp](##{dataStructure.getDocId("timestamp")})"
          optional: true
          description: """
                       If specified, only events modified since that time will be returned.
                       """
        ,
          key: "includeDeletions"
          type: "boolean"
          optional: true
          description: """
                       Whether to include event deletions since `modifiedSince` for sync purposes (only applies when `modifiedSince` is set). Defaults to `false`.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "events"
          type: "array of [events](##{dataStructure.getDocId("event")})"
          description: """
                       The accessible events ordered by time (see `sortAscending` above).
                       """
        ,
          key: "eventDeletions"
          type: "array of [item deletions](##{dataStructure.getDocId("item-deletion")})"
          optional: true
          description: """
                       If requested by `includeDeletions`, the event deletions since `modifiedSince`, ordered by deletion time.
                       """
        ]
      examples: [
        title: "Fetching the last 20 events (default call)"
        params: {}
        result:
          events: [examples.events.picture, examples.events.activity, examples.events.position]
      ,
        title: "cURL with streams query for activity or nutrition that are tagged with the health stream (URL encoded)"
        params: """
                ```bash
                curl -i "https://${token}@${username}.pryv.me/events?streams=%7B%22any%22%3A%5B%22activity%22%2C%22nutrition%22%5D%2C%22all%22%3A%5B%22health%22%5D%7D"
                ```
                """
        result:
          events: [ examples.events.running, examples.events.vegetablesEaten ]
      ,
        title: "cURL for multiple streams"
        params: """
                ```bash
                curl -i "https://${token}@${username}.pryv.me/events?streams[]=diary&streams[]=weight"
                ```
                """
        result:
          events: [examples.events.picture, examples.events.note, examples.events.position, examples.events.mass]
      ,
        title: "cURL with deletions"
        params: """
                ```bash
                curl -i "https://${token}@${username}.pryv.me/events?includeDeletions=true&modifiedSince=#{timestamp.now('-24h')}""
                ```
                """
        result:
          events: [examples.events.mass]
          eventDeletions: [examples.itemDeletions[0], examples.itemDeletions[1], examples.itemDeletions[2]]
      ]

    ,

      id: "events.getOne"
      type: "method"
      title: "Get one event"
      http: "GET /events/{id}"
      description: """
                   Fetches a specific event. This request is mostly used to fetch an event's version history, allowing to review all the modifications to an event's data.
                   """
      params:
        properties: [
          key: "includeHistory"
          type: "boolean"
          optional: true
          description: """
                       If `true`, the event's history will be added to the response. Default: false (don't include the history).
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "event"
          type: "[event](##{dataStructure.getDocId("event")})"
          description: """
                       The event.
                       """
        ,
          key: "history"
          type: "array of [events](##{dataStructure.getDocId("event")})"
          optional: true
          description: """
                       If requested by `includeHistory`, the history of the event as an array of events, ordered by modification time.
                       """
        ]
      examples: [
        title: "Fetching an event's version history"
        params: {"includeHistory": true}
        result:
          event: examples.events.noteWithHistory
          history: [
            examples.events.noteHistory1,
            examples.events.noteHistory2
          ]
      ]

    ,

      id: "events.create"
      type: "method"
      title: "Create event"
      http: "POST /events"
      description: """
                   Records a new event, in addition to JSON, this request accepts standard multipart/form-data content to support the creation of event with attached files in a single request. When sending a multipart request, one content part must hold the JSON for the new event and all other content parts must be the attached files.
                   """
      params:
        description: """
                     The new event's data: see [Event](##{dataStructure.getDocId("event")}).
                     """
      result:
        http: "201 Created"
        properties: [
          key: "event"
          type: "[event](##{dataStructure.getDocId("event")})"
          description: """
                       The created event.
                       """
        ]
      errors: [
        key: "invalid-operation"
        http: "400"
        description: """
                     The referenced stream is in the trash, and we prevent the recording of new events into trashed streams.
                     """
      ]
      examples: [
        title: "Capturing a simple number value"
        params: _.pick(examples.events.mass, "streamIds", "type", "content")
        result:
          event: examples.events.mass
      ,
        title: "cURL with attachment"
        content: """
                 ```bash
                 curl -i -F 'event={"streamIds":["#{examples.events.picture.streamId}"],"type":"#{examples.events.picture.type}"}'  -F "file=@#{examples.events.picture.attachments[0].fileName}" "https://${token}@${username}.pryv.me/events"
                 ```
                 """
        result:
          event: examples.events.picture
      ]

    ,

      id: "events.update"
      type: "method"
      title: "Update event"
      http: "PUT /events/{id}"
      description: """
                   Modifies the event.
                   """
      params:
        properties: [
          key: "id"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The id of the event.
                       """
        ,
          key: "update"
          type: "object"
          http:
            text: "request body"
          description: """
                       New values for the event's fields: see [event](##{dataStructure.getDocId("event")}). All fields are optional, and only modified values must be included.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "event"
          type: "[event](##{dataStructure.getDocId("event")})"
          description: """
                       The updated event.
                       """
        ]
      errors: []
      examples: [
        title: "Changing streams"
        params:
          id: "ckbs54rfh0014ik0sabqobcsb"
          update:
            streamIds: ["position"]
        result:
          event: _.defaults({ id: "ckbs54rfh0014ik0sabqobcsb", streamIds: ["position"], streamId: "position", modified: timestamp.now(), modifiedBy: examples.accesses.app.id }, examples.events.position)
      ]

    ,

      id: "events.addAttachment"
      type: "method"
      title: "Add attachment(s)"
      httpOnly: true
      http: "POST /events/{id}"
      description: """
                   Adds one or more file attachments to the event. This request expects standard multipart/form-data content, with all content parts being the attached files.
                   """
      result:
        http: "200 OK"
        properties: [
          key: "event"
          type: "[event](##{dataStructure.getDocId("event")})"
          description: """
                       The updated event.
                       """
        ]
      examples: [
        title: "cURL"
        content: """
                 ```bash
                 curl -i -F "file=@travel-expense.jpg" "https://${token}@${username}.pryv.me/events/#{examples.events.activityAttachment.id}""
                 ```
                 """
        result:
          event: examples.events.activityAttachment
      ]

    ,

      id: "events.getAttachment"
      type: "method"
      title: "Get attachment"
      httpOnly: true
      http: "GET /events/{id}/{fileId}[/{fileName}]"
      description: """
                   Gets the attached file. Accepts an arbitrary filename path suffix (ignored) for easier link readability.
                   For this function using the `auth` query parameter is not accepted. You can either use the [access token](##{dataStructure.getDocId("access")}) in the `Authorization` header or provide the `readToken` as query parameter.
                   """
      params:
        properties: [
          key: "readToken"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       Required if not using the `Authorization` HTTP header. The file read token to authentify the request. See [`event.attachments[].readToken`](##{dataStructure.getDocId("event")}) for more info.
                       """
        ]
      result:
        http: "200 OK"
        description: """
                     The file's content, with a **Digest** header with SHA-256 hash of the file, encoded in base64, `SHA-256=....` to check file integrity see [RFC3230](https://www.ietf.org/rfc/rfc3230.txt) and [RFC5843](https://datatracker.ietf.org/doc/html/rfc5843)
                     """
    ,

      id: "events.deleteAttachment"
      type: "method"
      title: "Delete attachment"
      http: "DELETE /events/{id}/{fileId}"
      description: """
                   Irreversibly deletes the attached file.
                   """
      params:
        properties: [
          key: "id"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The id of the event.
                       """
        ,
          key: "fileId"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The id of the attached file.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "event"
          type: "[event](##{dataStructure.getDocId("event")})"
          description: """
                       The updated event.
                       """
        ]
      examples: [
        params:
          id: examples.events.activityAttachment.id
          fileId: examples.events.activityAttachment.attachments[0].id
        result:
          event: _.omit(examples.events.activityAttachment, "attachments")
      ]
    ,

      id: "events.delete"
      type: "method"
      title: "Delete event"
      http: "DELETE /events/{id}"
      description: """
                   Trashes or deletes the specified event, depending on its current state:

                   - If the event is not already in the trash, it will be moved to the trash (i.e. flagged as `trashed`)
                   - If the event is already in the trash, it will be irreversibly deleted (including all its attached files, if any).
                   """
      params:
        properties: [
          key: "id"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The id of the event.
                       """
        ]
      result: [
        title: "Result: trashed"
        http: "200 OK"
        properties: [
          key: "event"
          type: "[event](##{dataStructure.getDocId("event")})"
          description: """
                       The trashed event.
                       """
        ]
      ,
        title: "Result: deleted"
        http: "200 OK"
        properties: [
          key: "eventDeletion"
          type: "[item deletion](##{dataStructure.getDocId("item-deletion")})"
          description: """
                       The event deletion record.
                       """
        ]
      ]
      examples: [
        title: "Trashing"
        params:
          id: examples.events.note.id
        result:
          event: _.defaults({ trashed: true, modified: timestamp.now(), modifiedBy: examples.accesses.app.id }, examples.events.note)
      ,
        title: "Deleting"
        params:
          id: examples.events.note.id
        result: {eventDeletion:{id:examples.events.note.id}}
      ]
    ]
  ,

  id: "hfs"
  title: "HF events"
  description: """
                Methods to manipulate high-frequency data through HF events and [HF series](##{dataStructure.getDocId("high-frequency-series")}).
               """
  sections: [
      id: "hfs.create"
      type: "method"
      title: "Create HF event"
      http: "POST /events"
      description: """
                   Creates a new event that will be holding [HF series](##{dataStructure.getDocId("high-frequency-series")}).
                   """
      params:
        description: """
                     The new event's data: see [Event](##{dataStructure.getDocId("event")}).

                     The content of HF events is read-only, so you should not provide any content.
                     However, the event type should correspond to the type of the data points in the series, prefixed with `series:`.
                     For example, to store HF series of `mass/kg` data points, the type of the holder event should be `series:mass/kg`.
                     """
      result:
        http: "201 Created"
        properties: [
          key: "event"
          type: "[event](##{dataStructure.getDocId("event")})"
          description: """
                       The created event.
                       """
        ]
      errors: [
        key: "invalid-operation"
        http: "400"
        description: """
                     The referenced stream is in the trash, and we prevent the recording of new events into trashed streams.
                     """
      ,
        key: "invalid-parameters-format"
        http: "400"
        description: """
                     The event content's format is invalid. Events of type High-frequency have a read-only content.
                     """
      ]
      examples: [
        title: "Creating a new HF event that will hold HF series"
        params: _.pick(examples.events.series.holderEvent, "streamIds", "type")
        result:
          event: examples.events.series.holderEvent

      ]

    ,
      id: "hfs.get"
      type: "method"
      httpOnly: true
      title: "Get HF series data points"
      http: "GET /events/{id}/series"
      description: """
                   Retrieves HF series data points from a HF event.
                   Returns data in order of ascending deltaTime between "fromTime" and "toTime".
                   Data is returned as input, no sampling or aggregation is performed.
                   """
      params:
        properties: [
          key: "fromDeltaTime"
          type: "[timestamp](##{dataStructure.getDocId("timestamp")})"
          optional: true
          description: """
                       Only returns data points later than this deltaTime. If no value is given the query will return data starting at the earliest deltaTime in the series.
                       """
        ,
          key: "toDeltaTime"
          type: "[timestamp](##{dataStructure.getDocId("timestamp")})"
          optional: true
          description: """
                       Only returns data points earlier than this deltaTime. If no value is given the server will return only data that is in the past.
                       """
        ]
      result:
        http: "200 OK"
        description: """
              The [HF series data points](##{dataStructure.getDocId("high-frequency-series")}).
              """
      examples: [
        title: "Retrieving HF series data points from a HF event"
        params: {}
        result:
          examples.events.series.position
      ]

    ,

      id: "hfs.add"
      type: "method"
      httpOnly: true
      title: "Add HF series data points"
      http: "POST /events/{id}/series"
      description: """
                   Adds new HF series data points to a HF event.

                   The HF series data will only store one set of values for any given deltaTime. This means you can update existing data points by 'adding' new data with the original deltaTime.
                   """
      params:
        description: """
                     The new HF series data point(s), see [HF series](##{dataStructure.getDocId("high-frequency-series")}).
                     """
      result:
        http: "200 OK"
        properties: [
          key: "status"
          type: "string"
          description: """
                       The string "ok".
                       """
        ]
      errors: [
        key: "invalid-operation"
        http: "400"
        description: """
                     The event is not a HF event.
                     """
      ,
        key: "invalid-operation"
        http: "400"
        description: """
                     The referenced HF event is in the trash, and we prevent the recording of new data points into trashed events.
                     """
      ]
      examples: [
        title: "Adding new HF series data points to a HF event"
        params: examples.events.series.position
        result:
          status: "ok"
      ]

    ,

      id: "hfs.addBatch"
      type: "method"
      httpOnly: true
      title: "Add HF series batch"
      http: "POST /series/batch"
      description: """
                    Adds data to multiple HF series (stored in multiple HF events) in a single atomic operation. This is the fastest way to append data to Pryv; it allows transferring many data points in a single request.

                    For this operation to be successful, all of the following conditions must be fulfilled:

                      - The access token needs write permissions to all series identified by "eventId".
                      - All events referred to must be HF events (type starts with the string "series:").
                      - Fields identified in each individual message must match those specified by the type of the HF event; there must be no duplicates.
                      - All the values in every data point must conform to the type specification.

                    If any part of the batch message is invalid, the entire batch is aborted and the returned result body identifies the error.
                   """
      params:
        properties: [
          key: "format"
          type: "string"
          description: """
                       The format string "seriesBatch".
                       """
        ,
          key: "data"
          type: "array"
          description: """
                       Array of batch entries. Each batch entry is defined as follows:
                       """
          properties: [
            key: "eventId"
            type: "string"
            description: """
                        The id of the HF event.
                        """
          ,
            key: "data"
            type: "object"
            description: """
                        HF series data to add to the HF event.
                        """
          ]
        ]
      result:
        http: "201 Created"
        properties: [
          key: "status"
          type: "string"
          description: """
                       The string "ok".
                       """
        ]
      errors: [
        key: "invalid-request-structure"
        http: "400"
        description: """
                     The request was malformed and could not be executed. The entire operation was aborted.
                     """
      ]
      examples: [
        title: "Adding a batch of HF series data to multiple HF events"
        params: examples.events.series.batch
        result:
          status: "ok"
      ]

    ,

      id: "hfs.update"
      type: "method"
      title: "Update HF event"
      http: "PUT /events/{id}"
      description: """
                    Similar to the standard [Update event](##{_getDocId("events", "events.update")}) method.

                    You may update all non read-only fields, except `content` which is read-only for HF events.
                   """
      errors: [
        key: "invalid-parameters-format"
        http: "400"
        description: """
                     The event content's format is invalid. Events of type High-frequency have a read-only content.
                     """
      ]

    ,

      id: "hfs.delete"
      type: "method"
      title: "Delete HF event"
      http: "DELETE /events/{id}"
      description: """
                   Similar to the standard [Delete event](##{_getDocId("events", "events.delete")}) method.
                   """
  ]

  ,

    id: "streams"
    title: "Streams"
    description: """
                 Methods to retrieve and manipulate [streams](##{dataStructure.getDocId("stream")}).
                 """
    sections: [
      id: "streams.get"
      type: "method"
      title: "Get streams"
      http: "GET /streams"
      description: """
                   Gets the accessible streams hierarchy.
                   """
      params:
        properties: [
          key: "parentId"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          optional: true
          description: """
                       The id of the parent stream from which to retrieve streams. Default: `null` (returns all accessible streams from the root level).
                       """
        ,
          key: "state"
          type: "`default`|`all`"
          optional: true
          description: """
                       By default, only items that are not in the trash are returned; `all` return all items regardless of their state.
                       """
        ,
          key: "includeDeletionsSince"
          type: "[timestamp](##{dataStructure.getDocId("timestamp")})"
          optional: true
          description: """
                       Whether to include stream deletions since that time for sync purposes.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "streams"
          type: "array of [streams](##{dataStructure.getDocId("stream")})"
          description: """
                       The tree of the accessible streams, sorted by name.
                       """
        ,
          key: "streamDeletions"
          type: "array of [item deletions](##{dataStructure.getDocId("item-deletion")})"
          optional: true
          description: """
                       If requested by `includeDeletionsSince`, the stream deletions since then, ordered by deletion time.
                       """
        ]
      examples: [
        title: "Retrieving streams for work activities"
        params:
          parentId: examples.streams.activities[1].id
        result:
          streams: examples.streams.activities[1].children
      ]

    ,

      id: "streams.create"
      type: "method"
      title: "Create stream"
      http: "POST /streams"
      description: """
                   Creates a new stream.
                   """
      params:
        description: """
                     The new stream's data: see [stream](##{dataStructure.getDocId("stream")}).
                     """
      result:
        http: "201 Created"
        properties: [
          key: "stream"
          type: "[stream](##{dataStructure.getDocId("stream")})"
          description: """
                       The created stream.
                       """
        ]
      errors: [
        key: "item-already-exists"
        http: "409"
        description: """
                     A similar stream already exists. The error's `data` contains the conflicting properties.
                     """
      ,
        key: "invalid-item-id"
        http: "400"
        description: """
                     The specified id is invalid (e.g. it's a reserved word such as `null`).
                     """
      ]
      examples: [
        title: "Create sub-stream 'white-cells' of 'blood'"
        params: _.pick(examples.streams.healthSubstreams[0], "id", "name", "parentId")
        result:
          stream: examples.streams.healthSubstreams[0]
      ]

    ,

      id: "streams.update"
      type: "method"
      title: "Update stream"
      http: "PUT /streams/{id}"
      description: """
                   Modifies the stream.
                   """
      params:
        properties: [
          key: "id"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The id of the stream.
                       """
        ,
          key: "update"
          type: "object"
          http:
            text: "request body"
          description: """
                       New values for the stream's fields: see [stream](##{dataStructure.getDocId("stream")}). All fields are optional, and only modified values must be included.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "stream"
          type: "[stream](##{dataStructure.getDocId("stream")})"
          description: """
                       The updated stream (without child streams).
                       """
        ]
      errors: [
        key: "item-already-exists"
        http: "409"
        description: """
                     A similar stream already exists. The error's `data` contains the conflicting properties.
                     """
      ]
      examples: [
        title: "Renaming a stream"
        params:
          id: examples.streams.activities[0].id
          update:
            name: "Slothing"
        result:
          stream: _.defaults({ name: "Slothing", modified: timestamp.now(), modifiedBy: examples.accesses.app.id }, _.omit(examples.streams.activities[0], "children"))
      ]

    ,

      id: "streams.delete"
      type: "method"
      title: "Delete stream"
      http: "DELETE /streams/{id}"
      description: """
                   Trashes or deletes the specified stream, depending on its current state:

                   - If the stream is not already in the trash, it will be moved to the trash (i.e. flagged as `trashed`)
                   - If the stream is already in the trash, it will be irreversibly deleted with its descendants (if any). If events exist that refer to the deleted item(s), you must indicate how to handle them with the parameter `mergeEventsWithParent`.
                   """
      params:
        properties: [
          key: "id"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The id of the stream.
                       """
        ,
          key: "mergeEventsWithParent"
          type: "boolean"
          description: """
                       Required if actually deleting the item and if it (or any of its descendants) has linked events, ignored otherwise. If `true`, the linked events will be assigned to the parent of the deleted item; if `false`, the linked events will be deleted.
                       """
        ]
      result: [
        title: "Result: trashed"
        http: "200 OK"
        properties: [
          key: "stream"
          type: "[stream](##{dataStructure.getDocId("stream")})"
          description: """
                       The trashed stream.
                       """
        ]
      ,
        title: "Result: deleted"
        http: "200 OK"
        properties: [
          key: "streamDeletion"
          type: "[item deletion](##{dataStructure.getDocId("item-deletion")})"
          description: """
                       The stream deletion record.
                       """
        ]
      ]
      examples: [
        title: "Trashing"
        params:
          id: examples.streams.health[0].children[2].id
        result:
          stream: _.defaults({ trashed: true, modified: timestamp.now(), modifiedBy: examples.accesses.app.id }, examples.streams.health[0].children[2])
      ,
        title: "Deleting"
        params:
          id: examples.streams.health[0].children[2].id
        result: {streamDeletion:{id:examples.streams.health[0].children[2].id}}
      ]
    ]

  ,

    id: "accesses"
    title: "Accesses"
    description: """
                 Methods to retrieve and manipulate [accesses](##{dataStructure.getDocId("access")}), e.g. for sharing.
                 Any app token can manage shared accesses it created. Full access management is available to personal tokens.
                 """
    sections: [
      id: "accesses.get"
      type: "method"
      title: "Get accesses"
      v2Tag: true
      http: "GET /accesses"
      description: """
                   Gets accesses that were created by your access token, unless you're using a personal token then it returns all accesses.
                   Only returns accesses that are active when making the request. To include accesses that have expired or were deleted, use
                   the `includeExpired` or `includeDeletions` parameters respectively.

                   In v2 the returned `id`, `createdBy`, and `modifiedBy` fields use the composite reference format `<base>:<serial>` for accesses that have been updated at least once. Never-updated accesses still serialise as bare cuid (`<base>`) for full backwards-compatibility. Parse with `pryv.utils.parseAccessRef(ref)` if you need to extract the version.
                   """
      params:
        properties: [
          key: "includeExpired"
          type: "boolean"
          optional: true
          description: """
            If `true`, also includes expired accesses. Defaults to `false`.
          """
        ,
          key: "includeDeletions"
          type: "boolean"
          optional: true
          description: """
            If `true`, also includes deleted accesses. Defaults to `false`.
          """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "accesses"
          type: "array of [accesses](##{dataStructure.getDocId("access")})"
          description: """
                       All manageable accesses in the user's account, ordered by name.
                       """
        ,
          key: "accessDeletions"
          type: "array of deleted [accesses](##{dataStructure.getDocId("access")})"
          description: """
                       If requested by `includeDeletions`, the access deletions, ordered by deletion time.
                       """
        ]
      examples: [
        params: {}
        result:
          accesses: [examples.accesses.shared]
      ,
        title: "cURL with deletions"
        params: """
                ```bash
                curl -i "https://${token}@${username}.pryv.me/accesses?includeDeletions=true
                ```
                """
        result:
          accesses: [examples.accesses.shared]
          accessDeletions: [examples.accesses.deleted]
      ]

    ,

      id: "accesses.getOne"
      type: "method"
      title: "Get one access"
      v2Tag: true
      http: "GET /accesses/{id}"
      description: """
                   Returns the access identified by `{id}`. The id can be either:

                   - **bare** `<base>`, returns the current head row.
                   - **composite** `<base>:<serial>` matching the current head's serial, returns the current head row.
                   - **composite** `<base>:<serial>` referring to an *older* serial, returns the historical snapshot from that version, alongside a `current` hint pointing at the live head's composite id. Mirrors GitHub's `GET /repos/X/Y/commits/<sha>` behaviour for ref-by-version.
                   - any other id (unknown base, or a serial that never existed), `404 unknown-resource`.

                   Pass `?includeHistory=true` to also return the full chronological history of the access (oldest first) in a `history` array. Default `false`, the singular case covers the typical "audit this access" use case without the list-side overhead.

                   App callers can only fetch their own access (self) or shared accesses they directly manage; other access ids return `404 unknown-resource` to avoid info leakage.
                   """
      params:
        properties: [
          key: "id"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The access id to fetch. Bare cuid on never-updated accesses, composite `<base>:<serial>` once versioned.
                       """
        ,
          key: "includeHistory"
          type: "boolean"
          optional: true
          description: """
                       If `true`, include the chronological history of the access. Defaults to `false`.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "access"
          type: "[access](##{dataStructure.getDocId("access")})"
          description: """
                       The requested access (current head, or historical snapshot when the id targets an older serial).
                       """
        ,
          key: "current"
          type: "string"
          optional: true
          description: """
                       Set when the request targeted an older serial, the composite id `<base>:<serial>` of the current head.
                       """
        ,
          key: "history"
          type: "array of [accesses](##{dataStructure.getDocId("access")})"
          optional: true
          description: """
                       Set when `includeHistory=true`, the chronological history of the access (oldest first). Each entry uses the composite id of the frozen version.
                       """
        ]
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     The access does not exist, was soft-deleted, or the caller cannot see it (app caller visibility rule).
                     """
      ]
      examples: [
        params: { id: examples.accesses.shared.id }
        result:
          access: examples.accesses.shared
      ]

    ,

      id: "accesses.create"
      type: "method"
      title: "Create access"
      v2Tag: true
      http: "POST /accesses"
      description: """
                   Creates a new access. You can only create accesses whose permissions are a subset of those granted to your own access token.

                   **v2 behaviour change** (Pryv.io ≥ 2.0.0-pre.X): when an `app` access creates a `shared` access scoped under it, the new shared's `expires` (resolved from `expireAfter` if provided) cannot exceed the managing app's `expires`. Violations return `invalid-operation` with `data: { parentExpires, requestedExpires }`. Personal-issued accesses are not subject to this check (personal accesses typically have no `expires`).
                   """
      params:
        description: """
                     An object with the new access's data: see [access](##{dataStructure.getDocId("access")}).
                     """
        properties: [
          key: "randomAlias"
          type: "boolean"
          optional: true
          description: """
                       When `true`, the access is issued a platform-unique, routable alias (`r-` followed by 8 characters) that replaces the username in the returned `apiEndpoint` and in the access-info response. The real username never appears for this access, so accesses handed to different parties cannot be cross-matched back to one account. The resolved value is returned as the access's `alias`.
                       """
        ]
      result:
        http: "201 Created"
        properties: [
          key: "access"
          type: "[access](##{dataStructure.getDocId("access")})"
          description: """
                       The created access. When `randomAlias` was set, its `alias` holds the issued alias and `apiEndpoint` is built from the alias.
                       """
        ]
      errors: [
        key: "invalid-item-id"
        http: "400"
        description: """
                     The specified token is invalid (e.g. it's a reserved word such as `null`).
                     """
      ]
      examples: [
        params: _.pick(examples.accesses.sharedNew, "name", "permissions")
        result:
          access: examples.accesses.sharedNew
      ]

    ,

      id: "accesses.update"
      type: "method"
      title: "Update access"
      v2Tag: true
      http: "PUT /accesses/{id}"
      description: """
                   Updates the access identified by `{id}`. Each successful update mutates the head row, snapshots the prior state into history, and bumps the access's `serial`. The returned access carries the new wire-format composite id `<base>:<serial>` (or bare `<base>` when never updated).

                   **Mutable fields** (whitelist): `name`, `deviceName`, `permissions`, `expireAfter` / `expires`, `clientData`. Anything else returns `invalid-parameters-format`.

                   **Caller-vs-target matrix**:
                   - `personal` accesses are immutable (no caller can update them).
                   - A `personal` access can update any `app` or `shared` access.
                   - An `app` access can update only the `shared` accesses it directly manages.
                   - `shared` accesses cannot update anything.
                   - No self-update via this method (self-revoke stays available via `accesses.delete`).

                   **Chain rules enforced on update**:
                   - A managed `shared`'s new `permissions` must remain a subset of its managing `app`'s permissions.
                   - Narrowing an `app`'s permissions (or `expires`) is strict-rejected if any managed `shared` would now sit outside the new scope or outlive the new expiry. The error includes `data.offendingChildren: [ids]` so the caller can resolve children first and retry.
                   - A managed `shared`'s `expires` cannot exceed its managing `app`'s `expires` (parent with `expires: null` imposes no cap).

                   **Expiry**: `expireAfter` (seconds, not negative) sets `expires` to the time of the update plus that many seconds; `expires: null` removes the expiry. `deviceName` applies to `app` accesses only, and an OAuth session access (named `oauth:<clientId>`) cannot be renamed.

                   **Composite-id conflict**: the `{id}` must match the current head's `serial`. A stale composite returns `409 stale-resource` with `data: { provided, currentSerial }`; refetch the access via [Get one access](##{_getDocId("accesses", "accesses.getOne")}) and retry with the current head id. Bare `<base>` is only valid on a never-updated access.

                   On success, the server emits an `accessesChanged` socket.io event (coarse-grained) and an `accessUpdated` event with payload `{ type: 'access-updated', accessId, serial }` (fine-grained).
                   """
      params:
        properties: [
          key: "id"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The access id (bare or composite) to update.
                       """
        ,
          key: "update"
          type: "object"
          http:
            text: "request body"
          description: """
                       Subset of mutable fields (`name`, `deviceName`, `permissions`, `expireAfter`, `expires: null`, `clientData`). Sent as the HTTP request body, the server wraps it into `params.update`.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "access"
          type: "[access](##{dataStructure.getDocId("access")})"
          description: """
                       The updated head, with new composite `id` and bumped `serial`.
                       """
        ]
      errors: [
        key: "stale-resource"
        http: "409"
        description: """
                     The provided composite `{id}` does not match the current head's serial. Refetch via `accesses.getOne` and retry.
                     """
      ,
        key: "invalid-operation"
        http: "400"
        description: """
                     Chain rule violation. `data.offendingChildren` lists shared accesses that would be orphaned by a narrowing; `data.parentExpires` / `data.requestedExpires` are set for expiry-chain rejections.
                     """
      ,
        key: "forbidden"
        http: "403"
        description: """
                     Caller is not allowed to update the target (personal access, self-update, app-trying-to-update-a-non-managed-access, or shared caller).
                     """
      ,
        key: "unknown-resource"
        http: "404"
        description: """
                     Access not found or soft-deleted.
                     """
      ]
      examples: [
        params:
          id: examples.accesses.shared.id
          update: { name: "Renamed shared" }
        result:
          access: examples.accesses.shared
      ]

    ,

      id: "accesses.delete"
      type: "method"
      title: "Delete access"
      v2Tag: true
      http: "DELETE /accesses/{id}"
      description: """
                   Deletes the specified access. Personal accesses can delete any access. App accesses can delete shared accesses they created. Deleting an app access deletes the shared ones it created.
                   All accesses can also perform a self-delete unless a forbidden `selfRevoke` permission has been set.

                   **v2 behaviour change** (Pryv.io ≥ 2.0.0-pre.X): the `{id}` is composite-aware, pass the composite `<base>:<serial>` you last observed via [Get accesses](##{_getDocId("accesses", "accesses.get")}) or [Get one access](##{_getDocId("accesses", "accesses.getOne")}). A stale composite returns `409 stale-resource` with `data: { provided, currentSerial }`; refetch and retry. Bare `<base>` is only valid on a never-updated access.
                   """
      params:
        properties: [
          key: "id"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The id of the access.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "accessDeletion"
          type: "[item deletion](##{dataStructure.getDocId("item-deletion")})"
          description: """
                       The deletion record.
                       """
        ,
          key: "relatedDeletions"
          type: "array of [item deletions](##{dataStructure.getDocId("item-deletion")})"
          optional: true
          description: """
                       The deletion records of all the shared accesses that were generated from this app token when deleting it
                       """
        ]
      examples: [
        params:
          id: examples.accesses.app.id
        result:
          accessDeletion:
            id: examples.accesses.app.id
          relatedDeletions: [
            id: generateId()
          ,
            id: generateId()
          ]
      ]

    ,

      id: "accesses.checkApp"
      type: "method"
      trustedOnly: true
      title: "Check app authorization"
      http: "POST /accesses/check-app"
      description: """
                   For the app authorization process. Checks if the app requesting authorization already has access with the same permissions (and on the same device, if applicable), and returns details of the requested permissions' streams (for display) if not.
                   """
      params:
        properties: [
          key: "requestingAppId"
          type: "string"
          description: """
                       The id of the app requesting authorization.
                       """
        ,
          key: "deviceName"
          type: "string"
          optional: true
          description: """
                       The name of the device running the app requesting authorization, if applicable.
                       """
        ,
          key: "requestedPermissions"
          type: "array of permission request objects"
          description: """
                       An array of permission request objects, which are identical to stream permission objects of [accesses](##{dataStructure.getDocId("access")}) except that each stream permission object must have a `defaultName` property specifying the name the stream should be created with later if missing.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "checkedPermissions"
          type: "array of permission request objects"
          description: """
                       Set if no matching access already exists.
                       A updated copy of the `requestedPermissions` parameter, with the `defaultName` property of stream permissions replaced by `name` for each existing stream (set to the actual name of the item). (For missing streams the `defaultName` property is left untouched.) If streams already exist with the same name but a different `id`, `defaultName` is updated with a valid alternative proposal (in such cases the result also has an `error` property to signal the issue).
                       """
        ,
          key: "mismatchingAccess"
          type: "[access](##{dataStructure.getDocId("access")})"
          description: """
                       Set if an access already exists for the requesting app, but with different permissions than those requested.
                       """
        ,
          key: "matchingAccess"
          type: "[access](##{dataStructure.getDocId("access")})"
          description: """
                       Set if an access already exists for the requesting app with matching permissions. The existing [access](##{dataStructure.getDocId("access")}).
                       """
        ]
      examples: []
    ]
  ,

    id: "getAccessInfo"
    type: "method"
    title: "Access Info"
    http: "GET /access-info"
    description: """
                  Retrieves information about the access in use.
                  """
    result:
      http: "200 OK"
      description: """
            The current [Access properties](##{dataStructure.getDocId("access")}), as well as:
            """
      properties: [
        key: "calls"
        type: "[key-value](##{_getDocId("key-value")})"
        description: "A map of API methods and the number of time each of them was called using the current access."
      ,
        key: "user"
        type: "[key-value](##{_getDocId("key-value")})"
        description: "A map of user account properties."
      ,
        key: "delegation"
        type: "object"
        optional: true
        description: """
                     Present only when the access comes from [account delegation](/guides/account-delegation/); absent for every other access. `user.username` stays the account the access lives on.

                     For a delegate token, and for an access granted with one (an app access an auth page created for an account the user controls, and the accesses that app creates in turn): `{ isDelegatedAccess: true, controlledUsername, delegate: { username, hostSlug } }`, plus `grantedVia: "app"` for a granted access. For a control access: `{ kind: "control", controlledUsername, delegate }`.

                     This is the authoritative answer to "is this app acting for a controlled account?": the `delegation` block of an [accepted auth request](#poll-request) is only a display hint.
                     """
        properties: [
          key: "isDelegatedAccess"
          type: "`true`"
          optional: true
          description: """
                       Set for a delegate token and for an access granted through a delegation.
                       """
        ,
          key: "controlledUsername"
          type: "string"
          description: """
                       The controlled account (the account the access lives on).
                       """
        ,
          key: "delegate"
          type: "object"
          description: """
                       The delegate the access acts for: `username`, and `hostSlug` (its core) when known.
                       """
        ,
          key: "grantedVia"
          type: "`app`"
          optional: true
          description: """
                       Set when the access was granted through the delegation rather than being the delegate token itself. Such an access is revoked when the delegate is removed from the controlled account.
                       """
        ,
          key: "kind"
          type: "`control`"
          optional: true
          description: """
                       Set, instead of `isDelegatedAccess`, for a control access.
                       """
        ]
      ]
    examples: [
      params: {}
      result: examples.accesses.info
    ]
  ,
    id: "webhooks"
    title: "Webhooks"
    description: """
                 Methods to retrieve and manipulate [webhooks](##{dataStructure.getDocId("webhook")}). These methods are only allowed for app and personal accesses.
                 """
    sections: [
      id: "webhooks.get"
      type: "method"
      title: "Get webhooks"
      http: "GET /webhooks"
      description: """
                   Gets manageable webhooks. Only returns webhooks that were created by the access, unless you are using a personal access which returns all existing webhooks in the user's account.
                   """
      params:
        properties: [
        ]
      result:
        http: "200 OK"
        properties: [
          key: "webhooks"
          type: "array of [webhooks](##{dataStructure.getDocId("webhook")})"
          description: """
                       All manageable webhooks by the given access, ordered by modified date.
                       """
        ]
      examples: [
        params: {}
        result:
          webhooks: [
            examples.webhooks.simple
          ,
            examples.webhooks.failing
          ]
      ]

    ,
      id: "webhooks.getOne"
      type: "method"
      title: "Get one webhook"
      http: "GET /webhooks/{id}"
      description: """
                   Fetches a specific webhook. Only returns a webhook if it was created by the access, unless you are using a personal access which is allowed to fetch any existing webhook in the user's account.
                   """
      params:
        properties: [
          key: "id"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The id of the webhook.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "webhook"
          type: "[webhook](##{dataStructure.getDocId("webhook")})"
          description: """
                       The webhook.
                       """
        ]
      examples: [
        params: {}
        result:
          webhook: examples.webhooks.simple
      ]

    ,

      id: "webhooks.create"
      type: "method"
      title: "Create webhook"
      http: "POST /webhooks"
      description: """
                   Creates a new webhook. You can only create webhooks with `app` and `shared` accesses.
                   """
      params:
        description: """
                     An object with the new webhook's data: see [webhook](##{dataStructure.getDocId("webhook")}).
                     """
      result:
        http: "201 Created"
        properties: [
          key: "webhook"
          type: "[webhook](##{dataStructure.getDocId("webhook")})"
          description: """
                       The created webhook.
                       """
        ]
      errors: []
      examples: [
        title: "A simple webhook"
        params: _.pick(examples.webhooks.simple, "url")
        result:
          webhook: examples.webhooks.simple
      ,
        title: "A scoped webhook (notified only of matching changes)"
        params: _.pick(examples.webhooks.new, "url", "scopes")
        result:
          webhook: examples.webhooks.new
      ]

    ,

      id: "webhooks.update"
      type: "method"
      title: "Update webhook"
      http: "PUT /webhooks/{id}"
      description: """
                   Modifies the webhook. You can only modify webhooks with the access that was used to create them, unless you are using a personal token.
                   Updating the `state` to `active` resets the `currentRetries` counter.
                   """
      params:
        properties: [
          key: "id"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The id of the webhook.
                       """
        ,
          key: "update"
          type: "object"
          http:
            text: "request body"
          description: """
                       New values for the webhook's fields: see [webhook](##{dataStructure.getDocId("webhook")}). All fields are optional, and only modified values must be included.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "webhook"
          type: "[webhook](##{dataStructure.getDocId("webhook")})"
          description: """
                       The updated webhook.
                       """
        ]
      errors: [
        key: "item-already-exists"
        http: "409"
        description: """
                     There is already a webhook for this URL created by the given access.
                     """
      ]
      examples: [
        title: "Reactivating a webhook"
        params:
          state: 'active'
        result:
          webhook: examples.webhooks.hasFailed
      ]

    ,

      id: "webhooks.delete"
      type: "method"
      title: "Delete webhook"
      http: "DELETE /webhooks/{id}"
      description: """
                   Deletes the specified webhook. You can only delete webhooks with the access that was used to create them, unless you are using a personal token.
                   """
      params:
        properties: [
          key: "id"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The id of the webhook.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "webhookDeletion"
          type: "[item deletion](##{dataStructure.getDocId("item-deletion")})"
          description: """
                       The deletion record.
                       """
        ]
      examples: [
        params:
          id: examples.webhooks.new.id
        result: {webhookDeletion:{id:examples.webhooks.new.id}}
      ]

    ,

      id: "webhooks.test"
      type: "method"
      title: "Test webhook"
      http: "POST /webhooks/{id}/test"
      description: """
                   Sends a post request containing a message called `test` to the URL of the specified webhook's `url`. You can only test webhooks with the access that was used to create them, unless you are using a personal token.
                   """
      params:
        properties: [
          key: "id"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The id of the webhook.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "webhook"
          type: "[webhook](##{dataStructure.getDocId("webhook")})"
          description: """
                       The webhook.
                       """
        ]
      examples: [
        params: {}
        result:
          webhook: examples.webhooks.new
      ]
      errors: [
        key: "unknown-referenced-resource"
        http: "400"
        description: """
                     The webhook's `url` is either unreachable or responds with a 4xx/5xx status.
                     """
        ]

    ]

  ,

    id: "shared-secrets"
    title: "Shared secrets"
    description: """
                 Hand a secret to a third party by a one-time random **key** instead of
                 embedding the credential (typically an apiEndpoint carrying an access
                 token) in a URL, where it would persist in browser history, `Referer`
                 headers and server access logs.

                 A key is redeemable **exactly once** and expires after a mandatory TTL.
                 The server stores only the `SHA-256` of the key's random half, so the
                 clear key exists only in the creation response and cannot be recovered
                 afterwards.

                 The secret is scrubbed the moment the item stops being pending: when the
                 key is redeemed, when the item is discarded, or on the first retrieval
                 attempt made after the TTL has passed. Expiry is enforced on access, not
                 by a background sweeper, so an item that expires and is never touched
                 again keeps its stored payload until something reaches it or it is
                 removed with [events.delete](##{_getDocId("events", "events.delete")}).

                 The redemption call needs no credentials (the key itself is the
                 credential), so the key always travels in the **request body**, never in
                 the URL.

                 Shared secrets are stored as events under a reserved per-access stream
                 and can be listed with a standard [events.get](##{_getDocId("events", "events.get")})
                 naming that stream explicitly; they never appear in a wildcard query.
                 An access can be barred from creating them with the `secretSharing`
                 feature permission.

                 The feature is optional: on a platform where the operator has disabled
                 it, all three methods below answer `451 unavailable-method`.
                 """
    sections: [

      id: "sharedSecrets.create"
      type: "method"
      title: "Create shared secret"
      http: "POST /shared-secrets"
      description: """
                   Stores a secret and returns a one-time key for it. The `key` is
                   returned **once** and is not recoverable afterwards. Requires an
                   access whose `secretSharing` feature permission is not `forbidden`.
                   """
      params:
        properties: [
          key: "ttl"
          type: "number"
          description: """
                       Seconds the key stays redeemable. Required, must be greater than 0
                       and not exceed the configured maximum (30 days by default).
                       """
        ,
          key: "title"
          type: "string"
          description: """
                       A label shown to the account owner.
                       """
        ,
          key: "onConsumed"
          type: "object"
          description: """
                       `{ message, returnUrl }` returned to whoever presents the key once
                       it is no longer available. `message` is required; the optional
                       `returnUrl` must be an `http(s)` URL (it is followed by an
                       unauthenticated third party).
                       """
        ,
          key: "secret"
          type: "object"
          description: """
                       The payload to hand over: any non-null JSON value. Its serialized
                       size must not exceed the configured maximum (4096 bytes by default).
                       """
        ,
          key: "signature"
          optional: true
          type: "object"
          description: """
                       Optional proof required to redeem. `{ type: "secret", value }`
                       compares a passphrase shared out-of-band; `{ type: "hmac-sha256",
                       value }` verifies an HMAC the redeemer computes from a verifier
                       secret that never reaches the server. For `hmac-sha256`, `value`
                       must be the lowercase-hex `HMAC-SHA256(verifierSecret, randomHalf)`
                       where `randomHalf` is the part of the key after the dot: the server
                       compares the redeemer's proof against this stored string
                       byte-for-byte, so both sides must derive it the same way. A wrong
                       proof discards the secret; a missing one is refused without
                       discarding it.
                       """
        ,
          key: "keyHash"
          optional: true
          type: "string"
          description: """
                       Hex `SHA-256` of a random half you generate yourself (at least 192
                       bits of entropy), for binding an `hmac-sha256` signature to the key
                       before the item exists. When supplied, the response carries no
                       `key`: compose it yourself as `{id}.{yourRandomHalf}`. Omit it to
                       let the server mint and return the key.

                       The random half must be 32 to 128 characters from the base64url
                       alphabet (`A-Za-z0-9_-`); lowercase hex qualifies. Creation only
                       checks the hash, so a half that breaks this rule (standard base64
                       padding, for instance) is accepted here and then fails every
                       redemption with the uniform refusal, leaving a secret that can
                       never be reached.
                       """
        ]
      result:
        http: "201 Created"
        properties: [
          key: "sharedSecret"
          type: "object"
          description: """
                       `{ id, key, status, title, statusHistory, onConsumed, expires }`,
                       plus `signatureType` when a signature was set. `key` is present
                       only when the server minted it (i.e. `keyHash` was not supplied)
                       and is returned this one time only.
                       """
        ]
      errors: [
        key: "invalid-parameters-format"
        http: "400"
        description: """
                     A required field is missing or malformed, including a non-positive or
                     too-long `ttl`, an oversized `secret`, a non-`http(s)` `returnUrl`, or
                     an unknown `signature` type.
                     """
      ,
        key: "forbidden"
        http: "403"
        description: """
                     The access is barred from creating shared secrets by a
                     `secretSharing: forbidden` feature permission.
                     """
      ]

    ,

      id: "sharedSecrets.retrieve"
      type: "method"
      title: "Redeem shared secret"
      http: "POST /shared-secrets/retrieve"
      description: """
                   Redeems a key for its secret. **Unauthenticated** (the key is the
                   credential), so no access token is required. Succeeds exactly once;
                   every later attempt returns the creator's `onConsumed` message. Unknown
                   or malformed keys receive a single uniform refusal that does not reveal
                   whether a given item exists.
                   """
      params:
        properties: [
          key: "key"
          type: "string"
          description: """
                       The one-time key, as returned by (or composed from) the create call.
                       """
        ,
          key: "signature"
          optional: true
          type: "object"
          description: """
                       `{ type, payload }` proof, required only if the secret was created
                       with a signature. For `secret`, `payload` is the passphrase; for
                       `hmac-sha256`, `payload` is the lowercase-hex
                       `HMAC-SHA256(verifierSecret, randomHalf)`, computed over the part
                       of the key after the dot.

                       **A wrong proof discards the secret permanently**; nobody can
                       redeem it afterwards. A *missing* proof is refused without
                       discarding anything, so a client that knows a proof is needed may
                       retry. There is no way to tell from the response that a proof is
                       required: the refusal is byte-identical to the one for an
                       already-consumed item, so the redeemer must learn it from the
                       creator.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "secret"
          type: "object"
          description: """
                       The stored secret payload.
                       """
        ]
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     The uniform refusal: the key is malformed, names nothing, or does not
                     match the stored hash. It is deliberately the same answer in every
                     case, so it cannot be used to learn whether an item exists, and it
                     never consumes or discards anything.
                     """
      ,
        key: "forbidden"
        http: "403"
        description: """
                     The secret is no longer available (already redeemed, expired, or
                     discarded), or the signature proof was wrong. The response carries the
                     creator's `message` and optional `returnUrl`.
                     """
      ]

    ,

      id: "sharedSecrets.getOne"
      type: "method"
      title: "Get shared secret status"
      http: "POST /shared-secrets/status"
      description: """
                   Returns the status and metadata of a shared secret **without consuming
                   it**. Available to the access that created the secret or to a personal
                   token. Never returns the secret payload. An item past its TTL is
                   reported as expired even before it is redeemed.
                   """
      params:
        properties: [
          key: "key"
          type: "string"
          description: """
                       The one-time key.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "sharedSecret"
          type: "object"
          description: """
                       `{ id, title, status, statusHistory, onConsumed, expires }`, plus
                       `signatureType` when a signature was set and `expired: true` when
                       the TTL has passed (the reported `status` is then `discarded`,
                       though the stored item is left untouched). Never includes the
                       secret.
                       """
        ]
      errors: [
        key: "unknown-resource"
        http: "404"
        description: """
                     The key is malformed, names nothing, does not match the stored hash,
                     or the caller is neither the access that created the secret nor a
                     personal token. All four give the same answer, so status cannot be
                     used to probe a key.
                     """
      ]

    ]

  ,

    id: "followed-slices"
    title: "Followed slices"
    trustedOnly: true
    description: """
                 Methods to retrieve and manipulate [followed slices](##{dataStructure.getDocId("followed-slice")}).
                 """
    sections: [
      id: "followedSlices.get"
      type: "method"
      title: "Get followed slices"
      http: "GET /followed-slices"
      description: """
                   Gets followed slices.
                   """
      result:
        http: "200 OK"
        properties: [
          key: "followedSlices"
          type: "array of [followed slices](##{dataStructure.getDocId("followed-slice")})"
          description: """
                       All followed slices in the user's account, ordered by name.
                       """
        ]
      examples: []

    ,

      id: "followedSlices.create"
      type: "method"
      title: "Create followed slice"
      http: "POST /followed-slices"
      description: """
                   Creates a new followed slice.
                   """
      params:
        description: """
                     An object with the new followed slice's data: see [followed slice](##{dataStructure.getDocId("followed-slice")}).
                     """
      result:
        http: "201 Created"
        properties: [
          key: "followedSlice"
          type: "[followed slice](##{dataStructure.getDocId("followed-slice")})"
          description: """
                       The created followed slice.
                       """
        ]
      examples: []

    ,

      id: "followedSlices.update"
      type: "method"
      title: "Update followed slice"
      http: "PUT /followed-slices/{id}"
      description: """
                   Modifies the specified followed slice.
                   """
      params:
        properties: [
          key: "id"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The id of the followed slice.
                       """
        ,
          key: "update"
          type: "object"
          http:
            text: "request body"
          description: """
                       New values for the followed slice's fields: see [followed slice](##{dataStructure.getDocId("followed-slice")}). All fields are optional, and only modified values must be included.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "followedSlice"
          type: "[followed slice](##{dataStructure.getDocId("followed-slice")})"
          description: """
                       The updated followed slice.
                       """
        ]
      examples: []

    ,

      id: "followedSlices.delete"
      type: "method"
      title: "Delete followed slice"
      http: "DELETE /followed-slices/{id}"
      description: """
                   Deletes the specified followed slice.
                   """
      params:
        properties: [
          key: "id"
          type: "[identifier](##{dataStructure.getDocId("identifier")})"
          http:
            text: "set in request path"
          description: """
                       The id of the followed slice.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "followedSliceDeletion"
          type: "[item deletion](##{dataStructure.getDocId("item-deletion")})"
          description: """
                       The deletion record.
                       """
        ]
      examples: []
    ]

  ,

    id: "profile"
    title: "Profile sets"
    description: """
                 Methods to read and write profile sets. Profile sets are plain key-value stores of user-level settings.
                 """
    sections: [
      id: "profile.getApp"
      type: "method"
      title: "Get app profile"
      http: "GET /profile/app"
      description: """
                   Gets the app's dedicated profile set, which contains app-level settings for the user. Available to app accesses.
                   """
      result:
        http: "200 OK"
        properties: [
          key: "profile"
          type: "object"
          description: """
                       The app profile set. (Empty if the app never defined any setting.)
                       """
        ]
      examples: [
        params: {}
        result:
          profile: examples.profileSets.app
      ]

    ,

      id: "profile.updateApp"
      type: "method"
      title: "Update app profile"
      http: "PUT /profile/app"
      description: """
                   Adds, updates or delete app profile keys. Available to app accesses.

                   - To add or update a key, just set its value
                   - To delete a key, set its value to `null`

                   Existing keys not included in the update are left untouched.
                   """
      params:
        properties: [
          key: "update"
          type: "object"
          http:
            text: "request body"
          description: """
                       An object with the desired key changes (see above).
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "profile"
          type: "object"
          description: """
                       The updated app profile set.
                       """
        ]
      examples: [
        params:
          setting1: "new value",
          setting2: null
        result:
          profile: _.defaults({setting1: "new value"}, _.omit(examples.profileSets.app, "setting2"))
      ]

    ,

      id: "profile.getPublic"
      type: "method"
      title: "Get public profile"
      http: "GET /profile/public"
      description: """
                   Gets the public profile set, which contains the information the user makes publicly available (e.g. avatar image). Available to all accesses.
                   """
      result:
        http: "200 OK"
        properties: [
          key: "profile"
          type: "object"
          description: """
                       The public profile set.
                       """
        ]
      examples: [
        params: {}
        result:
          profile: examples.profileSets.public
      ]

    ,

      id: "profile.updatePublic"
      type: "method"
      title: "Update public profile"
      http: "PUT /profile/public"
      description: """
                   Adds, updates or delete public profile keys. Available to personal accesses.

                   - To add or update a key, just set its value
                   - To delete a key, set its value to `null`

                   Existing keys not included in the update are left untouched.
                   """
      params:
        properties: [
          key: "update"
          type: "object"
          http:
            text: "request body"
          description: """
                       An object with the desired key changes (see above).
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "profile"
          type: "object"
          description: """
                       The updated public profile set.
                       """
        ]
      examples: []

    ,

      id: "profile.getPrivate"
      type: "method"
      title: "Get private profile"
      http: "GET /profile/private"
      description: """
                   Gets the private profile set. Available to personal accesses.
                   """
      result:
        http: "200 OK"
        properties: [
          key: "profile"
          type: "object"
          description: """
                       The private profile set.
                       """
        ]
      examples: []

    ,

      id: "profile.updatePrivate"
      type: "method"
      title: "Update private profile"
      http: "PUT /profile/private"
      description: """
                   Adds, updates or delete private profile keys. Available to personal accesses.

                   - To add or update a key, just set its value
                   - To delete a key, set its value to `null`

                   Existing keys not included in the update are left untouched.
                   """
      result:
        http: "200 OK"
        properties: [
          key: "profile"
          type: "object"
          description: """
                       The updated private profile set.
                       """
        ]
      examples: []
    ]

  ,

    id: "account"
    title: "Account management"
    trustedOnly: true
    description: """
                 Methods to manage the user's account.
                 """
    sections: [
      id: "account.get"
      type: "method"
      title: "Get account information"
      http: "GET /account"
      description: """
                   **(DEPRECATED)** Please use events methods instead.

                   Retrieves the user's account information.
                   """
      result:
        http: "200 OK"
        properties: [
          key: "account"
          type: "[account information](##{dataStructure.getDocId("account")})"
          description: """
                       The user's account information.
                       """
        ]
      examples: [
        params: {}
        result:
          account: _.omit(examples.users.one, "id", "password")
      ]

    ,

      id: "account.update"
      type: "method"
      title: "Update account information"
      http: "PUT /account"
      description: """
                   **(DEPRECATED)** Please use events methods instead.

                   Modifies the user's account information.
                   """
      params:
        properties: [
          key: "update"
          type: "object"
          http:
            text: "request body"
          description: """
                       New values for the account information's fields: see [account information](##{dataStructure.getDocId("account")}). All fields are optional, and only modified values must be included.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "account"
          type: "[account information](##{dataStructure.getDocId("account")})"
          description: """
                       The updated account information.
                       """
        ]
      examples: [
        params:
          email: examples.users.two.email
        result:
          account: _.omit(examples.users.two, "id", "password")

      ]

    ,

      id: "account.changePassword"
      type: "method"
      title: "Change password"
      http: "POST /account/change-password"
      description: """
                   Modifies the user's password.
                   Enforces password complexity, reuse and minimum age rules if enabled (set via the corresponding platform settings).
                   """
      params:
        properties: [
          key: "oldPassword"
          type: "string"
          description: """
                       The current password.
                       """
        ,
          key: "newPassword"
          type: "string"
          description: """
                       The new password.
                       """
        ]
      result:
        http: "200 OK"
      errors: [
        key: "invalid-operation"
        http: "400"
        description: """
                     The given password does not match, cannot be changed at this time (if password minimum age rule enabled) or the new password was already used recently (if password reuse rule enabled).
                     """
      ,
        key: "invalid-parameters-format"
        http: "400"
        description: """
                     The new password does not match password complexity rules (if enabled).
                     """
      ]
      examples: [
        params:
          oldPassword: examples.users.one.password
          newPassword: "//\\_.:o0o:._//\\"
        result: {}
      ]

    ,
      id: "account.changeUsername"
      type: "method"
      title: "Change username"
      v2Tag: true
      http: "POST /account/change-username"
      description: """
                   Changes the user's username. Requires a personal access token.

                   Accesses already issued under the previous username keep working: the old name is retained as a routable alias, and the access-info response for those accesses reports the new (current) username. The number of changes a user may perform is capped by the operator (default 2); see Username changes to read the remaining allowance.
                   """
      params:
        properties: [
          key: "newUsername"
          type: "string"
          description: """
                       The new username. Must be available (not used by any account or alias) and not reserved.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "account"
          type: "[account](##{dataStructure.getDocId("account")})"
          description: """
                       The updated account, carrying the new username.
                       """
        ,
          key: "usernameChangesRemaining"
          type: "number"
          description: """
                       How many further username changes the user may perform.
                       """
        ]
      errors: [
        key: "invalid-operation"
        http: "400"
        description: """
                     The new username equals the current one, is reserved, or the per-user change limit has been reached (`data: { usernameChangesUsed, usernameChangesLimit }`).
                     """
      ,
        key: "item-already-exists"
        http: "409"
        description: """
                     The requested username is already taken by another account or alias.
                     """
      ,
        key: "forbidden"
        http: "403"
        description: """
                     The request was not made with a personal access token.
                     """
      ]
      examples: [
        params:
          newUsername: "ada-lovelace"
        result:
          account:
            username: "ada-lovelace"
            email: "ada@pryv.io"
            language: "en"
          usernameChangesRemaining: 1
      ]

    ,
      id: "account.usernameChanges"
      type: "method"
      title: "Username changes"
      v2Tag: true
      http: "GET /account/username-changes"
      description: """
                   Returns how many username changes the user has performed, the operator-configured limit, and how many remain. Requires a personal access token.
                   """
      params:
        properties: []
      result:
        http: "200 OK"
        properties: [
          key: "usernameChangesUsed"
          type: "number"
          description: """
                       How many username changes have already been performed.
                       """
        ,
          key: "usernameChangesLimit"
          type: "number"
          description: """
                       The maximum number of changes allowed (operator setting, default 2).
                       """
        ,
          key: "usernameChangesRemaining"
          type: "number"
          description: """
                       How many further changes the user may perform.
                       """
        ]
      examples: [
        params: {}
        result:
          usernameChangesUsed: 1
          usernameChangesLimit: 2
          usernameChangesRemaining: 1
      ]

    ,

      id: "account.requestPasswordReset"
      type: "method"
      title: "Request password reset"
      http: "POST /account/request-password-reset"
      description: """
                   Requests the resetting of the user's password. An e-mail containing an expiring reset token (e.g. in a link) will be sent to the user.
                   This method requires that the `appId` and `Origin` (or `Referer`) header comply with the [trusted app verification](##{basics.getDocId("trusted-apps-verification")}).
                   """
      params:
        properties: [
          key: "appId"
          type: "string"
          description: """
                       Your app's unique identifier.
                       """
        ]
      result:
        http: "200 OK"
      examples: [
        params:
          appId: "my-app-id"
        result: {}
      ]

    ,

      id: "account.resetPassword"
      type: "method"
      title: "Reset password"
      http: "POST /account/reset-password"
      description: """
                   Resets the user's password, authorizing the request with the given reset token (see [request password reset](##{_getDocId("account", "account.requestPasswordReset")}) ).
                   Enforces password complexity, reuse and minimum age rules if enabled (set via the corresponding platform settings).
                   This method requires that the `appId` and `Origin` (or `Referer`) header comply with the [trusted app verification](##{basics.getDocId("trusted-apps-verification")}).
                   """
      params:
        properties: [
          key: "resetToken"
          type: "string"
          description: """
                       The expiring reset token that was sent to the user after requesting the password reset.
                       """
        ,
          key: "newPassword"
          type: "string"
          description: """
                       The new password.
                       """
        ,
          key: "appId"
          type: "string"
          description: """
                       Your app's unique identifier.
                       """
        ]
      result:
        http: "200 OK"
      errors: [
        key: "invalid-operation"
        http: "400"
        description: """
                     The password cannot be changed at this time (if password minimum age rule enabled), or the new password was already used recently (if password reuse rule enabled).
                     """
      ,
        key: "invalid-parameters-format"
        http: "400"
        description: """
                     The new password does not match password complexity rules (if enabled).
                     """
      ]
      examples: [
        params:
          resetToken: "chtplghfp0000hqjx814u6393"
          newPassword: "Dr0ws$4p"
          appId: "my-app-id"
        result: {}
      ]
    ]
  ,

    id: "delegations"
    title: "Account delegation"
    v2Tag: true
    description: """
                 Methods to manage account delegation: letting one account (a *delegate*, e.g. a parent or guardian) control another (a *controlled account*, e.g. a child or dependent).

                 A controlled account invites a delegate with [invite a delegate](##{_getDocId("delegations", "delegations.requestAttach")}); the delegate accepts with [accept a delegation](##{_getDocId("delegations", "delegations.acceptAttach")}). A delegate may also create a controlled account outright with [create a controlled account](##{_getDocId("delegations", "delegations.createAccount")}), and obtain a delegate access token for an active relationship with [get a delegate token](##{_getDocId("delegations", "delegations.getToken")}). A delegate token is a personal-class token that can do everything on the controlled account **except** remove a delegation: removing a delegation (detach, cancel invite) requires a *genuine* direct login on the controlled account, never a delegated session. See the [Account delegation guide](/guides/account-delegation/).

                 Requires the `delegation:active` platform setting (default on). All methods below require a personal access token; the genuine-login-only methods additionally reject delegate tokens. A set of internal core-to-core endpoints under `/delegations/controlled-side/*` handles cross-core handshake delivery and token issuance; they are authorized by plugin-minted marker credentials and are not called directly by clients.
                 """
    sections: [
      id: "delegations.requestAttach"
      type: "method"
      title: "Invite a delegate"
      v2Tag: true
      http: "POST /delegations/attach-request"
      description: """
                   Called by a controlled account to invite another account to become its delegate. Creates a pending invite the delegate can accept with [accept a delegation](##{_getDocId("delegations", "delegations.acceptAttach")}). Requires a personal access token.
                   """
      params:
        properties: [
          key: "delegateUsername"
          type: "string"
          description: """
                       The username of the account being invited to control this one.
                       """
        ]
      result:
        http: "201 Created"
        properties: [
          key: "delegation"
          type: "object"
          description: """
                       The created relationship: `relId`, `delegate` (`{ username }`), `status` (`"invite"`), and the `requestedAt` / `expiresAt` Unix timestamps.
                       """
        ]
      errors: [
        key: "delegation-unknown-username"
        http: "404"
        description: """
                     The delegate account does not exist.
                     """
      ,
        key: "delegation-self-not-allowed"
        http: "400"
        description: """
                     An account may not delegate to itself.
                     """
      ,
        key: "delegation-already-exists"
        http: "409"
        description: """
                     A pending or active delegation to this delegate already exists.
                     """
      ,
        key: "delegation-delivery-failed"
        http: "503"
        description: """
                     The invite could not be delivered to the delegate's core.
                     """
      ]
      examples: [
        params:
          delegateUsername: "parent"
        result:
          delegation:
            relId: "ckz3n8x7k0000qzrmf9a1b2c3"
            delegate:
              username: "parent"
            status: "invite"
            requestedAt: 1631000000
            expiresAt: 1633592000
      ]

    ,

      id: "delegations.acceptAttach"
      type: "method"
      title: "Accept a delegation"
      v2Tag: true
      http: "POST /delegations/controlled/{controlled}/accept"
      description: """
                   Called by an invited delegate to accept a pending delegation from the controlled account `{controlled}`. Idempotent: re-accepting an already active relationship returns the settled record. Requires a personal access token.
                   """
      params:
        properties: [
          key: "controlled"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       The username of the controlled account whose invite is being accepted.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "delegation"
          type: "object"
          description: """
                       The now-active relationship: `relId`, `controlled` (`{ username, hostSlug }`), `status` (`"active"`) and `activatedAt`.
                       """
        ]
      errors: [
        key: "delegation-not-found"
        http: "404"
        description: """
                     No pending invite from that controlled account.
                     """
      ,
        key: "delegation-invite-expired"
        http: "410"
        description: """
                     The invite has expired or is no longer valid on the controlled account.
                     """
      ,
        key: "delegation-delivery-failed"
        http: "503"
        description: """
                     The controlled account's core could not be reached to confirm activation.
                     """
      ]
      examples: [
        params:
          controlled: "childaccount"
        result:
          delegation:
            relId: "ckz3n8x7k0000qzrmf9a1b2c3"
            controlled:
              username: "childaccount"
              hostSlug: "pryv-me"
            status: "active"
            activatedAt: 1631000500
      ]

    ,

      id: "delegations.refuseAttach"
      type: "method"
      title: "Refuse a delegation"
      v2Tag: true
      http: "POST /delegations/controlled/{controlled}/refuse"
      description: """
                   Called by an invited delegate to decline a pending delegation from the controlled account `{controlled}`. Requires a personal access token.
                   """
      params:
        properties: [
          key: "controlled"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       The username of the controlled account whose invite is being refused.
                       """
        ]
      result:
        http: "200 OK"
      errors: [
        key: "delegation-not-found"
        http: "404"
        description: """
                     No pending invite from that controlled account.
                     """
      ]
      examples: [
        params:
          controlled: "childaccount"
        result: {}
      ]

    ,

      id: "delegations.cancelInvite"
      type: "method"
      title: "Cancel a sent invite"
      v2Tag: true
      http: "POST /delegations/delegates/{delegate}/cancel"
      description: """
                   Called by a controlled account to cancel a pending invite it sent to `{delegate}`. Because cancelling removes a relationship record, it requires a *genuine* direct login on the controlled account: a delegate token is refused.
                   """
      params:
        properties: [
          key: "delegate"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       The username of the invited delegate whose pending invite is being cancelled.
                       """
        ]
      result:
        http: "200 OK"
      errors: [
        key: "delegation-genuine-login-required"
        http: "403"
        description: """
                     The request used a delegate (or non-personal) token. A genuine login on the controlled account is required.
                     """
      ]
      examples: [
        params:
          delegate: "parent"
        result: {}
      ]

    ,

      id: "delegations.listDelegates"
      type: "method"
      title: "List delegates"
      v2Tag: true
      http: "GET /delegations/delegates"
      description: """
                   Lists the delegates that control this account (from the controlled account's view). Requires a personal access token.
                   """
      result:
        http: "200 OK"
        properties: [
          key: "delegates"
          type: "array of objects"
          description: """
                       One entry per delegate: `relId`, `delegate` (`{ username, hostSlug }`), `status` (`"invite"` | `"active"` | `"stale"`), `requestedAt`, `activatedAt` and `lastTokenIssuedAt`.
                       """
        ]
      examples: [
        params: {}
        result:
          delegates: [
            relId: "ckz3n8x7k0000qzrmf9a1b2c3"
            delegate:
              username: "parent"
              hostSlug: "pryv-me"
            status: "active"
            requestedAt: 1631000000
            activatedAt: 1631000500
            lastTokenIssuedAt: 1631004000
          ]
      ]

    ,

      id: "delegations.listControlled"
      type: "method"
      title: "List controlled accounts"
      v2Tag: true
      http: "GET /delegations/controlled"
      description: """
                   Lists the accounts this account controls as a delegate (from the delegate's view). Requires a personal access token.
                   """
      result:
        http: "200 OK"
        properties: [
          key: "controlled"
          type: "array of objects"
          description: """
                       One entry per controlled account: `relId`, `controlled` (`{ username, hostSlug }`), `status` (`"invite"` | `"active"` | `"stale"`), `requestedAt` and `activatedAt`.
                       """
        ]
      examples: [
        params: {}
        result:
          controlled: [
            relId: "ckz3n8x7k0000qzrmf9a1b2c3"
            controlled:
              username: "childaccount"
              hostSlug: "pryv-me"
            status: "active"
            requestedAt: 1631000000
            activatedAt: 1631000500
          ]
      ]

    ,

      id: "delegations.createAccount"
      type: "method"
      title: "Create a controlled account"
      v2Tag: true
      http: "POST /delegations/controlled"
      description: """
                   Called by a delegate to create a brand-new controlled account, active from birth, with this account as its delegate. The new account has no email and no usable password unless supplied, so it is reachable only through its delegates until someone sets real credentials. On a multi-core platform the target core defaults to the delegate's own core. Requires a personal access token.
                   """
      params:
        properties: [
          key: "username"
          type: "string"
          description: """
                       The username for the new controlled account. Must be available and not reserved.
                       """
        ,
          key: "email"
          type: "string"
          optional: true
          description: """
                       Optional e-mail address for the new account.
                       """
        ,
          key: "password"
          type: "string"
          optional: true
          description: """
                       Optional password. When omitted, the account has no usable password and is reachable only via its delegates until one is set.
                       """
        ,
          key: "core"
          type: "string"
          optional: true
          description: """
                       Optional target core (its id or URL) on a multi-core platform. Defaults to the delegate's own core.
                       """
        ,
          key: "language"
          type: "string"
          optional: true
          description: """
                       Optional two-letter language code for the new account.
                       """
        ]
      result:
        http: "201 Created"
        properties: [
          key: "delegation"
          type: "object"
          description: """
                       The active relationship to the new account: `relId`, `controlled` (`{ username, hostSlug }`), `status` (`"active"`) and `activatedAt`.
                       """
        ]
      errors: [
        key: "delegation-unknown-username"
        http: "400"
        description: """
                     A username for the new account is required.
                     """
      ,
        key: "delegation-self-not-allowed"
        http: "400"
        description: """
                     An account may not delegate to itself.
                     """
      ,
        key: "delegation-unknown-core"
        http: "400"
        description: """
                     The requested target core is unknown to this platform.
                     """
      ,
        key: "delegation-username-taken"
        http: "409"
        description: """
                     The requested username is already taken.
                     """
      ,
        key: "delegation-creation-failed"
        http: "502"
        description: """
                     The target core could not create the account.
                     """
      ]
      examples: [
        params:
          username: "childaccount"
          language: "en"
        result:
          delegation:
            relId: "ckz3n8x7k0000qzrmf9a1b2c3"
            controlled:
              username: "childaccount"
              hostSlug: "pryv-me"
            status: "active"
            activatedAt: 1631000500
      ]

    ,

      id: "delegations.getToken"
      type: "method"
      title: "Get a delegate token"
      v2Tag: true
      http: "POST /delegations/controlled/{controlled}/token"
      description: """
                   Called by a delegate to obtain a delegate access token for an active controlled account `{controlled}`. The returned token is a personal-class token over the controlled account, and its `apiEndpoint` points at the controlled account's core so the delegate's client talks to that core directly. Re-issuing while the session is alive returns the same token. Requires a personal access token.
                   """
      params:
        properties: [
          key: "controlled"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       The username of the active controlled account to get a token for.
                       """
        ]
      result:
        http: "200 OK"
        properties: [
          key: "token"
          type: "string"
          description: """
                       The delegate access token (a personal-class token over the controlled account).
                       """
        ,
          key: "apiEndpoint"
          type: "string"
          description: """
                       The controlled account's API endpoint (token embedded), to be used directly against its core.
                       """
        ]
      errors: [
        key: "delegation-not-found"
        http: "404"
        description: """
                     No delegation relationship with that controlled account.
                     """
      ,
        key: "delegation-not-active"
        http: "410"
        description: """
                     The relationship is not active (for example it was detached on the controlled account).
                     """
      ,
        key: "delegation-delivery-failed"
        http: "503"
        description: """
                     The controlled account's core could not be reached to issue a token.
                     """
      ]
      examples: [
        params:
          controlled: "childaccount"
        result:
          token: "cwyz8k2p90000356mexampletok"
          apiEndpoint: "https://cwyz8k2p90000356mexampletok@childaccount.pryv.me/"
      ]

    ,

      id: "delegations.detachDelegate"
      type: "method"
      title: "Detach a delegate"
      v2Tag: true
      http: "DELETE /delegations/delegates/{delegate}"
      description: """
                   Called by a controlled account to remove a delegate `{delegate}`. This is the authoritative teardown: it kills the delegate's token and control access on this account, then best-effort notifies the delegate; a still-pending invite is cancelled instead. Because it removes a delegation relationship, it requires a *genuine* direct login on the controlled account: a delegate token is refused.
                   """
      params:
        properties: [
          key: "delegate"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       The username of the delegate to detach.
                       """
        ]
      result:
        http: "200 OK"
      errors: [
        key: "delegation-genuine-login-required"
        http: "403"
        description: """
                     The request used a delegate (or non-personal) token. A genuine login on the controlled account is required to remove a delegation.
                     """
      ,
        key: "delegation-not-found"
        http: "404"
        description: """
                     No delegation relationship with that delegate.
                     """
      ]
      examples: [
        params:
          delegate: "parent"
        result: {}
      ]

    ,

      id: "delegations.dismissControlled"
      type: "method"
      title: "Dismiss a stale controlled entry"
      v2Tag: true
      http: "DELETE /delegations/controlled/{controlled}"
      description: """
                   Called by a delegate to remove a `stale` controlled-account entry from its own list (local housekeeping after the relationship ended on the controlled account). This removes no authority and never touches the controlled account. Only a `stale` entry may be dismissed. Requires a personal access token.
                   """
      params:
        properties: [
          key: "controlled"
          type: "string"
          http:
            text: "set in request path"
          description: """
                       The username of the controlled account entry to dismiss.
                       """
        ]
      result:
        http: "200 OK"
      errors: [
        key: "delegation-not-found"
        http: "404"
        description: """
                     No delegation relationship with that controlled account.
                     """
      ,
        key: "delegation-mirror-not-stale"
        http: "409"
        description: """
                     The relationship is still invite or active; only a stale entry can be dismissed.
                     """
      ]
      examples: [
        params:
          controlled: "childaccount"
        result: {}
      ]
    ]
  ]

# Returns the in-doc id of the given method, for safe linking from other doc sections
exports.getDocId = (methodId) ->
  result = null
  exports.sections.forEach((section) ->
    methodSection = _.find(section.sections, (subSection) -> subSection.id == methodId)
    if methodSection
      result = helpers.getDocId(exports.id, section.id, methodId)
  )
  return result || throw new Error("Unknown method id")
