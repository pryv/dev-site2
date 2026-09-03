---
title: 'Observability'
---


Open Pryv.io v2 ships an **optional** observability layer that reports per-method usage metrics and server-side error reports to a monitoring backend of your choice, over **OTLP/HTTP**. It is **off by default**.

No third-party monitoring agent runs inside the process, and nothing is auto-instrumented. Telemetry is **constructed by the platform from a fixed allow-list** and then sent. That distinction is the whole design: what can leave your deployment is a property of the platform's source code, not of an external agent's defaults, so it does not change when a dependency is upgraded.

> **Data handling note.** Enabling observability means performance metadata leaves your deployment for wherever you point it. The emitted surface is enumerated below and is deliberately anonymous, but you own the decision and — unless you point it at a collector you host yourself — it is a processing arrangement with a third party. Read [What is sent](#what-is-sent) before enabling this on a deployment holding personal data.

## Table of contents <!-- omit in toc -->

1. [Overview](#overview)
2. [What is sent](#what-is-sent)
3. [What cannot be sent](#what-cannot-be-sent)
4. [How anonymous is it, exactly](#how-anonymous-is-it-exactly)
5. [Choosing a backend](#choosing-a-backend)
6. [Enabling it](#enabling-it)
7. [The reporting interval](#the-reporting-interval)
8. [Verifying what your backend holds](#verifying-what-your-backend-holds)
9. [Rotating credentials](#rotating-credentials)
10. [Disabling](#disabling)
11. [Caveats](#caveats)

## Overview

A single emitter inside the core builds every datapoint from a compile-time vocabulary, validates it, aggregates it in memory, and posts it to your OTLP endpoint on a timer. Anything that does not match the vocabulary is dropped and counted, never sent.

Configuration is cluster-wide, stored in PlatformDB, and managed with `bin/observability.js`. Credentials are encrypted at rest. Changes require a rolling restart of your cores: workers receive the resolved configuration from the master process when they start.

## What is sent

This is the complete list. There is no "and other diagnostic data".

**Metrics**, aggregated per reporting interval:

| Metric | Labels |
|---|---|
| `api.method.calls` | `method.id`, `status.class` |
| `api.method.duration` (histogram, ms) | `method.id`, `status.class` |
| `api.method.errors` | `method.id`, `error.code` |
| `telemetry.dropped` | `reason` |

- `method.id` is an API method identifier taken from the core's own method registry (for example `events.get`, `auth.login`). It is re-checked against that registry before every emission, so a value that is not a registered method id cannot be sent.
- `status.class` is one of `2xx`, `3xx`, `4xx`, `5xx`.
- `error.code` is one of the API's documented error ids (for example `invalid-access-token`), or `unknown`.
- `telemetry.dropped` counts datapoints the emitter refused. A non-zero value means something tried to emit outside the vocabulary and was stopped; it is worth alerting on.

**Process identity**, attached to every batch: service name (the label you set), service version, the **machine hostname**, and a worker index.

**Error reports**, for server-side faults only (5xx, unexpected and unclassifiable errors; client mistakes such as a rejected token are counted, not reported):

- the error code, and a **hard-coded message** looked up from the platform's own message catalogue by that code;
- the error class name (for example `Error`, `APIError`);
- the API method it occurred in;
- a **stack trace rebuilt from repository-relative frames**, plus a count of how many times that identical fault occurred in the interval.

## What cannot be sent

Request URLs, query parameters, route parameters, request and response bodies, HTTP headers of any kind, usernames, stream / event / attachment identifiers, application log records, and **error message text**.

None of these has a key in the emitted vocabulary, so no code path can emit them.

Error messages are excluded permanently and on purpose. Messages routinely interpolate whatever failed — `ENOENT: ... open '/var-pryv/users/<id>/...'`, "user &lt;email&gt; not found", validation errors quoting the submitted value. The error *code* travels; the message stays in your own logs, where identifying data belongs.

Stack frames are rebuilt rather than filtered. Each frame is decomposed into a function name and a source location, both checked against an allow-list, then reassembled. A frame that is not a repository-relative location or a Node internal is replaced by `at <external>`, so paths from outside the installation — a global module directory, an operator's own plugin folder, a home directory — are never emitted even in part.

## How anonymous is it, exactly

The claim is: **anonymous by construction, with a residual correlation risk at very low traffic volumes.** We state it that way rather than as an unqualified guarantee, because the qualification is real.

Two design choices carry it beyond simply omitting identifiers:

- **Error reports are aggregated by fault and stamped at the reporting interval**, not at the instant of failure. A precise timestamp is a re-identification handle even when the content is clean: "this method failed at 14:32:07.123 on this instance" singles out one action to anyone holding a second timestamped signal — your own audit log, for instance. The deliberate cost is that sub-interval ordering and exact error times are not available from telemetry.
- **The instance identifier is the machine hostname**, never derived from your service URL or DNS domain. In DNS-based deployments user-facing hosts are `<username>.<domain>`, so a URL-derived hostname would have attached a username to every datapoint.

**The residual**: on a very low-traffic instance, "one error in this interval" can still correlate to the only active user. That follows from traffic volume rather than from what is emitted, so no schema change removes it. Widening [the reporting interval](#the-reporting-interval) reduces it.

If your deployment cannot accept even that, point the endpoint at a collector inside your own infrastructure — then no third party is involved at all.

## Choosing a backend

Any service that ingests OTLP/HTTP works: New Relic, Grafana, Datadog, Honeycomb, Elastic, or an OpenTelemetry Collector you run yourself. The platform sends the same payload to all of them, so the data-protection posture does not vary by vendor.

A backend that only speaks gRPC or a proprietary protocol can be reached by putting an OpenTelemetry Collector in front of it. Running that collector inside your own trust boundary is also the recommended pattern when you want monitoring without a third-party processor.

## Enabling it

From any core, with PlatformDB reachable:

```bash
# 1. where telemetry goes (the standard OTLP paths /v1/metrics and
#    /v1/logs are appended to this base URL)
node bin/observability.js set-endpoint https://otlp.eu01.nr-data.net

# 2. whatever auth header that backend expects, stored encrypted at rest
node bin/observability.js set-header api-key YOUR-KEY-HERE

# 3. a label to tell your deployments apart in the backend's UI
node bin/observability.js set-app-name 'open-pryv.io (example.com)'

# 4. turn it on, then rolling-restart every core
node bin/observability.js enable
```

Plain `http://` is accepted when the collector is host-local: loopback, private (RFC1918) or link-local space, so a collector running as a sidecar container reached on the bridge gateway (`http://172.17.0.1:4318`, say) needs no certificate for a hop that never crosses a network. Cleartext to any routable address is refused, and the same rule is applied by the emitter at startup, not only by this command, so writing the value straight into PlatformDB or exporting it in the environment cannot get plaintext telemetry onto the wire.

Check the effective configuration at any time — credential values are never echoed:

```bash
node bin/observability.js show
```

`show` also prints the emitted surface, so an operator can answer "what does my backend see?" without reading source.

> Keep the app name free of anything identifying. It is the one label you choose rather than the platform, it is validated only for shape, and it is attached to every batch.

## The reporting interval

```bash
node bin/observability.js set-interval 600     # seconds; 60-3600, default 300
```

This is a **privacy control**, not only a tuning knob. It sets the granularity at which activity is observable, and it is the only lever on the low-traffic residual described above. Longer intervals weaken correlation and slow alerting; shorter intervals do the reverse. Values outside 60-3600 are clamped.

## Verifying what your backend holds

Do not take this page's word for it. After enabling and restarting, ask the backend to enumerate what it actually received, and scope the query to a time window that starts after your restart — older data will otherwise answer for the previous configuration.

With New Relic, for example:

```sql
-- every metric name the account holds for this deployment
SELECT uniques(metricName) FROM Metric
WHERE service.name = 'open-pryv.io (example.com)' SINCE '<restart time>'

-- every attribute key present on those metrics
SELECT keyset() FROM Metric
WHERE service.name = 'open-pryv.io (example.com)' SINCE '<restart time>'
```

Enumerate rather than spot-check for absence: a query for a specific identifier returning zero proves only that you guessed the identifier's shape correctly, whereas listing every key present proves the surface. The result should contain only the metric names and label keys listed under [What is sent](#what-is-sent).

Watch `telemetry.dropped` as well. It should normally be zero or near it; a rising count means datapoints are being refused, and the `reason` label says why.

## Rotating credentials

```bash
node bin/observability.js set-header api-key NEW-KEY      # overwrite
node bin/observability.js clear-headers                   # remove all
```

Then rolling-restart every core. Headers are stored AES-256-GCM encrypted at rest, with key material derived from the platform admin key.

## Disabling

```bash
node bin/observability.js disable
```

Then rolling-restart. For an immediate local kill switch that does not depend on PlatformDB, set `observability.enabled: false` in a core's own configuration — a local `false` always wins, on that core, at its next start.

## Caveats

- **Changes need a rolling restart.** Workers receive the resolved configuration at fork time; there is no live reconfiguration.
- **Coverage is the API method surface.** Requests are measured where the core dispatches API methods, which covers HTTP and socket calls alike. Background work (certificate renewal, webhook delivery, mail) is not instrumented yet.
- **Metrics are delta-reported per interval**, so a backend configured to expect cumulative values will need its usual OTLP delta handling.
- **Aggregation trades detail for privacy**, by decision. If you need the exact sequence of an incident, the source is your own logs, not this telemetry.
- **A failing backend never affects the API.** Send failures are counted and logged locally; buffers are bounded and drop rather than grow.
- **Up to one interval of telemetry is lost on restart.** Whatever has been aggregated but not yet sent is discarded when a worker stops, so a rolling restart leaves a gap of up to one reporting interval. Deliberate: buffered telemetry is not worth delaying a shutdown for.
- **Third-party processing.** Understand your jurisdiction's requirements before shipping metadata to a vendor cloud, and prefer a self-hosted collector if you would rather not add a processor at all.
- **Ingested telemetry usually cannot be deleted on demand.** Most vendors have no self-service purge; data expires with the account's retention window. Worth knowing before enabling, because a misconfiguration cannot be taken back.
- **Earlier versions behaved differently.** Releases before this one used an in-process vendor agent, and a configuration defect meant that agent ran on its own defaults: request URLs, the `Host` header, route parameters carrying the username, and forwarded application log records all reached the vendor. If you enabled observability on an earlier version, assume that was the case for as long as it was on, and check what your account holds.
