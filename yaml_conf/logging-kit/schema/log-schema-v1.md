# Log Schema v1

Schema nay la contract chung giua app/log agent va Log Center.

## Required Fields

| Field | Type | Example | Description |
|---|---|---|---|
| `@timestamp` | string date-time | `2026-05-07T02:00:00Z` | Thoi diem event xay ra |
| `service` | string | `payment-api` | Ten service/app |
| `environment` | string | `prod` | Moi truong: `dev`, `test`, `staging`, `prod`, `lab` |
| `level` | string | `INFO` | Log level |
| `message` | string | `Payment created` | Noi dung log chinh |
| `log_schema.name` | string | `dung-standard-log` | Ten schema |
| `log_schema.version` | string | `1.0` | Version schema |
| `pipeline.stage` | string | `normalized` | Trang thai xu ly log |
| `pipeline.normalized` | boolean | `true` | Da normalize theo schema chua |

## Optional Fields

| Field | Type | Example | Description |
|---|---|---|---|
| `event` | string | `payment_created` | Loai su kien |
| `trace_id` | string | `4bf92f...` | Trace id neu co |
| `span_id` | string | `00f067...` | Span id neu co |
| `request_id` | string | `req-12345` | Request id |
| `user_id` | string | `u001` | User id |
| `tenant` | string | `partner-a` | Tenant/doi tac |
| `log_source` | string | `vm-dung-lab` | Nguon log |
| `log_scope` | string | `external` | `external` hoac `internal` |
| `vm_name` | string | `simple-vm` | Ten VM neu log den tu VM |
| `kafka_topic` | string | `vm-logs-topic` | Topic da ghi vao |
| `pipeline.producer` | string | `fluent-bit` | Agent producer |
| `pipeline.processed_by` | array string | `["fluent-bit"]` | Cac thanh phan da xu ly |

## Allowed Log Levels

```text
DEBUG
INFO
WARN
ERROR
FATAL
```

## Pipeline Stages

```text
raw         log goc, chua parse
parsed      da parse duoc thanh field
normalized  da map ve schema chuan
enriched    da them metadata noi bo
indexed     da ghi vao Elasticsearch
```

## Example

```json
{
  "@timestamp": "2026-05-07T02:00:00Z",
  "service": "payment-api",
  "environment": "prod",
  "level": "INFO",
  "event": "payment_created",
  "message": "Payment created successfully",
  "request_id": "req-12345",
  "tenant": "partner-a",
  "log_source": "external-app",
  "log_scope": "external",
  "log_schema": {
    "name": "dung-standard-log",
    "version": "1.0"
  },
  "pipeline": {
    "stage": "normalized",
    "normalized": true,
    "producer": "fluent-bit",
    "processed_by": ["fluent-bit"]
  }
}
```

## Xu Ly Log Sai Schema

Log Center nen xu ly theo 1 trong 3 cach:

```text
drop        bo log sai schema
quarantine  ghi vao index rieng de debug
best_effort cho qua nhung gan tag _schema_invalid
```

Khuyen nghi cho production:

```text
quarantine
```

