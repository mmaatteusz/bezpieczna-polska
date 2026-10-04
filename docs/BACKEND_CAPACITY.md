# Backend capacity: baseline and staged changes

Keep the existing host and database. Record a baseline before enabling process
separation or moving clients to compact snapshots.

## Measurements

`node backend/scripts/measure-api.mjs https://your-api-host 04`

This sends 30 sequential read-only requests, reporting decoded response bytes,
status codes and latency percentiles. Ten samples are a baseline, not a capacity
claim. Compare from the same machine at similar times. The 333 kB figure from the
audit is a local JSON size, not necessarily bytes transferred with compression.

`GET /admin/metrics` requires the existing admin bearer token. It now reports:

- Per-route cumulative response bytes, errors and p95 of the last 1024 requests
  in that API process. Samples reset on restart; collect externally for trends.
- Outbox counts by state, oldest record age and oldest due time for pending/retry.
  DELIVERED remains the pre-existing provider acceptance label, not a handset receipt.
- Persistent worker start/completion, last success, duration, running age and
  schedule lag measured against start cadence. An absent worker row means it has
  never run; source health is still needed because adapters handle source failures.
- Filesystem capacity for `MONITOR_DISK_PATH` (default `/`). In Docker, mount the
  host filesystem to inspect the relevant host volume rather than assuming the
  container overlay measures all disks. Mount the database volume separately if
  it resides on another filesystem.
- Backup age and off-VM flag from `BACKUP_STATUS_FILE`. Missing configuration is
  NOT_CONFIGURED; unreadable/malformed status is UNAVAILABLE. Successful backup
  scripts atomically publish `/var/lib/bezpieczna-polska/monitoring/backup-status.json`.
  Mount that directory read-only into API and set the environment variable.
  `restoreVerifiedAt: null` explicitly means no verified restore is recorded.

Suggested initial alert thresholds: queued warning older than 60 seconds,
worker start lag > twice its cadence, backup older than 26 hours, free disk <20%.
Tune using baseline observations. No external alert receiver is configured by
these code changes; polling the endpoint and sending alarms is a deployment step.

## Shelter catalog

PostgreSQL stages and validates the complete incoming catalog, then atomically
deletes absent IDs and upserts only rows with different fields/JSON. The writer
lock allows ordinary SELECT through MVCC. Source health commits with the delta;
rollback preserves the last good catalog. Whole-package metadata changes inside
every shelter payload still require updating every affected row. This is not a
claim that every new source version produces a small delta.

The real PostGIS regression checks untouched rows using `xmin`, changed rows,
deletion and failed-write rollback. Run with `TEST_DATABASE_URL` on a disposable
test database; the existing production release gate already runs this suite.
SQLite retains the existing replacement path for local development.

Before a large-traffic release, also measure an 86k catalog with 0%, 1% and 100%
changes on staging, including concurrent shelter reads, WAL volume and commit
time. A local test without PostGIS cannot establish those production numbers.

## Snapshot rollout

The default `/v1/snapshot` remains unchanged. `mode=compact` omits duplicated
incident reports and shelter items, declares `omittedSections`, and retains
alerts, statuses, source freshness and shelter page metadata. Use dedicated
shelter and history endpoints for omitted details. It currently still reads the
full store snapshot, so the immediate benefit is serialization/network size,
not a claim of reduced database work. Existing APKs continue using full mode.

## Process separation on the same VM

Apply migration 3 before starting the new production binary. The default role
is `combined`, preserving the current deployment. `PROCESS_ROLE=api` serves HTTP
without automatic ingest or push dispatch. `PROCESS_ROLE=worker` runs the same
schedulers without opening a port. Manual administrator operations remain
available in API mode and must be controlled operationally during ingest.

For an initial safe rollout, start a worker using the same image, database and
credentials; worker leases prevent duplicate scheduled jobs. Then restart API
with `PROCESS_ROLE=api`. Disable the image's HTTP healthcheck for the worker
container (`--no-healthcheck`) and monitor persisted worker telemetry instead.
Retain `ENABLE_INGESTION` and `ENABLE_PUSH_DISPATCH` settings: candidate hosts
must not start production schedulers accidentally. Each process has its own
Postgres pool; account for both pools in the database connection budget.

Use the existing combined service for rollback until the split deployment has
been verified. No host settings or production API URLs change automatically.
