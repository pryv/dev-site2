---
title: 'FAQ - API'
description: Answers to common questions about the Pryv.io API, covering personal data, streams, event types, authentication, access sharing and notifications.
---


In this FAQ we answer common questions related to Pryv.io API. You can contact us on [Github Discussion](https://github.com/orgs/pryv/discussions) if your question is not listed here.



## Table of contents <!-- omit in toc -->

1. [Personal data](#personal-data)
2. [Streams](#streams)
3. [Event types](#event-types)
4. [Other data structures](#other-data-structures)
5. [API methods](#api-methods)
7. [Synchronization](#synchronization)
8. [User creation](#user-creation)
9. [Authentication](#authentication)
10. [Account granularity](#account-granularity)
11. [Access sharing](#access-sharing)
12. [Notification system](#notification-system)
13. [Test setup](#do-you-have-a-test-setup-where-i-could-experiment-with-your-api-)


## Personal data

### We are using medical devices to collect data from our users. Is technical data from these devices also part of “personal” data of the user ?

For data to be considered as “personal” data, it has to observe the following conditions  :

- It is describing the person’s life. For example, MR Safe data shows that the individual was in an MRI at a particular moment, which is descriptive of his life;
- It enables the person’s identification. For example, technical time-stamped data from a rare surgery can enable anyone to identify the person who has undergone the surgery, as only a few persons around the world have undergone the same surgery at the same timing.

### Where should I store technical data of these devices ?

If the technical data from these devices is considered as “personal” data of the user, he has the right to access it anytime. It should therefore be stored in his account.
If you prefer storing this data in a separate account, keep in mind that the user can ask for a copy of it anytime if it is “personal” data.


## Streams

### Is the stream structure declared globally or at the level of each user account ?

The stream structure is independent from one user account to another. It is declared and managed by apps: the stream structure can be created by the app when the user logs in for the first time for example.

We advise you to maintain a list of streams as explained in our [data modelling guide](/guides/data-modelling/#implementation).

### Is there a limit in the number of child streams that a stream can have ?

There is no limit to the number of substreams of a stream. As a general rule it is preferable to multiply the number of streams and to minimize the creation of different event types.

For example, if you want to enter data measurements for different types of allergens, it is preferable to create one substream per allergen type (`Cereal crops`, `Pollen`, `Hazelnut Tree`, etc) with a single event type (`density/kg-m3`) instead of multiplying event types (`density/pollen`, `density/cereal`, etc) under a single stream `Allergens`.


## Event Types

### How can I define custom event types?

You can define any custom type as long as it follows [this structure](/event-types/#basics). See [How to customize event types](/customer-resources/pryv.io-setup/#customize-event-types-validation) for more information.

### Can I limit the number of event types to be used in a stream ?

There is no limitation in terms of event types per stream. A stream acts like a “folder” in which you can put any type of information.
If you wish to give a Pryv access token to an external service and to control its use of the access, you can give it a “limited” access type - `create-only` - which allows it to **only** create events in the streams (more information on the different permission levels [here](/reference/#access)).

### Are my events content validated?

The default set of validated types is defined in [https://pryv.github.io/event-types](/event-types/), they are validated upon creation and modification. To validate custom types, it is possible to provide a different source of event types, following the [JSON schema format](/event-types/#format-specification).

### What kind of validation do you perform?

Depending on the `type` field of the event, the content of the fields `content` and `attachments` are validated.


## Other data structures

### What information should be contained in the “Profile” section of the user ?

Profile sets are plain key-value structure in which you can store any user-level settings (e.g. credentials).
This structure is likely to be deprecated soon, and with the exception of the “Public profile set”, we recommend our customers to use dedicated streams to store account information of their users.

### What are “Followed slices” that can be stored in Pryv accounts ?

Followed slices are meant to store another user's access tokens in one's account. For practical reasons, we generally advise you to store the access tokens in a dedicated stream.

For example, a doctor can store all the tokens to patients’ accounts for which he has been granted the access in a [Followed Slice](/reference/#followed-slice).

However this data structure has a limitation: it is only accessible with a “personal token” which requires the user to login with his password every time.


## API methods

### Is it possible to have a list of existing core servers ?

Yes, the register service has 2 methods:

- Get hostings: [GET hostings](/reference-system/#get-hostings).
- Get cores: [GET core servers](/reference-system/#get-core-servers).

### What is the exact structure of the create attachment call?

If you are having issues creating the package for the create attachment call with the client/framework/library you are using, you can print the details of the call by using cURL with the `-v` verbose option.


## Synchronization

### How to keep events in local cache up to date?

The [events.get API method](/reference/#get-events) offers the `modifiedSince` and `includeDeletions` parameters to synchronize a set of events.
As the default parameters return the last 20 events, we should perform synchronization on a time range, which can be very big if needed.

1. Initialize your events cache with an `events.get` call and a time range with `fromTime` and `toTime`.
2. When you receive the events, loop into them to find the latest `event.modified` value.
3. Store this value in a variable we call `anchor` and add a very small number to it, for example: `0.0000001`.
4. To synchronize the events you just need to call `events.get` with a time range and `&modifiedSince={anchor}&includeDeletions=true` query parameters.

The JavaScript library's [Monitor add-on](https://github.com/pryv/lib-js/tree/master/components/pryv-monitor) implements this pattern.

#### Limitation

Note that if you have an [access](/reference/#access) with permissions on a certain set of streams (we'll call this a "scope"), you will not be able to detect events that are leaving this scope.
For example, let's say you have permissions on the streamId `diary`. If some client changes its streamIds by removing `diary`, you will not be able to detect this change.

### How can I setup an "Automatic" synchronization of my Events and Streams cache

By coupling the precedent logic with a [Notification System](/faq-api/#notification-system)

If you use the [Pryv JavaScript Library](https://github.com/pryv/lib-js), it can be used in combination with our [Monitor](https://github.com/pryv/lib-js/tree/master/components/pryv-monitor) and [Socket.io](https://github.com/pryv/lib-js/tree/master/components/pryv-socket.io) add-ons to have "near real-time" updates.


## User creation

### Is there an API call for user creation?

The API call for user creation is defined in [API system reference](/reference-system/#account-creation), please contact us for more information.

### Can we restrict access to user creation?

The user creation API call uses a token and by not making this token public, it is possible to make account creation available to select users.

### What if I don't want to provide an email registration phase?

Account must have an email-like string attached to them. You can make up an email address for you internal app usage, depending on your requirements. Please note that you will not be able to retrieve a lost password using the [reset password request](/reference/#request-password-reset).

We suggest using the following format as a placeholder: `${USERNAME}@${DOMAIN}`.

### How can I programmatically create user accounts?

It is possible to create users with an API call, without having to fill the fields manually.

### Is there a search tool to retrieve a username from the user information (name, surname, etc) ?

It is possible to retrieve a username from an email address: [Get username from email](/reference-system/#get-username-from-email).
This is useful for email authentication or if the user has lost his password.


## Authentication

### How does the authentication flow work ?

You can check how to authenticate your app [here](/reference/#authenticate-your-app).

We deliver our Pryv.io platform with "default" web apps for registration, login, password-reset and auth request. The code is available [here](https://github.com/pryv/app-web-user-account) (formerly app-web-auth3).

We advise our customers to customize it, and we provide some [guidelines](/customer-resources/pryv.io-setup/#customize-authentication-registration-and-reset-password-apps) for the customization.

### I'm getting the "invalid credentials" error on the auth.login call although my fields are correct.

```json
{
    "error": {
        "id": "invalid-credentials",
        "message": "The app id ("appId") is either missing or not trusted."
    },
    "meta": {
        "apiVersion": "1.2.18",
        "serverTime": 1531830525.911
    }
}
```

API methods such as `auth.login` marked as <span onclick="location='/reference/#trusted-apps-verification'" class="label trusted-only">Trusted apps only</span> on [the API reference](/reference/) require to have the `Origin` or `Referer` headers matching the domain or one defined in the configuration. This field is not changeable in browser as it is a security measure. We use this to prevent phishing attacks that would allow attackers to impersonate Pryv.io connected apps to steal user credentials.

In order for this to work, the web app must be running on a domain allowed by the configuration. By default, this contains: `https://*.${DOMAIN}*, https://*.rec.la*, https://*.pryv.github.io*`.

In mobile apps, the `Origin` and `Referer` headers can be set manually in the HTTP request. For example: `Origin: "auth.${DOMAIN}"`.

In addition to the host, it is possible to allow this call for a defined set of `appId`.

### What authentication should I use in a mobile app?

You should implement the [auth request](/reference/#auth-request), displaying the provided `url` in a web view. Once you obtain the token, save it into the local app storage so you will not have to authenticate each time.

### Is it possible to add an additional layer of authentication?

The Pryv.io login supports multi-factor authentication (MFA). See its API reference methods [here](/reference/#multi-factor-authentication).


## Account granularity

### Should I store the data of more than one person in a single Pryv.io account?

For compliance reasons, Pryv.io accounts are per-user. Storing multiple people data under the same account bypasses the authentication step which is the technical equivalent of consent.


## Access sharing

### How does a person give access to his data?

Using a token previously obtained, you can generate a new one using the [accesses.create](/reference/#create-access) API call to generate a new token. The permission set associated to this token must be a subset of the permissions set of the access token used for the call.

### Where should I store the access token to a user's account ?

Once you have obtained an access token to a user's account, for example for a doctor to access particular streams of his patients' data, we advise you to store it in a dedicated stream.

You can find an example in the [data modelling guide](/guides/data-modelling/#consent-aggregation) of how to do consent aggregation with Pryv.io and store access tokens to user accounts.

### How can I request access to someone's data ?

In order to request an access to someone's data, one must implement a page that makes an [auth request](/reference/#auth-request) when loaded. The `url` in the response must be displayed to the user. The web page will ask him for his credentials as well as display the list of requested permissions. Upon approval, the app will obtain a valid token in the polling url response.

A simple web app demonstrating this implementation can be seen [here](https://github.com/pryv/app-web-access).

### What are the different access types ?

There are three main access types - **personal**, **app** and **shared** - that are defined and explained [here](/concepts/#accesses).

### How long should I keep an access token valid ?

Accesses are not systematically set with an expiry date. The optional field `expireAfter` of an [Access token](/reference/#access) allows you to set an expiry date for the token if you want to.

If you are concerned with the security of the access, we provide you with monitoring tools to detect fraudulent use of tokens [here](/reference/#audit).

### How can I access Pryv.io resources from another app?

This can be done by using the auth request through a consent step or by generating a token directly through an API call using a token obtained previously.

### How does an access delegation work ?

It can happen that you would need an access delegation from your app users if they cannot connect on the app to authorize apps and grant access to their data for some period of time.

You can send an auth request to your users at their first login to grant your app access to all or specific streams (see [here](/reference/#authenticate-your-app) for more information on the auth request).

This works as a delegation of access, and the “app” token will be able to generate sub-tokens of a “shared” type and give permission to data that was in its scope.

### What level of permissions do I need to create/delete/modify streams in a user’s account ?

The access level “manage” on a stream gives you the permission to manipulate (read, create, modify, delete) all the substreams of this stream (see more details on the **Access** structure [here](/reference/#access)).

### Can I limit the number of apps that can send an auth request to users ?

There is currently no API secret to restrict the auth request usage.
You can contact us directly if you wish to implement a verification protocol for the requesting apps.

### How to distribute accesses over a user account between multiple apps ?

We advise you to define all the needed accesses for third-parties from the beginning, and to ask for the user's consent at his first login on your app.

You can do so by sharing a document with the user listing the concerned third-parties and asking for his consent, or by implementing a web-app that displays a panel of apps/third-parties to grant access to.

To see an example of access structure implementation, you can check the [Data Modelling guide](/guides/data-modelling/).

You can give each third-party an “app” token with limited permissions to a particular scope of streams.

It is generally preferable to maximize the number of "app" tokens with limited set of permissions than to use a "master" token generating shared type of accesses to third parties, as it allows to track accesses made over data for audit capabilities.

Below is an example of a single app "third-party-test" requesting access to the particular streams "Health" and "Personal Information" with a limited set of permissions :

<img align="center" width="200" src="/assets/images/app-access.png" >


## Notification system

### Should I use “websockets” or “webhooks” to subscribe to changes ?

**Websockets** should be used to get notified of data changes in a web application (on the frontend side).
**Webhooks** are more suited to get notified of data changes in a web service (on the backend side).

More details on websockets and webhooks can be found [here](/reference/#subscribe-to-changes).

### What type of information do webhooks/websockets contain ?

You can have a look at the webhooks and websockets data changes payload in the [Subscribe to changes section](/reference/#subscribe-to-changes).

### Is the server notified of data changes in all streams of the account or only the streams for which permission was granted in the provided access token ?

Notifications are sent as soon as there is a data change in the "events", "streams" or "accesses" for the whole user account. It is therefore possible to get notified of a data change that would not be in the scope of the access token.
Notifications are likely to be scoped in the near future.


## Do you have a test setup where I could experiment with your API?

You can try out Pryv.io using our demo platform pryv.me: [https://pryv.com/pryvlab/](https://pryv.com/pryvlab/)
