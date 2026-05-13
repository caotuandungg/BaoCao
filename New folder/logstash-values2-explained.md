# Giai thich `logstash-values2.yaml` (lines 81-261)

Tai lieu nay giai thich chi tiet phan pipeline trong:

- `10-filter-cilium-agent.conf`
- `11-filter-tetragon.conf`
- `12-filter-keep-selected.conf`
- dong mo dau cua `13-filter-tetragon-export.conf`

Muc tieu la giup doc file de hieu "moi doan dang lam gi", khong can phai nho het cu phap Logstash ngay tu dau.

---

## 1. Buc tranh tong the

Phan pipeline nay dang lam viec theo flow sau:

1. Doc event log tu input `file`
2. Lay ra duong dan file log (`source_path`)
3. Dua vao nhanh xu ly phu hop:
   - `cilium-agent`
   - `tetragon`
   - `tetragon-operator`
   - `export-stdout` (duoc giu lai o block chon nguon)
4. Boc cac field can dung:
   - `service_name`
   - `timestamp`
   - `level`
   - `msg`
5. Xoa field phu
6. Drop cac log khong thuoc nhom da chon

---

## 2. `10-filter-cilium-agent.conf`

### Dong 81

```conf
10-filter-cilium-agent.conf: |
```

Day la ten file `.conf` duoc nhung vao `logstash-values2.yaml`.

---

### Dong 82-83

```conf
filter {
  if [type] == "container" {
```

Y nghia:

- vao block `filter`
- chi xu ly event co `type = container`

Noi cach khac, block nay danh cho log doc tu file container.

---

### Dong 84-90

```conf
# Chuan hoa duong dan file log de dung chung o cac buoc sau
ruby {
  code => '
    source_path = event.get("path") || event.get("[log][file][path]") || event.get("[file][path]")
    event.set("[@metadata][source_path]", source_path) if source_path
  '
}
```

Y nghia:

- Logstash co the dat duong dan file log o nhieu field khac nhau:
  - `path`
  - `[log][file][path]`
  - `[file][path]`
- doan nay thu lay lan luot field nao co gia tri truoc thi dung
- sau do ghi ve mot cho chung:
  - `[@metadata][source_path]`

Muc dich:

- cac buoc sau khong can check 3 cho nua
- chi can doc:
  - `[@metadata][source_path]`

Luu y:

- `@metadata` la vung metadata noi bo cua Logstash
- thuong khong day ra Elasticsearch

---

### Dong 92-93

```conf
# Chi xu ly log tu container cilium-agent trong namespace kube-system
if [@metadata][source_path] =~ /_kube-system_cilium-agent-.*\.log$/ {
```

Y nghia:

- chi cho event di tiep neu ten file log khop regex nay
- regex nay chon dung log file cua:
  - namespace `kube-system`
  - container `cilium-agent`

Vi du file hop le:

```text
/var/log/containers/cilium-jpjnk_kube-system_cilium-agent-....log
```

Neu khong khop, block nay bo qua event.

---

### Dong 94-100

```conf
# Lay raw log goc de parse on dinh hon
ruby {
  code => '
    raw_message = event.get("[event][original]") || event.get("message")
    event.set("[@metadata][raw_message]", raw_message) if raw_message
  '
}
```

Y nghia:

- uu tien lay log tho tu:
  - `[event][original]`
- neu khong co thi fallback sang:
  - `message`
- sau do dua vao:
  - `[@metadata][raw_message]`

Muc dich:

- cac buoc parse ben duoi chi can dung 1 field chung
- khong phai viet lai `event.get("[event][original]") || event.get("message")` nhieu lan

---

### Dong 102-110

```conf
# Boc lop CRI va tach cac field key=value chinh cua cilium-agent
grok {
  match => {
    "[@metadata][raw_message]" => [
      "^%{TIMESTAMP_ISO8601:cri_timestamp} %{WORD:stream} %{WORD:cri_flags} time=%{TIMESTAMP_ISO8601:timestamp} level=%{WORD:level} msg=\"%{DATA:msg}\"(?: module=%{NOTSPACE:module})?(?: %{GREEDYDATA:extra_fields})?$",
      "^%{TIMESTAMP_ISO8601:cri_timestamp} %{WORD:stream} %{WORD:cri_flags} %{GREEDYDATA:app_message}$"
    ]
  }
}
```

Y nghia:

- `grok` dang co 2 pattern

#### Pattern 1

Co gang parse truc tiep mot dong `cilium-agent` "dep", vi du:

```text
2026-05-13T04:43:53Z stdout F time=2026-05-13T04:43:53Z level=info msg="Successful endpoint creation" module=agent....
```

No tach ra:

