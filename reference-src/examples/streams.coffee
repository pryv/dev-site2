timestamp = require("unix-timestamp")
generateId = require("cuid")
accesses = require("./accesses")

idA = generateId()
idB = generateId()

module.exports = exports =
  activities: [
    id: "sport"
    name: "Sport"
    parentId: null
    children: [
      id: "jogging"
      name: "Jogging"
      parentId: "sport"
      children: []
    ,
      id: "bicycling"
      name: "Bicycling"
      parentId: "sport"
      children: []
    ]
  ,
    id: "work"
    name: "Work"
    parentId: null
    children: [
      id: idA
      name: "Noble Works Co."
      parentId: "work"
      children: [
        id: generateId()
        name: "Last Be First"
        parentId: idA
        children: []
      ,
        id: generateId()
        name: "Big Tree"
        parentId: idA
        children: []
      ,
        id: generateId()
        name: "Inner Light"
        parentId: idA
        children: []
      ]
    ,
      id: idB
      name: "Freelancing"
      parentId: "work"
      children: [
        id: generateId()
        name: "Funky Veggies"
        parentId: idB
        children: []
      ,
        id: generateId()
        name: "Jojo Lapin & sons"
        parentId: idB
        children: []
      ]
    ]
  ]

  diary: [
    id: "diary"
    name: "Diary"
    parentId: null
    children: []
  ]

  family: [
    id: "family"
    name: "Family"
    parentId: null
    children: [
      id: generateId()
      name: "Anne"
      parentId: "family"
      children: []
    ,
      id: generateId()
      name: "Arthur"
      parentId: "family"
      children: []
    ,
      id: generateId()
      name: "Beni"
      parentId: "family"
      children: []
    ,
      id: generateId()
      name: "Luisa"
      parentId: "family"
      children: []
    ]
  ]

  health: [
    id: "health"
    name: "Health"
    parentId: null
    children: [
      id: "heart"
      name: "Heart"
      parentId: "health"
      children: []
    ,
      id: "blood"
      name: "Blood"
      parentId: "health"
      children: []
    ,
      id: "weight"
      name: "Weight"
      parentId: "health"
      children: []
    ]
  ]

  healthSubstreams: [
    id: "white-cells"
    name: "White cells"
    parentId: "blood"
    children: []
    created: timestamp.now()
    createdBy: accesses.app.id
    modified: timestamp.now()
    modifiedBy: accesses.app.id
  ,
    id: "heart"
    name: "Heart",
    parentId: "health",
    children: []
    created: timestamp.now()
    createdBy: accesses.app.id
    modified: timestamp.now()
    modifiedBy: accesses.app.id
  ]

addTrackingProperties = (time, accessId, stream) ->
  stream.created ?= time
  stream.createdBy ?= accessId
  stream.modified ?= time + Math.random() * 365
  stream.modifiedBy ?= accessId
  stream.children.forEach(addTrackingProperties.bind(null, time + Math.random() * 30, accessId))
Object.keys(exports).forEach((key) ->
  exports[key].forEach(addTrackingProperties.bind(null, timestamp.now('-2y'), accesses.personal.id))
)
