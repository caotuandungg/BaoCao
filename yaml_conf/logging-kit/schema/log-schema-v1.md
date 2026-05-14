# Log Schema v1

Schema nay la contract log toi gian giua app/log agent va Log Center.

## Required Fields

| Field | Type | Example | Description |
|---|---|---|---|
| `@timestamp` | string date-time | `2026-05-07T02:00:00Z` | Thoi diem event xay ra |
| `service` | string | `payment-api` | Ten service/app |
| `environment` | string | `prod` | Moi truong: `dev`, `test`, `staging`, `prod`, `lab` |
| `level` | string | `INFO` | Log level |
| `message` | string | `Payment created` | Noi dung log chinh |

## Optional Fields

| Field | Type | Example | Description |
|---|---|---|---|
| `event` | string | `payment_created` | Loai su kien |
| `status_code` | integer | `200` | Ma trang thai HTTP neu co |
| `endpoint` | string | `/api/orders` | Endpoint/API neu co |
| `path` | string | `/login` | Duong dan request neu co |
| `method` | string | `GET` | HTTP method neu co |
| `duration_ms` | integer | `120` | Thoi gian xu ly neu co |

## Allowed Log Levels

```text
DEBUG
INFO
WARN
ERROR
FATAL
```

## Example

```json
{
  "@timestamp": "2026-05-07T02:00:00Z",
  "service": "payment-api",
  "environment": "prod",
  "level": "INFO",
  "event": "payment_created",
  "message": "Payment created successfully"
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
