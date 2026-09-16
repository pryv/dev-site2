timestamp = require("unix-timestamp")
generateId = require("cuid")

firstId = generateId();
secondId = generateId();

module.exports = exports =
  simple: 
    id: generateId()
    accessId: firstId
    url: 'https://notifications.service.com/pryv'
    minIntervalMs: 5000
    maxRetries: 5
    currentRetries: 0
    state: 'active'
    runCount: 2
    failCount: 0
    lastRun:
      status: 200,
      timestamp: timestamp.now('-1h')
    runs: [
      status: 200
      timestamp: timestamp.now('-1h')
    ,
      status: 200
      timestamp: timestamp.now('-2h')
    ]
    created: timestamp.now('-1d')
    createdBy: firstId
    modified: timestamp.now('-1d')
    modifiedBy: firstId
  hasFailed:
    id: generateId()
    accessId: firstId
    url: 'https://notifications.pryv.me/myusername/ui3HDAw43'
    minIntervalMs: 5000
    maxRetries: 5
    state: 'active'
    currentRetries: 0
    runCount: 5
    failCount: 5
    lastRun: 
      status: 404
      timestamp: timestamp.now('-15s')
    runs: [
      status: 404
      timestamp: timestamp.now('-15s')
    ,
      status: 404
      timestamp: timestamp.now('-55s')
    ,
      status: 404
      timestamp: timestamp.now('-1m15s')
    ,
      status: 404
      timestamp: timestamp.now('-1m25s')
    ,
      status: 404
      timestamp: timestamp.now('-1m30s')
    ]
  failing:
    id: generateId()
    accessId: firstId
    url: 'https://notifications.pryv.me/webhooks'
    minIntervalMs: 5000
    maxRetries: 5
    currentRetries: 2
    state: 'active'
    runCount: 8
    failCount: 2
    lastRun:
      status: 200,
      timestamp: timestamp.now('-5s')
    runs: [
      status: 500
      timestamp: timestamp.now('-5s')
    ,
      status: 500
      timestamp: timestamp.now('-10s')
    ,
      status: 200
      timestamp: timestamp.now('-10m')
    ,
      status: 200
      timestamp: timestamp.now('-20m')
    ,
      status: 200
      timestamp: timestamp.now('-30m')
    ,
      status: 200
      timestamp: timestamp.now('-40m')
    ,
      status: 200
      timestamp: timestamp.now('-50m')
    ,
      status: 200
      timestamp: timestamp.now('-1h')
    ]
    created: timestamp.now('-2d')
    createdBy: firstId
    modified: timestamp.now('-2d')
    modifiedBy: firstId
  new:
    id: generateId()
    accessId: secondId
    url: 'https://sievey.io/webhooks'
    minIntervalMs: 5000,
    maxRetries: 5,
    currentRetries: 0
    state: 'active'
    runCount: 0
    failCount: 0
    lastRun: {}
    runs: []
    scopes:
      newReadings:
        kind: 'events'
        query:
          streams: ['measurements']
          types: ['mass/kg']
      structure:
        kind: 'streams'
        query:
          streams: ['measurements']
    created: timestamp.now('-5s')
    createdBy: secondId
    modified: timestamp.now('-5s')
    modifiedBy: secondId
  inactive:
    id: generateId()
    accessId: secondId
    url: 'https://notifications.mancuso.org/webhooks'
    minIntervalMs: 5000,
    maxRetries: 5,
    currentRetries: 5
    state: 'inactive'
    runCount: 5
    failCount: 5
    lastRun:
      status: 500,
      timestamp: timestamp.now('-5s')
    runs: [
      status: 500
      timestamp: timestamp.now('-5s')
    ,
      status: 500
      timestamp: timestamp.now('-10s')
    ,
      status: 500
      timestamp: timestamp.now('-15s')
    ,
      status: 500
      timestamp: timestamp.now('-20s')
    ,
      status: 500
      timestamp: timestamp.now('-25s')
    ]
    created: timestamp.now('-1d')
    createdBy: secondId
    modified: timestamp.now('-1d')
    modifiedBy: secondId
  
