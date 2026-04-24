# ILM config:    https://www.elastic.co/guide/en/elasticsearch/reference/current/ilm-put-lifecycle.html
# index config:  https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-indices-get-index-template

$ErrorActionPreference = "Stop"

# Scope cấu hình Elasticsearch mục tiêu (đã tách riêng cho môi trường của bạn)
$ElasticNamespace = "elk-dung"
$ElasticUser = "elastic"
$ElasticPassword = "1xNIfTEXaH0MsbQN"

# 1. Khởi động tiến trình chạy ngầm để mở "đường hầm" (port-forward) 
# Kết nối từ cổng 9200 của máy cục bộ vào cổng 9200 của dịch vụ Elasticsearch trong K8s
$portForward = Start-Process -FilePath "kubectl" `
    -ArgumentList @("port-forward", "svc/elasticsearch-master", "9200:9200", "-n", $ElasticNamespace) `
    -PassThru `
    -WindowStyle Hidden # Chạy ẩn để không làm phiền màn hình người dùng

# Tạm dừng 5 giây để đảm bảo đường hầm port-forward đã được thiết lập xong trước khi gửi dữ liệu
Start-Sleep -Seconds 5

# 2. Tạo một thư mục tạm thời trong Windows để lưu trữ các file cấu hình JSON trước khi gửi đi
$tempDir = Join-Path $env:TEMP "dung-lab-es-setup"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Hàm tiện ích dùng để ghi nội dung văn bản (JSON) vào một file cụ thể trên đĩa cứng
function Write-JsonFile {
    param(
        [string]$Path,
        [string]$Content
    )
    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

# Hàm thực thi lệnh curl để gửi dữ liệu JSON tới API của Elasticsearch
function Invoke-CurlJson {
    param(
        [string]$Method,   # Phương thức HTTP (ví dụ: PUT, POST, GET)
        [string]$Path,     # Đường dẫn API của Elasticsearch (ví dụ: /_ilm/policy)
        [string]$FilePath  # Đường dẫn tới file JSON chứa nội dung cần gửi (có thể để trống)
    )
    # Nếu có file dữ liệu kèm theo (FilePath không trống)
    if ($FilePath) {
        # Thực hiện lệnh curl với các tham số:
        # -s: Chế độ im lặng (không hiện thanh tiến trình)
        # -k: Bỏ qua kiểm tra chứng chỉ SSL (vì ta dùng self-signed cert)
        # -u: Thông tin đăng nhập (username:password)
        # -H: Khai báo định dạng dữ liệu gửi đi là JSON
        # --data-binary: Đính kèm nội dung file JSON vào yêu cầu
        & curl.exe -s -k -u "${ElasticUser}:${ElasticPassword}" -X $Method "https://localhost:9200$Path" `
            -H "Content-Type: application/json" `
            --data-binary "@$FilePath"
    } else {
        # Nếu không có file (chỉ là lệnh gửi thông tin đơn giản)
        & curl.exe -s -k -u "${ElasticUser}:${ElasticPassword}" -X $Method "https://localhost:9200$Path"
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
        "min_age": "2d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
'@
    "ilm-delete-only.json" = @'
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {}
      },
      "delete": {
        "min_age": "1d",
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
      "number_of_replicas": 1,
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
      "number_of_replicas": 1,
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
      "number_of_replicas": 1,
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
      "number_of_replicas": 1,
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
    "wk03-logs-template.json" = @'
{
  "index_patterns": ["wk03-logs-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "index.lifecycle.name": "logs-delete-only-policy"
    },
    "mappings": {
      "dynamic": true,
      "properties": {
        "@timestamp": { "type": "date" },
        "service": { "type": "keyword", "ignore_above": 256 },
        "service_name": { "type": "keyword", "ignore_above": 256 },
        "level": { "type": "keyword", "ignore_above": 256 },
        "event_dataset": { "type": "keyword", "ignore_above": 256 },
        "message": { "type": "text" },
        "event_original": { "type": "text" },
        "node_name": { "type": "keyword", "ignore_above": 256 },
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
  "priority": 400
}
'@
    "wk03-cilium-envoy-template.json" = @'
{
  "index_patterns": ["wk03-cilium-envoy-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "index.lifecycle.name": "logs-lab-policy",
      "index.lifecycle.rollover_alias": "wk03-cilium-envoy-write"
    },
    "mappings": {
      "dynamic": true,
      "properties": {
        "@timestamp": { "type": "date" },
        "message": { "type": "text" },
        "stream": { "type": "keyword", "ignore_above": 256 },
        "logtag": { "type": "keyword", "ignore_above": 256 },
        "event_original": { "type": "text" },
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
  "priority": 460
}
'@
    "wk03-cilium-template.json" = @'
{
  "index_patterns": ["wk03-cilium-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "index.lifecycle.name": "logs-lab-policy",
      "index.lifecycle.rollover_alias": "wk03-cilium-write"
    },
    "mappings": {
      "dynamic": true,
      "properties": {
        "@timestamp": { "type": "date" },
        "message": { "type": "text" },
        "stream": { "type": "keyword", "ignore_above": 256 },
        "logtag": { "type": "keyword", "ignore_above": 256 },
        "event_original": { "type": "text" },
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
  "priority": 450
}
'@
    "wk03-cinder-csi-nodeplugin-template.json" = @'
{
  "index_patterns": ["wk03-cinder-csi-nodeplugin-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "index.lifecycle.name": "logs-lab-policy",
      "index.lifecycle.rollover_alias": "wk03-cinder-csi-nodeplugin-write"
    },
    "mappings": {
      "dynamic": true,
      "properties": {
        "@timestamp": { "type": "date" },
        "message": { "type": "text" },
        "stream": { "type": "keyword", "ignore_above": 256 },
        "logtag": { "type": "keyword", "ignore_above": 256 },
        "event_original": { "type": "text" },
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
  "priority": 450
}
'@
    "wk03-k8s-events-template.json" = @'
{
  "index_patterns": ["wk03-k8s-events-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "index.lifecycle.name": "logs-lab-policy",
      "index.lifecycle.rollover_alias": "wk03-k8s-events-write"
    },
    "mappings": {
      "dynamic": true,
      "properties": {
        "@timestamp": { "type": "date" },
        "kind": { "type": "keyword", "ignore_above": 256 },
        "reason": { "type": "keyword", "ignore_above": 256 },
        "type": { "type": "keyword", "ignore_above": 256 },
        "message": { "type": "text" },
        "event_original": { "type": "text" },
        "involvedObject": {
          "properties": {
            "kind": { "type": "keyword", "ignore_above": 256 },
            "namespace": { "type": "keyword", "ignore_above": 256 },
            "name": { "type": "keyword", "ignore_above": 256 },
            "apiVersion": { "type": "keyword", "ignore_above": 256 }
          }
        },
        "reportingComponent": { "type": "keyword", "ignore_above": 256 },
        "reportingInstance": { "type": "keyword", "ignore_above": 256 }
      }
    }
  },
  "priority": 455
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
    "wk03-logs-bootstrap.json" = @'
{
  "aliases": {
    "wk03-logs-write": {
      "is_write_index": true
    }
  }
}
'@
    "wk03-cilium-envoy-bootstrap.json" = @'
{
  "aliases": {
    "wk03-cilium-envoy-write": {
      "is_write_index": true
    }
  }
}
'@
    "wk03-cilium-bootstrap.json" = @'
{
  "aliases": {
    "wk03-cilium-write": {
      "is_write_index": true
    }
  }
}
'@
    "wk03-cinder-csi-nodeplugin-bootstrap.json" = @'
{
  "aliases": {
    "wk03-cinder-csi-nodeplugin-write": {
      "is_write_index": true
    }
  }
}
'@
    "wk03-k8s-events-bootstrap.json" = @'
{
  "aliases": {
    "wk03-k8s-events-write": {
      "is_write_index": true
    }
  }
}
'@
}


# Duyệt qua danh sách dữ liệu đã khai báo và xuất chúng ra thành các file .json vật lý trong thư mục tạm
foreach ($entry in $files.GetEnumerator()) {
    Write-JsonFile -Path (Join-Path $tempDir $entry.Key) -Content $entry.Value
}

try {
    # Gọi hàm Invoke-CurlJson để đẩy lần lượt các file cấu hình vào Elasticsearch API
    # 1. Nạp ILM
    Invoke-CurlJson -Method PUT -Path "/_ilm/policy/logs-lab-policy" -FilePath (Join-Path $tempDir "ilm.json")
    Invoke-CurlJson -Method PUT -Path "/_ilm/policy/logs-delete-only-policy" -FilePath (Join-Path $tempDir "ilm-delete-only.json")
    
    # 2. Nạp các bản Index Templates cho từng dịch vụ
    Invoke-CurlJson -Method PUT -Path "/_index_template/dung-fe-template" -FilePath (Join-Path $tempDir "dung-fe-template.json")
    Invoke-CurlJson -Method PUT -Path "/_index_template/dung-be-template" -FilePath (Join-Path $tempDir "dung-be-template.json")
    Invoke-CurlJson -Method PUT -Path "/_index_template/dung-db-template" -FilePath (Join-Path $tempDir "dung-db-template.json")
    Invoke-CurlJson -Method PUT -Path "/_index_template/dung-web-template" -FilePath (Join-Path $tempDir "dung-web-template.json")
    Invoke-CurlJson -Method PUT -Path "/_index_template/wk03-logs-template" -FilePath (Join-Path $tempDir "wk03-logs-template.json")
    Invoke-CurlJson -Method PUT -Path "/_index_template/wk03-cilium-envoy-template" -FilePath (Join-Path $tempDir "wk03-cilium-envoy-template.json")
    Invoke-CurlJson -Method PUT -Path "/_index_template/wk03-cilium-template" -FilePath (Join-Path $tempDir "wk03-cilium-template.json")
    Invoke-CurlJson -Method PUT -Path "/_index_template/wk03-cinder-csi-nodeplugin-template" -FilePath (Join-Path $tempDir "wk03-cinder-csi-nodeplugin-template.json")
    Invoke-CurlJson -Method PUT -Path "/_index_template/wk03-k8s-events-template" -FilePath (Join-Path $tempDir "wk03-k8s-events-template.json")
    
    # 3. Khởi tạo các Index đầu tiên (Bootstrap) và gắn Alias ghi dữ liệu
    Invoke-CurlJson -Method PUT -Path "/dung-fe-000001" -FilePath (Join-Path $tempDir "dung-fe-bootstrap.json")
    Invoke-CurlJson -Method PUT -Path "/dung-be-000001" -FilePath (Join-Path $tempDir "dung-be-bootstrap.json")
    Invoke-CurlJson -Method PUT -Path "/dung-db-000001" -FilePath (Join-Path $tempDir "dung-db-bootstrap.json")
    Invoke-CurlJson -Method PUT -Path "/dung-web-000001" -FilePath (Join-Path $tempDir "dung-web-bootstrap.json")
    Invoke-CurlJson -Method PUT -Path "/wk03-logs-000001" -FilePath (Join-Path $tempDir "wk03-logs-bootstrap.json")
    Invoke-CurlJson -Method PUT -Path "/wk03-cilium-envoy-000001" -FilePath (Join-Path $tempDir "wk03-cilium-envoy-bootstrap.json")
    Invoke-CurlJson -Method PUT -Path "/wk03-cilium-000001" -FilePath (Join-Path $tempDir "wk03-cilium-bootstrap.json")
    Invoke-CurlJson -Method PUT -Path "/wk03-cinder-csi-nodeplugin-000001" -FilePath (Join-Path $tempDir "wk03-cinder-csi-nodeplugin-bootstrap.json")
    Invoke-CurlJson -Method PUT -Path "/wk03-k8s-events-000001" -FilePath (Join-Path $tempDir "wk03-k8s-events-bootstrap.json")
    
    Write-Host "Elasticsearch ILM, templates, and aliases have been configured."
}
finally {
    # Đảm bảo luôn đóng kết nối port-forward (kubectl) sau khi xong việc hoặc nếu có lỗi xảy ra
    if ($portForward -and !$portForward.HasExited) {
        Stop-Process -Id $portForward.Id -Force
    }
}
