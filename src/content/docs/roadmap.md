---
title: 'Pryv.io roadmap'
description: "The Pryv.io roadmap: upcoming releases and a history of shipped versions, including the v2 single-binary release under the BSD-3-Clause license."
---


# Future releases

- Check progress and features plan on [Github V2 Project](https://github.com/orgs/pryv/projects/5)

# Released

## 11.04.2026 - 2.0.0-pre

Open-Pryv.io v2: the former "Enterprise version" and Open-Pryv.io are now the same codebase, distributed as a single binary and Docker image under BSD-3-Clause. All features are always enabled.

- Registration, MFA, high-frequency series and previews served by a single binary (`bin/master.js`)
- PostgreSQL as an alternative storage engine alongside MongoDB
- Multi-core support with built-in DNS server
- Docker image: [`pryvio/open-pryv.io`](https://hub.docker.com/r/pryvio/open-pryv.io)

See the [change log](/change-log/) for full details.

## 19.05.2025 - 1.9.3

- Added Audit to Open-Pryv.io.

## 02.02.2025 - 1.9.2

- Full open source release
- Refactored Attachments (Event Files) Logic to be modular for future cloud storage of files such as S3.
- Implemented ferretDB compatibility allowing full-open source modules
- Replaced rec.la by backloop.dev

## 01.10.2023 - 1.9.0

Many under-the-hood changes and a couple fixes, including:

- Stream response to `streams.delete` method to avoid potential timeout
- Deleted stream ids are now already reusable when following the auth process
- Username is not available anymore form `username` system stream. It should be retreived from `access-info`.

## 07.05.2023 - 1.8.1

- Fixes migration issues found in 1.8.0  

## 07.10.2022 - Dynamic mapping support & HDS SECU_AUTH with 1.8.0

- Expose external (e.g. legacy) data warehouses through Pryv.io. (documentation)[https://github.com/pryv/pryv-datastore]
- Compliance with HDS requirements SECU_AUTH 3 & 4: Enforce rules for password complexity and password age (including past passwords history)

## 12.11.2021 - Automatic SSL certificate generation with Pryv.io 1.7.4

- Pryv introduces a service that generates a SSL certificate for your running Pryv.io installation and deploys it to all machines for cluster and single-node.
See [Generate SSL certificate guide](/customer-resources/ssl-certificate/) for more information.

## 25.10.2021 - New features with Pryv.io 1.7.0

- Audit log has been rebuilt, improving performance of fetched audit data, adding granularity over which methods are audited. See the [Audit guide](/guides/audit-logs/) on how to use them and see the [Audit setup guide](/customer-resources/audit-setup/) on how to set it up on your Pryv.io platform.
- New integrity feature, computing hash for events, attachments and accesses data.
- Automated platform upgrade tool. See "Find Migrations" button in Admin panel and check [changelog](/change-log/) for API.

## 26.04.2021 - new MFA release with Pryv.io 1.6.20

New MFA release:

- New [MFA configuration guide](/customer-resources/mfa/)
- Support for simple communication services: [single mode](/customer-resources/mfa/#modes)
- Expand current implementation to template what is sent to the communcation service and store only user values in profiles.
- Deactivate MFA through the Admin panel & API. See [change log](/change-log/).

## 11.01.2021 - Complete admin and system API

[Admin](/reference-admin/) and [system](/reference-system/) API references are now complete and available through [Open API definitions](/open-api/#definition-file).

## 15.12.2020 - Stream queries

You can now query events with more precision using [Streams queries](/reference/#streams-query).

## 22.10.2020 - React Native support for lib-js

A react native application using the [Pryv.io JavaScript library](https://github.com/pryv/lib-js) is now available in our [Github repository](https://github.com/pryv/app-react-native-example).
This app example displays an implementation of Pryv.io authentication protocol.

## 20.10.2020 - Consent implementation with Pryv.io

We have released our new [tech guide](https://pryv.github.io/guides/consent) to help developers manage consent when building personal data collecting applications to satisfy existing and forthcoming privacy regulations. It outlines the logic of managing consent with Pryv.io, and guides you through a practical hands-on example involving a consent request.

## 28.09.2020 - System Streams with Pryv.io

Now user registration could be customized using the Pryv.io configuration. Either you want to have a registration without an email or
have your own unique fields, now it is possible to do so. Also, admin panel users could easily delete not active users.

## 27.08.2020 - Collect and Share High Frequency Data with Pryv.io

Push the boundaries of your High Frequency Data. Discover how to collect, view and share high-frequency data in our [tutorial video](https://www.youtube.com/watch?v=l6uOXr1_ivA) for our high-frequency app.
The code for the Desktop and Mobile version is available in our [Github repository](https://github.com/pryv/example-apps-web/tree/release/hf-example/hf-data).

## 24.08.2020 - Custom Authentication with Pryv.io

Provide your Pryv.io platform with a custom auth step to authenticate your Pryv.io API requests or authorize them against another web service. Detailed information in our [new technical guide](/guides/custom-auth/), illustrated with our [video use case](https://www.youtube.com/watch?v=Z1Ufo_9b_E4&feature=youtu.be): *How to check Alice's identity when she tries to access Bob's data for which he gave her access to ?*

## 12.08.2020 - Admin panel for Pryv.io

We have released a web application for your Pryv.io platform administration. It allows you to manage the platform settings of your platform. Contact us directly if you wish to get your admin panel for Pryv.io!

## 10.08.2020 - Data Modelling guide

Our new [Data modelling guide](/guides/data-modelling/) is out, illustrating multiple use cases that can be implemented using the Pryv.io API.

## 05.08.2020 - "Change password" page

The additional `/change-password.html` page has been published among our [template web pages](https://github.com/pryv/app-web-user-account) to register, authenticate and password modification for your app users.

You can discover the authentication process for your Open Pryv.io platform in our [video tutorial](https://youtu.be/MfGTAgXr2WI). and fork our [Github repository](https://github.com/pryv/app-web-user-account/fork) to customize it.

## 31.07.2020 - Develop your iOS applications with Pryv.io

Our new [Swift library](https://github.com/pryv/lib-swift) facilitates writing iOS apps for a Pryv.io platform, and provides an [Apple HealthKit bridge](https://github.com/pryv/bridge-ios-healthkit) between HealthKit data samples and Pryv.io streams.

Learn how to grow your own [iOS App(le)s](https://github.com/pryv/app-ios-swift-example) in this video: https://youtu.be/poWC__m8ZFU.

Discover Apple HealthKit bridge video here: https://youtu.be/PIBh2_joFqQ.

## 24.07.2020 - View and share data

Following our [Collect survey data tutorial](https://github.com/pryv/example-apps-web/tree/master/collect-survey-data), enable your users to visualize and share data with our new template web app.
- Github repository for [View and Share data](https://github.com/pryv/example-apps-web/tree/master/view-and-share) web app
- Check our [video tutorial](https://youtu.be/gEfPmkQmtAI)

## 23.07.2020 - Register and authenticate your users

Learn how to use our [template web pages](https://github.com/pryv/app-web-user-account) to register and authenticate your app users in our new [video tutorial](https://youtu.be/MfGTAgXr2WI).
Simplify your authorization process for your Open Pryv.io platform by forking our [Github repository](https://github.com/pryv/app-web-user-account/fork).

## 15.07.2020 - Dockerized Open Pryv.io

Open Pryv.io is now available through Docker containers : [youtube](https://youtu.be/RwxEo4c_ed0) with the whale.

## 14.07.2020 - Customize your Pryv.io web apps

A new tutorial on how to customize assets in your web apps is now available on [Github](https://github.com/pryv/example-apps-web/tree/master/customize-assets). Check the video tutorial [here](https://youtu.be/VI1zjLLcR9Q).

## 06.07.2020 - Pryv.io Onboarding

Learn how to implement an onboarding experience for your app users by watching our [video tutorial](https://www.youtube.com/watch?v=258UsM1Qq0o&t=12s) and the [Github implementation](https://github.com/pryv/example-apps-web/tree/master/onboarding).

## 03.07.2020 - Collect survey data with Pryv.io

Discover how to easily create a form and collect data with Pryv.io in our [tutorial video](https://www.youtube.com/watch?v=SN11LSxL8q4). The web app is available in our [Github repositery](https://github.com/pryv/example-apps-web/tree/master/collect-survey-data) to help you implement your own.

## 08.06.2020 - Pryv.io goes Open Source

Pryv releases an [Open-Source Solution](https://github.com/pryv/open-pryv.io) for Personal Data & Privacy Management.

## 17.01.2020 - Pryv.io integration with Postman

Check how Postman can help to facilitate & accelerate the Pryv.io API integration 
Integrate Open Pryv.io with Postman in our [1min video](https://www.youtube.com/watch?v=jv_cZPAbUo4), and download our newly [created OpenAPI definition](https://pryv.github.io/open-api/3.0/api.yaml) file to boost your way to privacy !.

## 04.01.2020 - Webhooks at Pryv.io

Pryv.io notifies your app of any data changes from now.
Our [Webhooks technical guide](/guides/webhooks/) explains their different features and how they are set up.

## 23.11.2019 - Audit Logs in Pryv.io

Keep track of actions performed by your app users against Pryv.io accounts with audit logs.

## 02.06.2019 - High Frequency Data in Pryv.io

Learn more about how you can store data at high frequency and high data density in Pryv.io [here](https://pryv.github.io/reference/#hf-series).
