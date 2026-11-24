---
title: 'Pryv.io audit configuration'
description: "How to configure the Pryv.io v2 audit feature through the unified config: outputs, filtering rules, syslog templating and performance tuning."
---


This document describes how to configure the Audit feature for your Pryv.io platform.

> **Since v2 (2026)** audit is configured entirely through the unified config (`override-config.yml` merged on top of `config/default-config.yml` at startup) under the `audit:` block. There is no longer a `platform.yml` file or admin-panel GUI — one config file, applied on core restart, is the surface for filters, syslog options and templates alike.

## Outputs

Audit data can be written to any or both of the following:

- in a dedicated **storage** where it will be indexed for [querying through the Events API](/guides/audit-logs/) (engine-pluggable; default `auditStorage` engine is SQLite)
- in the host machine's **syslog** to which you can setup your own listeners

The audit record of a call is written after the call has taken effect, on every transport (HTTP, batch calls, socket.io). If that write fails (for example the audit database is unreachable), the call keeps its answer and the core logs the failure at `error` level with its stack: `Failed to audit a batched call` for a call inside a batch, `result onEnd callback failed` for a single HTTP call, `[socket.io audit]` for socket.io. From the release after 2.0.0-rc.87 two more lines come from the audit itself: `Failed to send an audit record to syslog` and `No audit storage: audit records are not stored` (once per worker). Alert on these lines: they are the record of an audit row that could not be written.

Some calls are made by the core itself, for a flow: a delivery to an account of the same core, the one-time secret of a credential hand-off or of a third-party sign-in, the writes of an OAuth consent. From the release after 2.0.0-rc.87 they leave the same record as over HTTP, success or refusal, with the flow in `source.name` (`local-delivery`, `credential-handoff`, `sso`, `oauth2`) and no `source.ip`: no client connection made them. The lookups the core makes for itself during these flows are not recorded.

### Records that could not be written

From the release after 2.0.0-rc.87 the core also counts them, so that you can alert without reading logs:

