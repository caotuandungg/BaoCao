function env(name, default)
  local value = os.getenv(name)
  if value == nil or value == "" then
    return default
  end
  return value
end

function set_if_missing(record, key, value)
  if record[key] == nil or record[key] == "" then
    record[key] = value
  end
end

function enrich_standard_log(tag, timestamp, record)
  local producer = env("PIPELINE_PRODUCER", "fluent-bit")

  set_if_missing(record, "service", env("SERVICE_NAME", "payment-api"))
  set_if_missing(record, "environment", env("ENVIRONMENT", "prod"))
  set_if_missing(record, "tenant", env("TENANT", "partner-a"))
  set_if_missing(record, "log_scope", env("LOG_SCOPE", "external"))
  set_if_missing(record, "log_source", env("LOG_SOURCE", "external-app"))

  record["log_schema"] = record["log_schema"] or {}
  record["log_schema"]["name"] = record["log_schema"]["name"] or env("LOG_SCHEMA_NAME", "dung-standard-log")
  record["log_schema"]["version"] = record["log_schema"]["version"] or env("LOG_SCHEMA_VERSION", "1.0")

  record["pipeline"] = record["pipeline"] or {}
  record["pipeline"]["stage"] = record["pipeline"]["stage"] or "normalized"
  record["pipeline"]["normalized"] = true
  record["pipeline"]["producer"] = record["pipeline"]["producer"] or producer

  local processed_by = record["pipeline"]["processed_by"]
  if type(processed_by) ~= "table" then
    processed_by = {}
  end
  local found = false
  for _, item in ipairs(processed_by) do
    if item == producer then
      found = true
      break
    end
  end
  if not found then
    table.insert(processed_by, producer)
  end
  record["pipeline"]["processed_by"] = processed_by

  return 1, timestamp, record
end
