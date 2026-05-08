# Logging Onboarding Kit

Bo kit nay dung de onboarding mot app/log source moi vao Log Center.

Muc tieu:

- Co mot log schema chung, doc lap voi agent.
- App/doi tac co the dung Fluent Bit, Filebeat, Vector, hoac Logstash.
- Agent chi can parse/enrich nhe va gui log vao Kafka gateway.
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

## Nguyen tac

Log format/schema la chuan chung. Agent config chi la cach doc va gui log theo chuan do.

Khong tao 4 format rieng cho 4 agent. Chi co 1 schema:

```text
log-schema-v1
```

Moi agent deu phai tao output JSON co cac field bat buoc:

```text
@timestamp
service
environment
level
message
log_schema.version
pipeline.stage
```

## Field chong xu ly trung

Moi log event nen co:

```json
{
  "log_schema": {
    "name": "dung-standard-log",
    "version": "1.0"
  },
  "pipeline": {
    "stage": "normalized",
    "normalized": true,
    "processed_by": ["partner-agent"]
  }
}
```

Logstash noi bo se nhin field nay de tranh parse/normalize lai nhieu lan.

## Topic khuyen nghi

```text
vm-logs-topic      log external tu VM/app ben ngoai
dung-logs-topic    log internal tu k8s/node/core services
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
```

4. Kiem tra output trong Kafka co field:

```text
log_schema.version=1.0
pipeline.stage=normalized
service=<service-name>
```

## Trach nhiem

Ben Log Center:

- So huu schema.
- So huu Kafka topic contract.
- So huu rule validate/route noi bo.
- Cung cap config mau cho agent pho bien.

Ben tich hop/doi tac:

- App log dung schema.
- Agent doc log va gui vao Kafka dung topic.
- Khong tu route vao Elasticsearch noi bo cua Log Center.
- Gan metadata `log_schema` va `pipeline`.