- `cri_timestamp`
- `stream`
- `cri_flags`
- `timestamp`
- `level`
- `msg`
- `module`
- `extra_fields` (neu con phan du)

#### Pattern 2

Neu pattern 1 khong an duoc, pattern 2 se:

- boc lop CRI ben ngoai
- giu lai toan bo phan con lai vao:
  - `app_message`

Muc dich:

- uu tien parse dep ngay tu dau
- neu khong duoc thi van giu lai noi dung de parse tiep bang cach khac

---

### Dong 112-121

```conf
# Neu grok fallback thi dung kv de lay them cac field key=value
if ![timestamp] and [app_message] {
  kv {
    source => "app_message"
    field_split_pattern => " (?=\\w+=)"
    value_split => "="
    trim_value => "\""
    include_keys => ["time", "level", "module", "msg"]
  }
}
```

Y nghia:

- neu `grok` chua lay duoc `timestamp`
- va co `app_message`
- thi dung plugin `kv`

Plugin `kv` phu hop voi log kieu:

```text
time=... level=info msg="..." module=...
```

No se co gang tach ra:

- `time`
- `level`
- `module`
- `msg`

Y nghia cua cac option:

- `source => "app_message"`
  - parse tren field `app_message`
- `field_split_pattern => " (?=\\w+=)"`
  - cat field khi gap dau cach ma phia sau la `key=`
- `value_split => "="`
  - cat key va value theo dau `=`
- `trim_value => "\""`
  - bo dau `"` bao quanh value
- `include_keys`
  - chi giu nhung key can thiet

---

### Dong 123-128

```conf
# Gan ten service de Kibana nhin duoc theo nhom log
mutate {
  add_field => {
    "service_name" => "cilium-agent"
  }
}
```

Y nghia:

- gan nhan:
  - `service_name = cilium-agent`

Muc dich:

- sau nay tren Kibana co the loc nhanh theo:
  - `service_name`

---

### Dong 130-137

```conf
# Dong bo ten field thoi gian neu kv tra ve field time
if ![timestamp] and [time] {
  mutate {
    rename => {
      "time" => "timestamp"
    }
  }
}
```

Y nghia:

- trong nhanh `kv`, co khi log tach ra field `time`
- nhung pipeline muon thong nhat ten field la:
  - `timestamp`
- vi vay neu chua co `timestamp` ma co `time`, thi doi ten `time` thanh `timestamp`

---

### Dong 139-155

```conf
# Don cac field phu sau khi parse xong
mutate {
  remove_field => [
    "message",
    "app_message",
    "cri_timestamp",
    "cri_flags",
    "time",
    "path",
    "host",
    "type",
    "event",
    "@version",
    "extra_fields",
    "[@metadata][raw_message]"
  ]
}
```

Y nghia:

- sau khi da lay duoc field chinh, xoa bot field trung gian va field phu

Muc tieu:

- document trong ES gon hon
- de doc hon tren Kibana

Luu y:

- `message`, `app_message`, `extra_fields` la field trung gian
- `cri_timestamp`, `cri_flags` la field tam de parse
- `[@metadata][raw_message]` chi dung noi bo

---

### Dong 156-158

```conf
    }
  }
}
```

Dong block `if`, dong `if [type] == "container"`, va dong `filter`.

---

## 3. `11-filter-tetragon.conf`

### Dong 160

```conf
11-filter-tetragon.conf: |
```

Ten file `.conf` cho nhanh xu ly `tetragon`.

---

### Dong 161-168

```conf
filter {
  if [type] == "container" {
    # Chuan hoa duong dan file log de dung chung o cac buoc sau
    ruby {
      code => '
        source_path = event.get("path") || event.get("[log][file][path]") || event.get("[file][path]")
        event.set("[@metadata][source_path]", source_path) if source_path
      '
    }
```

Doan nay co y nghia giong ben `cilium-agent`:

- chi xu ly log `container`
- lay duong dan file log
- dua ve `[@metadata][source_path]`

---

### Dong 171-172

```conf
# Chi xu ly log tu tetragon va tetragon-operator trong kube-system
if [@metadata][source_path] =~ /_kube-system_(tetragon|tetragon-operator)-.*\.log$/ {
```

Y nghia:

- chi xu ly 2 nhom file:
  - `tetragon`
  - `tetragon-operator`

Khong xu ly:

- `export-stdout`
- cac container khac

---

### Dong 173-179

```conf
# Lay raw log goc de parse on dinh hon
ruby {
  code => '
    raw_message = event.get("[event][original]") || event.get("message")
    event.set("[@metadata][raw_message]", raw_message) if raw_message
  '
}
```

Y nghia:

