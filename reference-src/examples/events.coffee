timestamp = require("unix-timestamp")
generateId = require("cuid")
accesses = require("./accesses")
streams = require("./streams")

generateReadToken = () ->
  hash = "";
  dictionnary = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

  for i in [1 .. 27]
    hash += dictionnary.charAt(Math.floor(Math.random() * dictionnary.length));
  return generateId() + '-' + hash

module.exports =
  activity:
    id: generateId()
    time: timestamp.now()
    streamIds: [ streams.activities[0].children[0].id ]
    streamId: streams.activities[0].children[0].id
    tags: []
    type: "activity/plain"
    content: null
    integrity: "EVENT:0:sha256-ieAsdy44tr0o/9aFEdbzVTRVzzZEVYDUDLSfTMQsHUU="
    created: timestamp.now()
    createdBy: accesses.app.id
    modified: timestamp.now()
    modifiedBy: accesses.app.id

  activityRunning:
    id: generateId()
    time: timestamp.now()
    duration: null
    streamIds: [ streams.activities[0].children[1].id ]
    streamId: streams.activities[0].children[1].id
    tags: []
    type: "activity/plain"
    content: null
    integrity: "EVENT:0:sha256-ieAsdy44tr0o/9aFEdbzVTRVzzZEVYDUDLSfTMQsHUU="
    created: timestamp.now()
    createdBy: accesses.app.id
    modified: timestamp.now()
    modifiedBy: accesses.app.id

  activityAttachment:
    id: generateId()
    time: timestamp.now()
    duration: null
    streamIds: [ streams.activities[1].children[1].id ]
    streamId: streams.activities[1].children[1].id
    tags: []
    type: "activity/plain"
    content: null
    attachments: [
      id: generateId()
      fileName: "travel-expense.jpg"
      type: "image/jpeg"
      size: 1111
      readToken: generateReadToken()
      integrity: "sha256-JhFVUp+6GmF4xApi6dZrNroSrunAWl4R0ocXi8bjF1U="
    ]
    integrity: "EVENT:0:sha256-ieAsdy44tr0o/9aFEdbzVTRVzzZEVYDUDLSfTMQsHUU="
    created: timestamp.now()
    createdBy: accesses.app.id
    modified: timestamp.now()
    modifiedBy: accesses.app.id

  heartRate:
    id: generateId()
    time: 1385046854.282,
    streamIds: [ "heart" ]
    streamId: "heart"
    tags: []
    type: "frequency/bpm"
    content: 90
    integrity: "EVENT:0:sha256-ieAsdy44tr0o/9aFEdbzVTRVzzZEVYDUDLSfTMQsHUU="
    created: timestamp.now()
    createdBy: accesses.app.id
    modified: timestamp.now()
    modifiedBy: accesses.app.id

  mass:
    id: generateId()
    time: timestamp.now()
    streamIds: [ streams.health[0].children[2].id ]
    streamId: streams.health[0].children[2].id
    tags: []
    type: "mass/kg"
    content: 90
    integrity: "EVENT:0:sha256-ieAsdy44tr0o/9aFEdbzVTRVzzZEVYDUDLSfTMQsHUU="
    created: timestamp.now()
    createdBy: accesses.app.id
    modified: timestamp.now()
    modifiedBy: accesses.app.id

  note:
    id: generateId()
    time: timestamp.now('-1h')
    streamIds: [ streams.diary[0].id ]
    streamId: streams.diary[0].id
    tags: []
    type: "note/text"
    content: "道可道非常道。。。"
    integrity: "EVENT:0:sha256-ieAsdy44tr0o/9aFEdbzVTRVzzZEVYDUDLSfTMQsHUU="
    created: timestamp.now('-1h')
    createdBy: accesses.app.id
    modified: timestamp.now('+10h')
    modifiedBy: accesses.app.id

  noteWithHistory:
    id: generateId()
    time: timestamp.now('-1h')
    streamIds: [ streams.diary[0].id ]
    streamId: streams.diary[0].id
    tags: []
    type: "note/text"
    content: "Hi, I am the latest version of this event"
    integrity: "EVENT:0:sha256-ieAsdy44tr0o/9aFEdbzVTRVzzZEVYDUDLSfTMQsHUU="
    created: timestamp.now('-1h')
    createdBy: accesses.app.id
    modified: timestamp.now('+2h')
    modifiedBy: accesses.app.id

  noteHistory1:
    id: generateId()
    time: timestamp.now('-1h')
    streamIds: [ streams.diary[0].id ]
    streamId: streams.diary[0].id
    tags: []
    type: "note/text"
    content: "Hi, I am the first modification"
    integrity: "EVENT:0:sha256-ieAsdy44tr0o/9aFEdbzVTRVzzZEVYDUDLSfTMQsHUU="
    created: timestamp.now('-1h')
    createdBy: accesses.app.id
    modified: timestamp.now('+1h')
    modifiedBy: accesses.app.id

  noteHistory2:
    id: generateId()
    time: timestamp.now('-1h')
    streamIds: [ streams.diary[0].id ]
    streamId: streams.diary[0].id
    tags: []
    type: "note/text"
    content: "Hi, I was the initial event"
    integrity: "EVENT:0:sha256-ieAsdy44tr0o/9aFEdbzVTRVzzZEVYDUDLSfTMQsHUU="
    created: timestamp.now('-1h')
    createdBy: accesses.app.id
    modified: timestamp.now('0h')
    modifiedBy: accesses.app.id

  picture:
    id: generateId()
    time: timestamp.now('-1h')
    streamIds: [ streams.diary[0].id ]
    streamId: streams.diary[0].id
    tags: []
    type: "picture/attached"
    content: null
    attachments: [
      id: generateId()
      fileName: "photo.jpg"
      type: "image/jpeg"
      size: 2561
      readToken: generateReadToken()
      integrity: "sha256-JhFVUp+6GmF4xApi6dZrNroSrunAWl4R0ocXi8bjF1U="
    ]
    integrity: "EVENT:0:sha256-ieAsdy44tr0o/9aFEdbzVTRVzzZEVYDUDLSfTMQsHUU="
    created: timestamp.now('-1h')
    createdBy: accesses.shared.id
    modified: timestamp.now('-1h')
    modifiedBy: accesses.shared.id

  position:
    id: generateId()
    time: 1350373077.359
    streamIds: [ streams.diary[0].id ]
    streamId: streams.diary[0].id
    tags: []
    type: "position/wgs84"
    content:
      latitude: 40.714728
      longitude: -73.998672
    integrity: "EVENT:0:sha256-ieAsdy44tr0o/9aFEdbzVTRVzzZEVYDUDLSfTMQsHUU="
    created: timestamp.now('-2h')
    createdBy: accesses.personal.id
    modified: timestamp.now('-2h')
    modifiedBy: accesses.personal.id

  running:
    id: generateId()
    time: timestamp.now('-1h')
    streamIds: [ "running", "health" ]
    streamId: "running" 
    tags: []
    type: "activity/plain"
    content: null
    integrity: "EVENT:0:sha256-ieAsdy44tr0o/9aFEdbzVTRVzzZEVYDUDLSfTMQsHUU="
    created: timestamp.now('-1h')
    createdBy: accesses.shared.id
    modified: timestamp.now('-1h')
    modifiedBy: accesses.shared.id

  vegetablesEaten:
    id: generateId()
    time: timestamp.now('-3h')
    streamIds: [ "vegetables", "health" ]
    streamId: "vegetables" 
    tags: []
    type: "mass/kg"
    content: 350
    integrity: "EVENT:0:sha256-ieAsdy44tr0o/9aFEdbzVTRVzzZEVYDUDLSfTMQsHUU="
    created: timestamp.now('-3h')
    createdBy: accesses.shared.id
    modified: timestamp.now('-3h')
    modifiedBy: accesses.shared.id

  series:
    position:
      format: "flatJSON", 
      fields: ["deltaTime", "latitude", "longitude", "altitude"], 
      points: [
        [0, 10.2, 11.2, 500], 
        [1, 10.2, 11.2, 510],
        [2, 10.2, 11.2, 520],
      ]
    mass:
      format: "flatJSON", 
      fields: ["deltaTime", "value"], 
      points: [
        [0, 70], 
        [1, 71],
        [2, 72],
      ]
    holderEvent:
      id: generateId()
      time: timestamp.now()
      streamIds: [ "position" ]
      streamId: "position"
      tags: []
      type: "series:position/wgs84"
      content:
        elementType: "position/wgs84",
        fields: [
          "deltaTime",
          "latitude",
          "longitude",
          "altitude",
          "horizontalAccuracy",
          "verticalAccuracy",
          "speed",
          "bearing"
        ],
        required: [
          "deltaTime",
          "latitude",
          "longitude"
        ]
      created: timestamp.now()
      createdBy: accesses.app.id
      modified: timestamp.now()
      modifiedBy: accesses.app.id
    batch:
      format: "seriesBatch"
      data: [
        eventId: generateId()
        data:
          format: "flatJSON", 
          fields: ["deltaTime", "value"], 
          points: [
            [0, 70], 
            [1, 71],
            [2, 72],
          ]
      ,
        eventId: generateId()
        data:
          format: "flatJSON", 
          fields: ["deltaTime", "latitude", "longitude", "altitude"], 
          points: [
            [0, 10.2, 11.2, 500], 
            [2, 10.2, 11.2, 510],
            [1, 10.2, 11.2, 520],
          ]
      ]