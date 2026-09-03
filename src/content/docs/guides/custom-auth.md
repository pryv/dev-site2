---
title: 'Custom Authentication'
description: How to add a custom authentication step to your Pryv.io platform to validate API requests against extra information or an external service.
---


## Table of contents <!-- omit in toc -->
<!-- no toc -->
1. [Introduction](#introduction)
2. [Pryv.io Custom Auth Step](#pryv-io-custom-auth-step)
  1. [Why using a custom auth step](#why-using-a-custom-auth-step)
  2. [What is the custom auth step](#what-is-the-custom-auth-step)
  3. [How to set up the custom auth step](#how-to-set-up-the-custom-auth-step)
3. [Authenticate data access with Pryv.io](#authenticate-data-access-with-pryv-io)
  1. [Hands-on example](#hands-on-example)
  2. [Custom authentication function](#custom-authentication-function)
4. [Custom Auth Step features](#custom-auth-step-features)
5. [Authenticate data access with an external service](#authenticate-data-access-with-an-external-service)


## Introduction

Authentication allows you to validate the identity of a registered user attempting to access resources. You can add a custom authentication step to your Pryv.io platform to verify more information than the authorization token when performing a request to access data.  

In this guide, we explain how to provide your Pryv.io platform with this feature and illustrate it with a concrete use case. 

## Pryv.io Custom Auth Step

### Why using a custom auth step

A custom auth step is necessary when you wish to authenticate your Pryv.io API requests or authorize them against another web service. A possible use case can be to verify the identity of the person using the authorization token you have provided him or her with.  
In this case, you would append a second token to the `Authorization` header after the Pryv.io token separated by a whitespace.

For example, if a Alice needs to access data from Bob in your Pryv.io platform, you can implement an authentication step that will allow you to verify the identity of user Alice when she tries to access data from Bob. The identity of the data client (Alice) can be verified through a custom auth step that you can add to your Pryv.io platform as explained below.

### What is the custom auth step

You can define a function that will be run by Pryv.io after the authorization token verification.  
In this function, you have access to the fields described below, as well as the [NodeJS core modules](https://nodejs.org/docs/latest-v12.x/api/documentation.html):

- `username` (string)  
- `user` (object): the user object (properties include `id`)  
- `accessToken` (string): as read in the `Authorization` header or `auth` parameter  
- `callerId` (string): optional additional id passed after `accessToken` in the `Authorization` header after a separating space (header format is thus `[<access-token> <caller-id>]`)  
- `access` (object): the access object (see [API doc](https://pryv.github.io/reference/#access))  

```javascript
// Example of customAuthStepFn.js
module.exports = function (context, callback) {
  // do whatever is needed here (check LDAP, custom DB, etc.)
  performCustomValidation(context, function (err) {
    if (err) { return callback(err); }
    callback();
  });
};
```

### How to set up the custom auth step

> **Since v2 (2026)** the custom auth step is wired up directly through the unified config file — there is no admin-panel GUI in v2.

Drop your `customAuthStepFn.js` (an example body is given in [What is the custom auth step](#what-is-the-custom-auth-step) above) somewhere on each core, then set the two `customExtensions.*` keys in `override-config.yml`:

```yaml
customExtensions:
  defaultFolder: /etc/pryv/extensions   # absolute path; folder must exist on every core
  customAuthStepFn: customAuthStepFn.js # filename only, resolved against defaultFolder
```

Restart the core (`systemctl restart open-pryv` or your operator's equivalent) for the function to be loaded. Each core in a multi-core cluster needs the same file at the same path — keep them in sync via your configuration-management tool.

#### v1 procedure (legacy)

Pryv.io v1 exposed a web admin panel at `https://adm.${DOMAIN}` where the custom auth step file was uploaded through the GUI. v1 is no longer maintained — operators on the v1 line still have the panel for as long as their deployment lives, but new platforms run v2 and edit `override-config.yml` directly.

## Authenticate data access with Pryv.io

In this section, we illustrate the usage of a custom auth step through a basic use case. Bob wants to share his data with Alice, and creates an access for her on the stream "Health" with a "read" permission (more information on the **Access structure** [here](/reference/#data-structure-access)). 

When Alice is using the access that was provided to her, the custom auth step will allow to verify Alice's identity. This implies the creation of a "verification" access for Alice that will only be used to validate her identity.

### Hands-on example

The following scheme explains the different steps of the process using Pryv.io custom auth step.  

<p align="center">
<img src="/assets/gifs/alice-bob-v2.gif" />
</p>

You can watch the entire flow [here](https://youtu.be/Z1Ufo_9b_E4).  

Bob wants to create an [Access](/reference/#data-structure-access) exclusive to Alice on his stream "Health" with a "read" permission.

- 1 Alice creates an **Access for verification**, that will only be used by the custom auth step to validate her identity. The custom auth step will check that the access id of this **Access** and the access id stored in Bob's access for Alice match (see step n°6). This implies the creation of a stream "Verify" dedicated to this process.

```json
{
  "id": "alices-verification-abc",
  "token": "alices-token-for-bob",
  "type": "shared",
  "name": "alices-access",
  "permissions": [
    {
      "streamId": "verify",
      "level": "read"
    }
  ],
}
```

- 2 Alice provides Bob with:
  - her apiEndpoint: `https://alice.pryv.me/`
  - the `id` of her access previously created (see above): `alices-verification-abc`

- 3
 - 3.1 Bob creates an Access for Alice on the stream "Health".
 - 3.2 In the `clientData` field, he adds her apiEndpoint and the `id` of her access that she provided him with in the previous step, so that it will be verified by the custom auth step. 

```json
{
  "id": "ckdoc7cca0001m1pv5ju4msy5",
  "token": "bobs-token-for-alice",
  "type": "shared",
  "name": "bobs-access-for-alice",
  "permissions": [
    {
      "streamId": "health",
      "level": "read"
    }
  ],
  "clientData": {
    "customAuth": {
      "PryvAuthentication": {
        "apiEndpoint": "https://alice.pryv.me/",
        "accessId": "alices-verification-abc"
      }
    }
  }
}
```

- 4 Alice queries Bob's data with the following `Authorization` header:

```yaml
Authorization: "bobs-token-for-alice alices-token-for-bob"
```

It should contain both tokens, separated by a whitespace.

- 5 
 - 5.1 The Pryv.io API validates `bobs-token-for-alice`.
 - 5.2 The Custom Authentication function looks for a field `customAuth.PryvAuthentication` in the retrieved Access' `clientData`.
 - 5.3 Upon finding it, it fetches Alice's token's information, using Alice's `apiEndpoint` that is provided in the `clientData` field of Bob's access:
  
  ```
  GET {apiEndpoint}/access-info

  Authorization: alices-token-for-bob
  ```

  - 5.4 It receives the access information of Alice's verification token:

  ```json
  {
    "id": "alices-verification-abc",
    "token": "alices-token-for-bob",
    "type": "shared",
    "name": "alices-access",
    "permissions": [
      {
        "streamId": "verify",
        "level": "read"
      }
    ],
  }
  ```

- 6 It compares the retrieved Access `id` (`"id": "alices-verification-abc"`) with the one from Bob access' clientData: `clientData.customAuth.PryvAuthentication.accessId`. If it matches, it allows permission to the data, otherwise it refuses it.

### Custom Authentication function

You will find the code used by the custom auth step to validate Alice's identity below:

```javascript
const https = require("https");
module.exports = function (context, callback) {
  const access = context.access;
  if (
    access.clientData &&
    access.clientData.customAuth &&
    access.clientData.customAuth.PryvAuthentication
  ) {
    https
      .get(
        access.clientData.customAuth.PryvAuthentication.apiEndpoint +
          "/access-info?auth=" +
          context.callerId,
        (res) => {
          if (
            res.headers["pryv-access-id"] ===
            access.clientData.customAuth.PryvAuthentication.accessId
          ) {
            return callback();
          }
          callback(new Error("accessIds do not match"));
        }
      )
      .end();
  } else {
    callback();
  }
};
```

The arguments `context` and `callback` need to be passed as arguments to the method. Available properties of the context can be found in the fields described in the section [**What is the custom auth step**](#what-is-the-custom-auth-step).

```javascript
module.exports = function(context, callback) {
  // ...
}
```

The method first verifies that the access has a `clientData` property containing the access to verify:

```javascript
if (access.clientData && access.clientData.customAuth && access.clientData.customAuth.PryvAuthentication) {
  // perform authentication step
} else {
  callback();
}
```

If it does not, the authentication step is skipped.

If such a verification is required, a **getAccessInfo** API call is done to retrieve the information of Alice's token and verify if it matches the expected id:

```javascript
http.get(access.clientData.customAuth.PryvAuthentication.apiEndpoint + '/access-info?auth=' + context.callerId, (res) => {
  //alice accessId == clientData.customAuth.PryvAuthentication.accessId
  const authenticatedAccess = res.body.access;
  if (authenticatedAccess.id == access.clientData.customAuth.PryvAuthentication.accessId) {
    return callback();
  }
  callback(new Error('accessIds do not match'));
});
```

## Custom Auth Step features

You can access [NodeJS core modules](https://nodejs.org/docs/latest-v12.x/api/documentation.html) inside the custom auth function.  

As of template version v1.0.35, the Node version is 12.13.1.

## Authenticate data access with an external service

In the previous section, we presented a way to perform the authentication step against Pryv.io.  
In some cases, you might want to perform the validation step against a third-party API. This will require the validation of an additional token from the chosen external service.  

We invite you to contact us directly if you wish to implement such a verification with Pryv.io.