- giong nhanh `cilium-agent`
- lay log tho that su
- luu vao `[@metadata][raw_message]`

---

### Dong 181-186

```conf
# Boc lop CRI ben ngoai, giu lai phan noi dung app
grok {
  match => {
    "[@metadata][raw_message]" => "^%{TIMESTAMP_ISO8601:cri_timestamp} %{WORD:stream} %{WORD:cri_flags} %{GREEDYDATA:app_message}$"
  }
}
```

Y nghia:

- tach lop CRI ngoai cung cua 1 dong log container

No se lay ra:

- `cri_timestamp`
- `stream`
- `cri_flags`
- `app_message`

Trong do:

- `app_message` = toan bo phan noi dung log ben trong app

Vi du:

```text
2026-05-06T08:46:38Z stdout F level=warn msg="adding tracing policy failed"
```

thi:

- `cri_timestamp` = `2026-05-06T08:46:38Z`
- `stream` = `stdout`
- `cri_flags` = `F`
- `app_message` = `level=warn msg="adding tracing policy failed"`

---

### Dong 188-231

```conf
# Suy ra service, level, msg va timestamp theo kieu tong quat cho tetragon
ruby {
  code => '
    source_path = event.get("[@metadata][source_path]")
    if source_path
      file_name = File.basename(source_path)
      if file_name.include?("_kube-system_tetragon-operator-")
        event.set("service_name", "tetragon-operator")
      elsif file_name.include?("_kube-system_tetragon-")
        event.set("service_name", "tetragon")
      end
    end

    app_message = event.get("app_message")
    raw = app_message.is_a?(String) && !app_message.empty? ? app_message : event.get("message")

    if raw.is_a?(String)
      if raw =~ /\blevel=(\w+)/i
        event.set("level", Regexp.last_match(1).downcase)
      elsif raw =~ /\b(INFO|WARN|WARNING|ERROR|DEBUG|TRACE|FATAL)\b/i
        normalized = Regexp.last_match(1).downcase
        normalized = "warn" if normalized == "warning"
        event.set("level", normalized)
      else
        stream = event.get("stream")
        event.set("level", stream == "stderr" ? "error" : "info")
      end
    end

    level = event.get("level")
    event.set("level", level.to_s.downcase) if level

    if raw.is_a?(String)
      if raw =~ /\bmsg="([^"]+)"/
        event.set("msg", Regexp.last_match(1))
      elsif raw =~ /\bmsg=([^\s].*)/
        event.set("msg", Regexp.last_match(1).strip)
      else
        event.set("msg", raw)
      end
    end

    event.set("timestamp", event.get("cri_timestamp"))
  '
}
```

Day la block `ruby` quan trong nhat cua nhanh `tetragon`.

No dang lam 4 viec chinh:

### 3.1. Suy ra `service_name`

Doan nay:

```ruby
source_path = event.get("[@metadata][source_path]")
if source_path
  file_name = File.basename(source_path)
  if file_name.include?("_kube-system_tetragon-operator-")
    event.set("service_name", "tetragon-operator")
  elsif file_name.include?("_kube-system_tetragon-")
    event.set("service_name", "tetragon")
  end
end
```

Y nghia:

- doc ten file log
- neu file thuoc `tetragon-operator` thi gan:
  - `service_name = tetragon-operator`
- neu file thuoc `tetragon` thi gan:
  - `service_name = tetragon`

Tai sao lam vay:

- trong nhom `tetragon` muon tach duoc service logic
- ten file la cach de nhat de nhan biet

---

### 3.2. Chon noi dung log de parse

Doan nay:

```ruby
app_message = event.get("app_message")
raw = app_message.is_a?(String) && !app_message.empty? ? app_message : event.get("message")
```

Y nghia:

- uu tien parse tu `app_message`
- neu `app_message` khong hop le thi fallback sang `message`

Tai sao:

- `app_message` da duoc boc bo lop CRI ben ngoai, sach hon

---

### 3.3. Suy ra `level`

Doan nay:

```ruby
if raw.is_a?(String)
  if raw =~ /\blevel=(\w+)/i
    event.set("level", Regexp.last_match(1).downcase)
  elsif raw =~ /\b(INFO|WARN|WARNING|ERROR|DEBUG|TRACE|FATAL)\b/i
    normalized = Regexp.last_match(1).downcase
    normalized = "warn" if normalized == "warning"
    event.set("level", normalized)
  else
    stream = event.get("stream")
    event.set("level", stream == "stderr" ? "error" : "info")
  end
end
```

Y nghia:

- neu log co dang:
  - `level=warn`
  - `level=info`
  thi lay truc tiep
