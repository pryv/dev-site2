# Frozen example error payload. Previously derived from the core error factory
# (errorHandling.getPublicErrorData(errors.invalidAccessToken(...))); inlined here
# as a literal so the reference source has no dependency on the API server code.
module.exports =
  invalidAccessToken:
    id: "invalid-access-token"
    message: "Cannot find access with token 'bad-token'."
