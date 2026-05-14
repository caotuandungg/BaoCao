# Logging Onboarding Kit

Bo kit nay dung de onboarding mot app/log source moi vao Log Center voi schema JSON toi gian.

Muc tieu:

- Co mot log schema chung, de doc va de validate.
- App/doi tac co the dung Fluent Bit, Filebeat, Vector, hoac Logstash.
- Agent doc log JSON tu file va gui vao Kafka gateway.
- Log Center noi bo validate/route log ve Elasticsearch index phu hop.

Pipeline khuyen nghi:

```text
Application
  -> local log file/stdout JSON
  -> log agent
  -> Kafka topic
  -> Logstash internal
  -> Elasticsearch
  -> Kibana
```

## Thu muc

```text
schema/log-schema-v1.md
schema/log-schema-v1.schema.json
schema/sample-valid-log.json
schema/sample-invalid-log.json
agents/.env.example
agents/fluent-bit/fluent-bit.conf
agents/fluent-bit/parsers.conf
agents/filebeat/filebeat.yml
agents/vector/vector.toml
agents/logstash/partner-to-kafka.conf
```

## Schema toi gian

Moi log event can co cac field bat buoc:

```text
@timestamp
service
environment
level
message
```

Field optional hay dung:

```text
event
status_code
endpoint
path
method
duration_ms
```

Vi du log hop le:

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

## Cach dung nhanh voi Fluent Bit

1. App ghi log JSON vao file, vi du:

```text
/var/log/app/app.log
```

2. Sua `agents/.env.example` thanh thong tin app that.

3. Cau hinh Fluent Bit theo:

```text
agents/fluent-bit/fluent-bit.conf
agents/fluent-bit/parsers.conf
agents/fluent-bit/enrich.lua
```

4. Kiem tra output trong Kafka co cac field:

```text
@timestamp
service
environment
level
message
```

## Trach nhiem

Ben Log Center:

- So huu schema.
- So huu Kafka topic contract.
- So huu rule validate/route noi bo.
- Cung cap config mau cho agent pho bien.

Ben tich hop/doi tac:

- App log dung schema toi gian.
- Agent doc log va gui vao Kafka dung topic.
- Khong tu route vao Elasticsearch noi bo cua Log Center.
