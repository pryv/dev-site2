generateId = require("cuid")
timestamp = require("unix-timestamp")
helpers = require("../helpers")

idPersonal = generateId()
idApp = generateId()

accesses =
  personal:
    id: idPersonal
    token: generateId()
    type: "personal"
    integrity: "ACCESS:0:sha256-PHrsNNRauGOQV7YUeCo/HP21EugCbYkv/laykaWw9RE="
    created: timestamp.now('-1M')
    createdBy: "system"
    modified: timestamp.now('-1w')
    modifiedBy: "system"

  app:
    id: idApp
    token: generateId()
    type: "app"
    name: "my-app-id"
    permissions: [
      streamId: "health"
      level: "contribute"
    ]
    integrity: "ACCESS:0:sha256-PHrsNNRauGOQV7YUeCo/HP21EugCbYkv/laykaWw9RE="
    created: timestamp.now('-1d')
    createdBy: idPersonal
    modified: timestamp.now('-1d')
    modifiedBy: idPersonal

  shared:
    id: generateId()
    token: generateId()
    type: "shared"
    name: "Arthur"
    permissions: [
      streamId: "family"
      level: "contribute"
    ]
    integrity: "ACCESS:0:sha256-PHrsNNRauGOQV7YUeCo/HP21EugCbYkv/laykaWw9RE="
    created: timestamp.now('-12h')
    createdBy: idApp
    modified: timestamp.now('-12h')
    modifiedBy: idApp

  sharedNew:
    id: generateId()
    token: generateId()
    type: "shared"
    name: "For colleagues"
    permissions: [
      streamId: "work"
      level: "read"
    ]
    integrity: "ACCESS:0:sha256-PHrsNNRauGOQV7YUeCo/HP21EugCbYkv/laykaWw9RE="
    created: timestamp.now()
    createdBy: idApp
    modified: timestamp.now()
    modifiedBy: idApp

  deleted:
    id: generateId()
    token: generateId()
    type: "shared"
    name: "Health parameters survey"
    permissions: [
      streamId: "health"
      level: "read"
    ]
    integrity: "ACCESS:0:sha256-PHrsNNRauGOQV7YUeCo/HP21EugCbYkv/laykaWw9RE="
    created: timestamp.now('-2m')
    createdBy: idApp
    modified: timestamp.now('-2m')
    modifiedBy: idApp
    deleted: timestamp.now('-1m')

  info:
    id: generateId()
    token: generateId()
    type: "app"
    name: "Current access"
    deviceName: "My awesome device"
    permissions: [
      streamId: "health"
      level: "read"
    ]
    user:
      username: "jackslater"
    lastUsed: timestamp.now('-5m')
    expires: timestamp.now('-2m')
    deleted: timestamp.now('-1m')
    clientData: {
      consent: "My custom consent message."
    }
    created: timestamp.now('-2m')
    createdBy: idApp
    modified: timestamp.now('-2m')
    modifiedBy: idApp
    calls:
      getAccessInfo:	12
      'profile:get':	5
      'events:get':	12
      'streams:get':	11
      'accesses:get':	6

  createOnly:
    id: generateId()
    token: "mailbox"
    type: "shared"
    name: "publicly available token"
    permissions: [
      streamId: "inbox"
      level: "create-only"
    ,
      feature: "selfRevoke"
      setting: "forbidden"
    ]
    integrity: "ACCESS:0:sha256-PHrsNNRauGOQV7YUeCo/HP21EugCbYkv/laykaWw9RE="
    created: timestamp.now('-1d')
    createdBy: idPersonal
    modified: timestamp.now('-1d')
    modifiedBy: idPersonal

for key, a of accesses
  a.apiEndpoint = helpers.getApiEndpoint(a.token, "user1")

module.exports = accesses
