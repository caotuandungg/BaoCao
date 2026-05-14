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
  set_if_missing(record, "service", env("SERVICE_NAME", "payment-api"))
  set_if_missing(record, "environment", env("ENVIRONMENT", "prod"))

  return 1, timestamp, record
end
