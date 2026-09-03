---
title: 'Consent implementation with Pryv.io'
description: How to implement user consent with Pryv.io to meet data-protection requirements, covering the consent request flow and a hands-on example.
---


## Table of contents <!-- omit in toc -->
<!-- no toc -->
1. [Introduction](#introduction)
2. [How to collect consent with Pryv.io](#how-to-collect-consent-with-pryv-io)
    1. [Consent request](#consent-request)
    2. [Hands-on example](#hands-on-example)
3. [References](#references)

## Introduction

Managing consent is a critical issue for many developers when building personal data collecting applications. More than a checking-box option, it is what allows users to keep control over their personal information and businesses to keep track of data-related accesses and the purposes for which each data can be used.

This guide describes how Pryv.io implements consent to satisfy existing and forthcoming data protection and privacy requirements.

**Explicit consent** is one of the most challenging to satisfy, as it only allows you to collect data for specific purposes the data subject consented to; meaning that you must provide him with a clear explanation on what you are willing to do and obtain explicit permission.

However, consent can sometimes be *implicit*. For example, when hospitals need to collect and process personal data from emergency patients, or when a doctor shares a patient's data to a colleague to get a second opinion. In this case, your legal justification for processing personal data will not be "consent", but another one that would have been carefully defined as required by [art. 6 GDPR](https://gdpr.eu/article-6-how-to-process-personal-data-legally). If explicit consent is not your legal basis, we recommend that you go directly to the **API Reference** to learn how to [create an access token](https://pryv.github.io/reference/#create-access) and [track actions](https://pryv.github.io/reference/#audit) performed with it. Indeed, regardless of the legal basis on which you process personal data, you are still accountable for the actions performed on your users' data and need to ensure appropriate data audit capabilities (access control right).

In what concerns consent as a lawful base, Pryv made it easy for you: in the next few paragraphs, we will show you how to achieve it by simply building your app on top of Pryv.io.

## How to collect consent with Pryv.io

Privacy is embedded as default in Pryv, with dynamic consent as its cornerstone for organizations to account for privacy when building their products and apps on top of Pryv.io.

### Consent request

Data in Pryv.io accounts is organized in streams and events, and accesses are distributed over streams. This means that when you wish to collect/process particular data from your app user, you actually need to request access on the "stream" in which this particular data is located.

Let's keep things simple for now; thus, suffice to say that consent from the user will focus on "streams". If you wish to learn more about the **Pryv.io Data Model**, you can do so in this [tech guide](https://pryv.github.io/guides/data-modelling/) or [this video](https://www.youtube.com/watch?v=zl9RTf6JTps).

With Pryv.io, we are aiming at implementing a way of collecting consent that is straightforward, transparent, and meets the very specific requirements of the regulation: *freely given, specific, informed and unambiguous* ([Article 4](https://gdpr.eu/article-4-definitions/) of the GDPR).

Below are the step-by-step instructions on how to request consent from your user:

- **1** Define the data you are collecting/processing, and check whether it falls under what legislation.

- **2** Structure your data into streams and events following our [data modelling guide](https://pryv.github.io/guides/data-modelling/).

- **3** You are now ready to authenticate your app and request consent from your users. We have created a sample web application available [on Github](https://github.com/pryv/app-web-user-account) to register and authenticate your app users in a GDPR-compliant way by requesting their consent. You can test it [here](https://pryv.github.io/app-web-access/?pryvServiceInfoUrl=https://reg.pryv.me/service/info).

You will need to customize a few parameters to adapt it to your needs and ensure that you collect data from your users in the right way. In the [auth request](https://pryv.github.io/reference/#auth-request) that the app will perform, the parameter `clientData` will be the one containing the consent information:

```json
{
    "app-web-auth:description":
        {
            "type": "note/txt",
            "content": "This is a consent message."
        }
}
```

The consent request must follow very specific requirements that you need to keep in mind when customizing your consent message:

- **Consent must be informed**: Your app users must be fully informed of the data processing before granting consent. This means that your consent message should notify them of:

    - the name or title of the app/entity processing their data;
    - the purpose and the lawful basis (or bases) for processing their data;
    - the type of data that will be collected/processed. The concerned data streams will need to be described in the parameter `requestedPermissions` of the auth request;
    - their rights to access, erasure, and withdrawal.
- **Consent needs to be distinguishable**: Consent cannot be included "by default" or implicitly in the terms and conditions. Your app users must be provided an opt-in method that requires them to explicitly answer the consent message by selecting the "Reject" or "Accept" button. You must separate your requests for consent from all other matters and make sure that the request is accessible and written in plain language for your app users.

The parameter `requestedPermissions` of the auth request contains details about the data that will be collected, meaning the concerned streams from the user's Pryv.io account and the level of permission required on these streams (read, write, contribute or manage):

```json
{
    "streamId": "diary",
    "defaultName": "Journal",
    "level": "read"
}
```


- **4** Once the auth request has been sent, the web page will prompt the user to sign in using his Pryv.io credentials (or to create an account if he doesn't have one).

<p align="center">
<img src="/assets/images/signin.png" />
</p>

- **5** Once signed in, the consent message will appear.

<p align="center">
<img src="/assets/images/consent_message.png" />
</p>

If the user decides to "Accept" the consent request, the web page will open the authenticated Pryv API endpoint and grant access to the app on the requested streams:

<p align="center">
<img src="/assets/images/apiendpoint.png" />
</p>

- **6** You can view the created access by performing a [getAccessInfo](https://pryv.github.io/reference/#access-info) call: `https://ckg9hiq4n008m1ld3uhaxi9yr@mariana.pryv.me/access-info`.

This will return information about the access in use:

```json
{
    "name": "demo-request-consent",
    "type": "app",
    "permissions": [
        {
            "streamId": "diary",
            "level": "read"
        }
    ],
    "clientData": {
        "app-web-auth:description": {
            "type": "note/txt",
            "content": "This is a consent message."
        }
    },
    "user": {
        "username": "mariana"
    },
    "id": "ckg9hiq4o008n1ld3xy7t46d6",
    "token": "ckg9hiq4n008m1ld3uhaxi9yr",
    "created": 1602685422.023,
    "createdBy": "ckbi19ena00p11xd3eemmdv2o",
    "modified": 1602685422.023,
    "modifiedBy": "ckbi19ena00p11xd3eemmdv2o",
    "meta": {
        "apiVersion": "1.7.13",
        "serverTime": 1602860299.642,
        "serial": "2019061301"
    }
}
```

### Hands-on example

Let's illustrate the consent request process with a practical example. Bob wishes to invite Alice on a date to a restaurant but doesn't know her food preferences.
He wants to request access on Alice's stream "Nutrition" to subtly analyze what she likes to eat...How can he do so?

- **1** As Alice's food preferences qualify as personal data under GDPR requirements, he will have to formulate a proper request to access them.

- **2** Both Alice and Bob already have their Pryv.io accounts settled and furnished with structured data (in streams and events).

- **3** The only thing Bob needs to do is customize the consent message, and send a request to Alice:

He must prepare the payload for the [Auth request](/reference/#auth-request) containing:

- the streamId which data he wants to read in `requestedPermissions`
- the consent message in `clientData`
- an identifier for the request which will serve as the created access' name in `requestingAppId`

The payload looks as following:

```json
{
    "requestPermissions": [{
        "streamId": "nutrition",
        "defaultName": "Nutrition",
        "level": "read"
    }],
    "clientData": {
        "app-web-auth:description": {
            "type": "note/txt",
            "content": "Hi there! This is Bob. I'd really like to know more about what your tastes and preferences, and I'd need your approval to read personal information from your stream Nutrition. If you consent to share it with me, please click on Accept.

            You have a certain number of rights under the GDPR: the right to access personal data I may hold about you, the right to request that I amend any personal data which is incorrect or out-dated, and the right to request that I delete any personal information that I have about you. If you'd like to exercise any of these rights, please contact me at bob@privacy.com."
        }
    },
    "requestingAppId": "Alice's food preferences"
}
```

- **4** He will send the request to Alice through a mobile or web app such as [this one](/guides/consent/request/).

| Before sign in and consent request     |   After sign-in and accepting consent request                                                  |
| ------------------------------------------------------------ |------------------------------------------------------------ |
| <img src="/assets/images/request-app-1.png" alt="app-1" style="zoom:50%;" /> | <img src="/assets/images/request-app-2.png" alt="app-2" style="zoom:50%;" /> |

- **5** The web app will perform an [Auth request](/reference/#auth-request), prompting Alice for permissions to her data and presenting her with the consent message.

<p align="center">
<img src="/assets/images/consent2.png" width="333" height="478"/>
</p>

- **6** If she accepts, the app should send the obtained API endpoint to Bob (which was not done here).
In case Bob wants to save Alice's API endpoint along with other accesses that have been granted to him, he can do so as presented in [the chapter "Store data accesses" of the data modelling guide](/guides/data-modelling/#store-data-accesses).

Bob is now ready to discover what Alice really likes...


<p align="center">
<img src="/assets/images/bigmac.png" />
</p>


## References

### Data privacy requirements and legislation

For more information about how the GDPR requirements affect Swiss companies, you can read our article ["GDPR, Swiss DPA & ePrivacy – what Swiss companies should know"](https://web.archive.org/web/20200813020815/https://www.pryv.com/2019/11/20/gdpr-swiss-dpa-e-privacy/) (archived copy).

### Personal data scope

You can find more information on what is defined as **"personal data"** in our [FAQ](https://pryv.github.io/faq-api/#personal-data).

### Data modelling

**Pryv.io Data Model** is summarized in [this video](https://www.youtube.com/watch?v=zl9RTf6JTps).
To learn how to model your data into streams and events, you can check our [tech guide](https://pryv.github.io/guides/data-modelling/) on data modelling.

### Web app examples

You can found our sample web apps in our [Github repository](https://github.com/pryv/example-apps-web).