- `GET /system/audit-status` (admin key) answers the number of records the core could not write since it started, by kind and by cause ([reference](/reference-admin/#audit-status)). Poll every core: each one counts its own. Take the answer only when `scope` is `core`: `process`, on a core started with `bin/master.js`, means that the master did not answer in time and that only one worker was counted; ask again. The count starts again when the core restarts; `since` says when.
- With [telemetry](/customer-resources/observability/) enabled, the metric `audit.records.lost` carries the same events per reporting interval.

| Cause | What happened |
|---|---|
| `storage-write-failed` | the audit storage refused or failed the write |
| `storage-unavailable` | no audit storage is available |
| `invalid-record` | the record could not be built, or is not valid |
| `syslog-failed` | the record was not handed to syslog; it is in the audit storage when its method is stored there too |

Expect zero, and alert on anything above. The counts carry no account, method or message. The `error` log lines carry the failure itself; they do not name the record for every cause. A lost record is not written again later.

Not counted: a process stopped between answering a call and writing its record; a write that never ends (a storage that hangs); a syslog delivery error reported after the call (logged as `audit syslog dropped`); what a command-line tool could not write. A restart sets the count of the status back to zero: after an audit storage outage, read the log as well.

With `audit.onUserDelete: erase` (the default), a record refused because its account was erased while the call was running is not a lost record: the erasure exists to remove it. It is logged at `warn` (`Audit record not written`). With the audit storage on PostgreSQL and the base storage on SQLite the record is not refused, and may stay.


## Filtering

For both outputs, you define which API method is logged by filtering per [method-id](/reference/#method-ids). The two filter blocks share the same shape; they live under `audit.storage.filter` and `audit.syslog.filter` in `override-config.yml`.

```yaml
audit:
  active: true
  storage:
    filter:
      methods:
        include: ['accesses.create', 'events.all']
        exclude: ['events.get']
  syslog:
    filter:
      methods:
        include: ['all']
        exclude: []
```


## Rules

### You must specify at least one of them

At least one of `include` / `exclude` must contain a valid value.

### You can aggregate per resource

The Pryv.io [API method ids](/reference/#method-ids) are built in the format `{resource}.{verb}`, for example: `events.get`.
Audit filters accept aggregation of all methods for a particular resource using `all` for the verb, for example: `events.all`.


## Examples

### log everything

```yaml
audit:
  storage:
    filter:
      methods:
        include: ['all']
        exclude: []
```

### log nothing

```yaml
audit:
  storage:
    filter:
      methods:
        include: []
        exclude: ['all']
```

### log a few API methods

```yaml
audit:
  storage:
    filter:
      methods:
        include: ['accesses.create', 'accesses.delete']
        exclude: []
```

### log everything, but a few

```yaml
audit:
  storage:
    filter:
      methods:
        include: ['all']
        exclude: ['events.get']
```

### log all events methods, but get

```yaml
audit:
  storage:
    filter:
      methods:
        include: ['events.all']
        exclude: ['events.get']
```


## Syslog

**Introductory notes about syslog:**

*The syslog protocol uses a socket to transmit messages. For Linux, this socket is a `SOCK_STREAM` UNIX socket identified by the name `/dev/log`. The syslog daemon on Ubuntu is `rsyslogd`; its configuration files are located in `/etc/rsyslog.conf` and `/etc/rsyslog.d/`. In particular, the default logging rules can be found in `/etc/rsyslog.d/50-default.conf`. These rules typically tell to which actual log files the socket messages will be piped (e.g. `/var/log/syslog`), according to the message type (see the [Syslog wiki](https://en.wikipedia.org/wiki/Syslog) for more details about Facility and Severity levels).*

When activated, Pryv.io writes to the host machine's syslog. This is useful to enable security logging for actions such as blocking an IP address after too many forbidden requests using tools like [fail2ban](https://www.fail2ban.org/wiki/index.php/Main_Page).

Syslog options are configured under `audit.syslog.options`:

```yaml
audit:
  syslog:
    options:
      host: localhost
      #port: 514
      protocol: unix
      #path: /dev/log         # defaults to /dev/log on Linux
      localhost: ''
      app_name: pryv-audit
```

A Pryv.io audit log will look like this in the syslog:

```
Oct 26 14:58:46 co1-pryv-li pryv-audit[57]: ck6j759f000011ps2octzo1ds audit-log/pryv-api createdBy:system ["access-ck6j78uj600011ss2neygkpub","action-events.get"] {"source":{"name":"http","ip":"85.5.192.175"},"action":"events.get","query":{"toTime":"9900000000","fromTime":"-9900000000","limit":"1","sortAscending":"true","state":"all"}}
```

### Templating

Templates live under `audit.syslog.formats.<key>`. The `default` key is the fallback template applied to every audit event whose type has no dedicated entry:

```yaml
audit:
  syslog:
    formats:
      default:
        template: "{userid} {type} createdBy:{createdBy} {streamIds} {content}"
        level: notice
```

Available placeholders: `{userid}`, `{type}`, `{createdBy}`, `{streamIds}`, `{content}`. `level` is one of `notice`, `warning`, `error`, `critical`, `alert`, `emerg`.

Audit event types emitted by the core:

- `audit-log/pryv-api` — successful API call
- `audit-log/pryv-api-error` — errored API call

You can define a dedicated template for either (the map key matches the part after `audit-log/`, e.g. `pryv-api-error`).

### Plugin format

Instead of a template string, a format entry can point at an external JavaScript plugin that returns `{ level, message }` (or `null` to skip):

```yaml
audit:
  syslog:
    formats:
      pryv-api-error:
        plugin: 'plugins/audit-error-formatter.js'
```

Paths are resolved relative to the core root.


## Support

You can get in touch with Pryv's support at [Open Pryv - Issues and questions](https://github.com/pryv/open-pryv.io/issues).


## Performance

Both syslog and storage logging require additional processing — we recommend activating logging only for the methods that require it.


## v1 → v2 config mapping

For operators migrating from v1:

| v1 `platform.yml` variable | v2 key in `override-config.yml` |
|---|---|
| `AUDIT_STORAGE_FILTER` | `audit.storage.filter` |
| `AUDIT_SYSLOG_FILTER` | `audit.syslog.filter` |
| `AUDIT_SYSLOG_FORMAT` | `audit.syslog.formats.default` |

In v1 the filter payload was a JSON-encoded string edited through the admin panel's *Audit settings* tab; in v2 it is plain YAML under the unified config file.


## v1 procedure (legacy)

In v1 the audit pipeline was split across two extra Docker containers in front of and behind the cores:

* **`pryv/router`** sat between NGINX and the cores (`upstream core_server { server core_router:1337; }`), tagged each request with the resolved username, and fanned writes out to `--core-audit core:3000 --core-audit core:3001`. Logging level was set with `ROUTER_LOG=info`.
* **`pryv/audit`** ran as a separate process on `:5000`, configured through `core/audit/conf/audit.json` (`core.url`, `dataFolder=/app/data`, `http.port=5000`, `logs.{prefix,console,file}`).
* **rsyslog** wrote per-username files at `/var/log/pryv/audit/%programname%/%$.username%/audit.log`, rotated monthly with `rotate 12 missingok notifempty`.
* The list of audited methods, the syslog format and the storage filter were edited through the **admin panel** *Audit settings* tab and stored as JSON-encoded strings in `config-leader/conf/platform.yml` under `AUDIT_STORAGE_FILTER`, `AUDIT_SYSLOG_FILTER` and `AUDIT_SYSLOG_FORMAT`.

None of those processes or paths exist in v2 — the audit subsystem is in-process inside the core binary, configured via the `audit.*` keys covered above. The mapping table in the previous section translates each v1 variable to its v2 key.