- neu khong, thu bat cac chu:
  - `INFO`, `WARN`, `WARNING`, `ERROR`, `DEBUG`, `TRACE`, `FATAL`
- neu van khong co, fallback:
  - `stderr` -> `error`
  - con lai -> `info`

Muc tieu:

- co gang tao ra field `level` du log tetragon khong dong deu 100%

Doan tiep:

```ruby
level = event.get("level")
event.set("level", level.to_s.downcase) if level
```

chi de chuan hoa `level` ve chu thuong.

---

### 3.4. Suy ra `msg`

Doan nay:

```ruby
if raw.is_a?(String)
  if raw =~ /\bmsg="([^"]+)"/
    event.set("msg", Regexp.last_match(1))
  elsif raw =~ /\bmsg=([^\s].*)/
    event.set("msg", Regexp.last_match(1).strip)
  else
    event.set("msg", raw)
  end
end
```

Y nghia:

- neu co dang:
  - `msg="..."`
  thi lay phan trong dau nhay
- neu chi co dang:
  - `msg=...`
  thi lay phan sau dau `=`
- neu ca hai deu khong co, lay ca `raw` lam `msg`

Muc tieu:

- dam bao event van co noi dung thong diep de hien thi tren Kibana

---

### 3.5. Dat `timestamp`

Doan cuoi:

```ruby
event.set("timestamp", event.get("cri_timestamp"))
```

Y nghia:

- voi nhanh `tetragon`, field `timestamp` duoc lay tu thoi gian CRI o dau dong log
- cach nay don gian va on dinh

---

### Dong 234-248

```conf
# Don cac field phu sau khi parse xong
mutate {
  remove_field => [
    "message",
    "app_message",
    "cri_timestamp",
    "cri_flags",
    "path",
    "host",
    "type",
    "event",
    "@version",
    "[@metadata][raw_message]"
  ]
}
```

Y nghia:

- giong nhanh `cilium-agent`
- xoa field tam va field phu sau khi parse xong

Khac biet nho:

- nhanh `tetragon` khong co `extra_fields` va `time` trong danh sach remove o day

---

### Dong 249-251

```conf
    }
  }
}
```

Dong cac block `if` va `filter`.

---

## 4. `12-filter-keep-selected.conf`

### Dong 253

```conf
12-filter-keep-selected.conf: |
```

Ten file `.conf` de loc nguon log cuoi cung.

---

### Dong 254-259

```conf
filter {
  # Chi giu lai cac nguon log da chon cho pipeline nay
  if ![@metadata][source_path] or [@metadata][source_path] !~ /_kube-system_(cilium-agent|tetragon|tetragon-operator|export-stdout)-.*\.log$/ {
    drop { }
  }
}
```

Y nghia:

- day la "cua chan cuoi"
- neu event khong co `source_path`
- hoac `source_path` khong thuoc mot trong 4 nhom:
  - `cilium-agent`
  - `tetragon`
  - `tetragon-operator`
  - `export-stdout`
- thi `drop`

Tac dung:

- ngan log ngoai muc tieu roi vao index
- giu cho index chi gom nhung nguon minh muon phan tich

---

## 5. Dong 261: mo dau `13-filter-tetragon-export.conf`

### Dong 261

```conf
13-filter-tetragon-export.conf: |
```

Day moi chi la dong mo dau cua file `.conf` tiep theo.

Trong range `81-261` thi chua co noi dung block `13-filter-tetragon-export.conf`, chi moi thay ten file.

---

## 6. Tong ket nhanh

Neu rut gon toan bo doan `81-261` thanh mot flow de nho, thi no la:

### Nhanh `cilium-agent`

1. Lay `source_path`
2. Chi nhan file `cilium-agent`
3. Lay raw log
4. Dung `grok`
5. Neu can thi dung `kv`
6. Gan `service_name`
7. Chuan hoa `timestamp`
8. Xoa field phu

### Nhanh `tetragon`

1. Lay `source_path`
2. Chi nhan file `tetragon` va `tetragon-operator`
3. Lay raw log
4. Boc lop CRI
5. Dung `ruby` suy ra:
   - `service_name`
   - `level`
   - `msg`
   - `timestamp`
6. Xoa field phu

### Block chon nguon cuoi

1. Neu khong phai 1 trong cac nguon da chon
2. Thi `drop`

---

## 7. Cach doc file de do roi hon

Neu lan sau mo lai file ma thay dai, ban co the doc theo thu tu nay:

1. Xem regex dang chon file nao
2. Xem raw log duoc lay tu dau
3. Xem field nao duoc tao ra
4. Xem field nao bi xoa
5. Xem block `drop` co giu lai nguon dung khong

Chi can bam sat 5 cau hoi nay la se de doc hon rat nhieu.
