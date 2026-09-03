---
title: 'App guidelines'
description: General guidelines for building platform-agnostic Pryv.io applications and libraries, including auto-configuration from the service information endpoint.
---


General guidelines for writing applications and libraries for Pryv.io platforms.

Web applications should be implemented to be platform agnostic, so they can be run on your production environment as well as your staging one.  
Our [example applications](/external-resources/#web-application-examples) can be run on our [Pryv Lab platform](https://pryv.com/pryvlab/) as well as your own.

# Auto-configuration

Applications should retrieve configuration parameters from the [service information](/reference/#service-info).

For this we suggest to implement the following ways to load its configuration:


1. **pryvApiEndpoint** query param

  An URL in the [Basic HTTP Authorization form](/reference/#authorization).

  Example:`https://cdtasdjhashdsa@testuser.pryv.me` as API endpoint (URL encoded)

  ```
  https://sample.domain/app/index.html?pryvApiEndpoint=https%3A%2F%2Fcdtasdjhashdsa%40testuser.pryv.me
  ```

  Note: service information should be retrieved by appending the path `/service/info` to the value given by `pryvApiEndpoint`.

2. **pryvServiceInfoUrl** query param

  Example: `https://reg.pryv.me/service/info` as service information URL (URL encoded)

  ```
  https://sample.domain/app/index.html?pryvServiceInfoUrl=https%3A%2F%2Freg.pryv.me%2Fservice%2Finfo
  ```

**Prevalence** 

If multiple parameters are provided, the following order of priority should be used:  

1. `pryvServiceInfoUrl` as query parameter
2. `pryvApiEndpoint` as query parameter
3. `pryvServiceInfoUrl` as default value

# Authorization

Using a `pryvApiEndpoint` to load an app allows to load data directly as it usually contains credentials. For cases where you require authentication, it is preferred to use `pryvServiceInfoUrl`:

<script src="/assets/js/raphael.min.js"></script>
<script src="/assets/js/flowchart.min.js"></script>
<div id="diagram"></div>
<div id="flowChartCode" style="visibility: hidden; display:inline;">
st=>start: Start
ready=>end: Ready
fail=>end: Fail

authProcess=>operation: Auth Process:>/reference/#authenticate-your-app

condApiEndPoint=>condition: pryvApiEndpoint?
condServiceInfo=>condition: pryvServiceInfoUrl?

st->condApiEndPoint
condApiEndPoint(yes)->ready
condApiEndPoint(no)->condServiceInfo
condServiceInfo(no, bottom)->fail
condServiceInfo(yes, right)->authProcess
authProcess(top)->condApiEndPoint
</div>
<script>
var diagram = flowchart.parse(document.getElementById('flowChartCode').textContent);
diagram.drawSVG('diagram');
</script>