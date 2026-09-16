timestamp = require("unix-timestamp")
generateId = require("cuid")

module.exports = [
  id: generateId()
  deleted: timestamp.now('-1h')
,
  id: generateId()
  deleted: timestamp.now('-10h')
,
  id: generateId()
  deleted: timestamp.now('-20h')
]