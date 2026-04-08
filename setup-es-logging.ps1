# ILM config:    https://www.elastic.co/guide/en/elasticsearch/reference/current/ilm-put-lifecycle.html
# index config:  https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-indices-get-index-template

$ErrorActionPreference = "Stop"

$portForward = Start-Process -FilePath "kubectl" `
    -ArgumentList @("port-forward", "svc/elasticsearch-master", "9200:9200", "-n", "elk") `
    -PassThru `
    -WindowStyle Hidden

Start-Sleep -Seconds 5

$tempDir = Join-Path $env:TEMP "dung-lab-es-setup"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

function Write-JsonFile {
    param(
        [string]$Path,
        [string]$Content
    )
    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

function Invoke-CurlJson {
    param(
        [string]$Method,
        [string]$Path,
        [string]$FilePath
    )
    if ($FilePath) {
        & curl.exe -s -k -u "elastic:1qK@B5mQ" -X $Method "https://localhost:9200$Path" `
            -H "Content-Type: application/json" `
            --data-binary "@$FilePath"
    } else {
        & curl.exe -s -k -u "elastic:1qK@B5mQ" -X $Method "https://localhost:9200$Path"
    }
}

$files = @{
    "ilm.json" = @'
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_age": "1d",
            "max_primary_shard_size": "5gb"
          }
        }
      },
      "delete": {
        "min_age": "7d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
'@
    "dung-fe-template.json" = @'
{
  "index_patterns": ["dung-fe-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.lifecycle.name": "logs-lab-policy",
      "index.lifecycle.rollover_alias": "dung-fe-write"
    },
    "mappings": {
      "dynamic": false,
      "properties": {
        "@timestamp": { "type": "date" },
        "service": { "type": "keyword" },
        "level": { "type": "keyword" },
        "event": { "type": "keyword" },
        "environment": { "type": "keyword" },
        "message": { "type": "text" },
        "path": { "type": "keyword" },
        "user_id": { "type": "keyword" },
        "session_id": { "type": "keyword" },
        "response_time_ms": { "type": "integer" },
        "kubernetes": {
          "properties": {
            "namespace_name": { "type": "keyword" },
            "pod_name": { "type": "keyword" },
            "container_name": { "type": "keyword" },
            "host": { "type": "keyword" }
          }
        }
      }
    }
  },
  "priority": 500
}
'@
    "dung-be-template.json" = @'
{
  "index_patterns": ["dung-be-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.lifecycle.name": "logs-lab-policy",
      "index.lifecycle.rollover_alias": "dung-be-write"
    },
    "mappings": {
      "dynamic": false,
      "properties": {
        "@timestamp": { "type": "date" },
        "service": { "type": "keyword" },
        "level": { "type": "keyword" },
        "event": { "type": "keyword" },
        "environment": { "type": "keyword" },
        "message": { "type": "text" },
        "endpoint": { "type": "keyword" },
        "request_id": { "type": "keyword" },
        "status_code": { "type": "integer" },
        "error_code": { "type": "keyword" },
        "kubernetes": {
          "properties": {
            "namespace_name": { "type": "keyword" },
            "pod_name": { "type": "keyword" },
            "container_name": { "type": "keyword" },
            "host": { "type": "keyword" }
          }
        }
      }
    }
  },
  "priority": 500
}
'@
    "dung-db-template.json" = @'
{
  "index_patterns": ["dung-db-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.lifecycle.name": "logs-lab-policy",
      "index.lifecycle.rollover_alias": "dung-db-write"
    },
    "mappings": {
      "dynamic": false,
      "properties": {
        "@timestamp": { "type": "date" },
        "service": { "type": "keyword" },
        "level": { "type": "keyword" },
        "event": { "type": "keyword" },
        "environment": { "type": "keyword" },
        "message": { "type": "text" },
        "db_name": { "type": "keyword" },
        "query_type": { "type": "keyword" },
        "duration_ms": { "type": "integer" },
        "db_user": { "type": "keyword" },
        "kubernetes": {
          "properties": {
            "namespace_name": { "type": "keyword" },
            "pod_name": { "type": "keyword" },
            "container_name": { "type": "keyword" },
            "host": { "type": "keyword" }
          }
        }
      }
    }
  },
  "priority": 500
}
'@
    "dung-web-template.json" = @'
{
  "index_patterns": ["dung-web-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.lifecycle.name": "logs-lab-policy",
      "index.lifecycle.rollover_alias": "dung-web-write"
    },
    "mappings": {
      "dynamic": false,
      "properties": {
        "@timestamp": { "type": "date" },
        "service": { "type": "keyword" },
        "level": { "type": "keyword" },
        "event": { "type": "keyword" },
        "environment": { "type": "keyword" },
        "message": { "type": "text" },
        "method": { "type": "keyword" },
        "path": { "type": "keyword" },
        "status_code": { "type": "integer" },
        "client_ip": { "type": "ip" },
        "kubernetes": {
          "properties": {
            "namespace_name": { "type": "keyword" },
            "pod_name": { "type": "keyword" },
            "container_name": { "type": "keyword" },
            "host": { "type": "keyword" }
          }
        }
      }
    }
  },
  "priority": 500
}
'@
    "dung-fe-bootstrap.json" = @'
{
  "aliases": {
    "dung-fe-write": {
      "is_write_index": true
    }
  }
}
'@
    "dung-be-bootstrap.json" = @'
{
  "aliases": {
    "dung-be-write": {
      "is_write_index": true
    }
  }
}
'@
    "dung-db-bootstrap.json" = @'
{
  "aliases": {
    "dung-db-write": {
      "is_write_index": true
    }
  }
}
'@
    "dung-web-bootstrap.json" = @'
{
  "aliases": {
    "dung-web-write": {
      "is_write_index": true
    }
  }
}
'@
}

foreach ($entry in $files.GetEnumerator()) {
    Write-JsonFile -Path (Join-Path $tempDir $entry.Key) -Content $entry.Value
}

try {
    Invoke-CurlJson -Method PUT -Path "/_ilm/policy/logs-lab-policy" -FilePath (Join-Path $tempDir "ilm.json")
    Invoke-CurlJson -Method PUT -Path "/_index_template/dung-fe-template" -FilePath (Join-Path $tempDir "dung-fe-template.json")
    Invoke-CurlJson -Method PUT -Path "/_index_template/dung-be-template" -FilePath (Join-Path $tempDir "dung-be-template.json")
    Invoke-CurlJson -Method PUT -Path "/_index_template/dung-db-template" -FilePath (Join-Path $tempDir "dung-db-template.json")
    Invoke-CurlJson -Method PUT -Path "/_index_template/dung-web-template" -FilePath (Join-Path $tempDir "dung-web-template.json")
    Invoke-CurlJson -Method PUT -Path "/dung-fe-000001" -FilePath (Join-Path $tempDir "dung-fe-bootstrap.json")
    Invoke-CurlJson -Method PUT -Path "/dung-be-000001" -FilePath (Join-Path $tempDir "dung-be-bootstrap.json")
    Invoke-CurlJson -Method PUT -Path "/dung-db-000001" -FilePath (Join-Path $tempDir "dung-db-bootstrap.json")
    Invoke-CurlJson -Method PUT -Path "/dung-web-000001" -FilePath (Join-Path $tempDir "dung-web-bootstrap.json")
    Write-Host "Elasticsearch ILM, templates, and aliases have been configured."
}
finally {
    if ($portForward -and !$portForward.HasExited) {
        Stop-Process -Id $portForward.Id -Force
    }
}
