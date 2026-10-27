---
title: 'Open API 3.0'
description: Download the Pryv.io API and system API as OpenAPI 3.0.3 definition files, generated from the API reference, and import them into Postman or other API tools.
---

# Definition files

These OpenAPI 3.0.3 documents describe the Pryv.io API in YAML. They are generated from the [API reference](/reference/) every time this site is built, so they always match it: the reference stays the authoritative description, and the files are never edited by hand. Each file names the reference version it was generated from (`info.version`, `x-generated-from`).

- The [Pryv.io API](/reference/): [api.yaml](/open-api/3.0/api.yaml).
- The [system API](/reference-system/): [api_system.yaml](/open-api/3.0/api_system.yaml).
- [api_open.yaml](/open-api/3.0/api_open.yaml) is a legacy alias of `api.yaml` (same content), kept so existing links and imports keep working; use `api.yaml` for new integrations.

No OpenAPI definition is published for the admin API: the [admin reference](/reference-admin/) still describes the previous-generation admin panel and will get a definition once it is rewritten.

What the files contain:

- Each operation carries the reference method id as `operationId` and in `x-pryv-method-ids`. Where two methods share a route (for example `events.create` and `hfs.create` on `POST /events`), they are one operation and `x-pryv-method-ids` lists both; the request body and the responses are the methods' shapes combined (one schema when they are the same, an `anyOf` otherwise).
- `servers` lists the two account endpoint forms (`https://{username}.{domain}` and the single-host form `https://{host}/{username}`); the system API lists the register and core servers, and each operation says which one in `x-pryv-server`.
- The access token goes in the `Authorization` header or the `auth` query parameter; methods that need no token say so (`security: []`).
- Method-specific errors are listed per status code with their ids in `x-pryv-error-ids`; the errors possible on any call are the `default` response.
- The app authorization flow (auth request and polling) is described in the [reference](/reference/#basics-authenticate-your-app), not in the files: its URLs come from the service information at run time.

# Usage

## Postman

### Import

The OpenAPI description of Pryv.io can be directly imported into Postman to test the API's functionality.

- **1.** If Postman has not yet been installed on your computer, you can download it from [here](http://www.getpostman.com).
- **2.** In the Postman app, click `Import` to bring up the following screen:

![Import on Postman](/assets/images/import.png)

You can choose to upload a file, enter a URL, or copy the YAML file on Postman.

Import `api.yaml` from its [URL](/open-api/3.0/api.yaml), or the downloaded file, with `Import as an API` and `Generate a Postman Collection` checked.

### Environment

- **3.** In the top right corner of Postman, click on the eye icon to see the Environment Options and `Add` a new active Environment for Pryv:

![Add the Environment](/assets/images/add.png)

- **4.** Set the environment variables of Pryv.

Fill in the variable `baseUrl` as shown below:

![Manage the Environment](/assets/images/manage.png)

The variable `baseUrl` should be set as `https://{{token}}@{{username}}.pryv.me`, with the variables `username` and `token` corresponding to the username and access token of your Pryv account.
You can find more information on how to create a Pryv user on the [dedicated page](/getting-started/#create-a-pryv-lab-user), and obtain an Access Token from the [Pryv Access Token Generator](https://pryv.github.io/app-web-access/?pryvServiceInfoUrl=https://reg.pryv.me/service/info).

In our example, the `username` "testuser" associated to the `token` "cdtasdjhashdsa" are used to set the `baseUrl` variable as `https://cdtasdjhashdsa@testuser.pryv.me`.

**Note that you should remove trailing slash for the variable `baseUrl` to have a working environment.**

Finally, click on `Add` to update the environment.

### Testing the API

- **5.** Once the Pryv environment is set, you can get familiar with Pryv.io API by testing different methods:

![Open API methods](/assets/images/play.png)

Select a method by directly clicking on it.

For `GET` methods, you can check or uncheck the Query Params you need, and fill them with the right value in the `Params` field.

As an example, see the method `events.get` below:

![events.get](/assets/images/get-events.png)

For `POST` and `PUT` methods, you should fill the necessary parameters in the `Body` field.

As an example, the different parameters `name`, `parentId`, etc. should be completed with their own value when creating a new stream for the method `streams.create` below:

![streams.create](/assets/images/create-streams.png)

- **6.** Once you have filled in the necessary fields for the method you are testing, click on `Send` to send the request:

![Send request](/assets/images/send.png)

- **7.** Enjoy!

The original API reference can be found [online](/reference/).

For any questions or suggestions, do not hesitate to contact our team directly.
