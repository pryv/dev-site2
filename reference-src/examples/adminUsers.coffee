generateId = require("cuid")
register = require("./register")

module.exports =
  admin:
    username: "admin",
    permissions:
      users: [
        "read",
        "create",
        "delete",
        "resetPassword",
        "changePermissions"
      ],
      settings: ["read", "update"],
      platformUsers: ["read", "delete"]
  ,
  harrytasker:
    username: "harrytasker",
    permissions: 
      users: [
        "read",
      ],
      settings: ["read", "update"],
      platformUsers: ["read", "delete"]
    