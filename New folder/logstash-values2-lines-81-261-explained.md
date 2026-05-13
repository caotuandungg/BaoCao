# Giai thich chi tiet `logstash-values2.yaml` (dong 81-261)

Tai lieu nay giai thich doan pipeline trong [logstash-values2.yaml](C:\Users\admin\Desktop\BaoCao\yaml_conf\logstash\logstash-values2.yaml) tu dong `81` den `261`.

Muc tieu cua doan nay la:

- xu ly log `cilium-agent`
- xu ly log `tetragon`
- giu lai dung cac nguon log da chon
- bat dau block xu ly `tetragon-export`

Luu y:

- Trong file goc, dong `261` moi chi la dong mo dau cua block `13-filter-tetragon-export.conf`.
- Phan noi dung day du cua block `13-filter-tetragon-export.conf` nam sau dong `261`, nen tai lieu nay chi giai thich den muc bat dau block do.

## Mot so khai niem can nho truoc

- `event`: object cua Logstash dang chua 1 ban ghi log hien tai.
- `event.get(...)`: doc gia tri 1 field trong event.
- `event.set(...)`: ghi gia tri vao event.
- `[@metadata]`: khu vuc field noi bo cua Logstash, dung de trung gian xu ly, thuong khong day ra Elasticsearch.
- `[log][file][path]`: cach viet field long nhau trong Logstash. Tren Kibana/ES no se hien la `log.file.path`.

## Dong 81

```yaml
10-filter-cilium-agent.conf: |
```

Y nghia:

- bat dau khai bao 1 file pipeline con ten la `10-filter-cilium-agent.conf`
- dau `|` cua YAML nghia la toan bo cac dong ben duoi se duoc giu nguyen nhu 1 khoi text
- Logstash se nap khoi text nay nhu 1 file `.conf`

## Dong 82

```conf
filter {
```

Y nghia:

- bat dau khu vuc `filter`
- moi logic trong block nay deu la xu ly trung gian, truoc khi event duoc day sang output

## Dong 83

```conf
if [type] == "container" {
```

Y nghia:

- chi xu ly cac event co field `type = container`
- field nay do `file input` o phan tren gan vao
- neu event khong phai `container` thi bo qua toan bo block ben trong

## Dong 84

Comment:

- chi la ghi chu ngan cho block Ruby ben duoi

## Dong 85-90

```conf
ruby {
  code => '
    source_path = event.get("path") || event.get("[log][file][path]") || event.get("[file][path]")
    event.set("[@metadata][source_path]", source_path) if source_path
  '
}
```

Y nghia:

- dong `85`: bat dau `ruby` filter
- dong `86`: bat dau chuoi Ruby code
- dong `87`: co gang lay duong dan file log tu nhieu field co the co
  - `path`: kieu field cu
  - `[log][file][path]`: kieu field long nhau theo ECS
  - `[file][path]`: mot truong hop fallback khac
- toan tu `||` nghia la lay gia tri dau tien khong rong/khong nil
- dong `88`: neu lay duoc `source_path` thi ghi no vao `[@metadata][source_path]`
- dong `89`: ket thuc chuoi Ruby
- dong `90`: ket thuc block Ruby

Tai sao phai lam vay:

- de cac block ben duoi khong phai lap lai viec check `path` o 3 cho khac nhau
- chi can dung thong nhat `[@metadata][source_path]`

## Dong 92-100

```conf
if [@metadata][source_path] =~ /_kube-system_cilium-agent-.*\.log$/ {
  ruby {
    code => '
      raw_message = event.get("[event][original]") || event.get("message")
      event.set("[@metadata][raw_message]", raw_message) if raw_message
    '
  }
```

Y nghia:

- dong `92`: comment mo ta block nay chi xu ly log `cilium-agent`
- dong `93`: chi cho event di tiep neu `source_path` khop regex cua file:
  - namespace `kube-system`
  - container `cilium-agent`
  - ket thuc bang `.log`
- dong `94`: comment mo ta buoc lay raw log
- dong `95-100`: them 1 block Ruby de:
  - uu tien lay log that su tu `[event][original]`
  - neu khong co thi fallback sang `message`
  - ghi gia tri nay vao `[@metadata][raw_message]`

Tai sao uu tien `[event][original]`:

- no thuong giu nguyen dong log raw
- con `message` co luc chi la field da bi plugin khac can thiep, nen khong on dinh bang

## Dong 102-110

```conf
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

- dong `102`: comment mo ta block `grok`
- dong `103`: bat dau `grok` filter
- dong `104`: `match => {` nghia la khai bao field nao se duoc regex parse
- dong `105`: field can parse la `[@metadata][raw_message]`
- dong `106`: pattern uu tien, danh cho log `cilium-agent` dep kieu:
  - `CRI timestamp`
  - `stream`
  - `flag`
  - `time=...`
  - `level=...`
  - `msg="..."`
  - co the co `module=...`
  - va them phan con lai `extra_fields`
- dong `107`: pattern fallback, chi boc lop CRI ben ngoai va gom phan con lai vao `app_message`
- dong `108-110`: dong scope block `match` va `grok`

Tai sao can 2 pattern:

- pattern 1: neu log dep, parse duoc luon `timestamp`, `level`, `msg`, `module`
- pattern 2: neu log khong dep nhu mong doi, van co `app_message` de xu ly tiep bang plugin khac

## Dong 112-121

```conf
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

- dong `112`: comment mo ta neu `grok` fallback duoc kich hoat thi se dung `kv`
- dong `113`: chi chay block nay neu:
  - chua co `timestamp`
  - va co `app_message`
- dong `114`: bat dau `kv` filter
- dong `115`: parse text tu field `app_message`
- dong `116`: moi cap `key=value` duoc tach boi dau cach, nhung chi tach o vi tri truoc 1 tu dang `key=`
- dong `117`: phan tach giua key va value la dau `=`
- dong `118`: bo dau `"` bao quanh value
- dong `119`: chi lay 4 key can thiet:
  - `time`
  - `level`
  - `module`
  - `msg`
- dong `120-121`: dong block

Tai sao can `kv`:

- log `cilium-agent` co kieu `key=value`
- neu `grok` khong match chinh xac, `kv` la cach nhe hon de van lay lai duoc field chinh

## Dong 123-128

```conf
mutate {
  add_field => {
    "service_name" => "cilium-agent"
  }
}
```

Y nghia:

- dong `123`: comment mo ta viec gan nhan service
- dong `124`: bat dau `mutate`
- dong `125-127`: them field moi:
  - `service_name = cilium-agent`
- dong `128`: dong block

Tai sao can field nay:

- de Kibana co the group/filter theo nhom log de doc hon

## Dong 130-137

```conf
if ![timestamp] and [time] {
  mutate {
    rename => {
      "time" => "timestamp"
    }
  }
}
```

Y nghia:

- neu `grok` khong tao ra `timestamp`
- nhung `kv` da tao ra `time`
- thi doi ten `time` thanh `timestamp`

Tai sao phai doi ten:

- de pipeline cuoi cung chi dung 1 ten field nhat quan la `timestamp`

## Dong 139-155

```conf
mutate {
  remove_field => [
    ...
  ]
}
```

Y nghia:

- don cac field tam sau khi parse xong
- giam clutter trong document day len ES

Y nghia cua tung field bi xoa:

- `message`: bo ban text cu sau khi da tach field can thiet
- `app_message`: field trung gian cua fallback
- `cri_timestamp`, `cri_flags`: field tam sau khi boc lop CRI
- `time`: bo vi da dong bo ve `timestamp`
- `path`, `host`, `type`, `event`, `@version`: field khong can cho schema cuoi cung nay
- `extra_fields`: phan du ra neu grok pattern 1 bat trung
- `[@metadata][raw_message]`: raw log trung gian, khong can day ra ES

## Dong 160-161

```yaml
11-filter-tetragon.conf: |
  filter {
```

Y nghia:

- bat dau file pipeline con cho `tetragon`
- van nam trong nhom `filter`

## Dong 162-169

Noi dung block nay giong voi `cilium-agent`:

- chi xu ly event co `type = container`
- chuan hoa `source_path` vao `[@metadata][source_path]`

Y nghia thuc te:

- `tetragon` va `cilium-agent` deu can 1 field chung de biet log den tu file nao

## Dong 171-179

```conf
if [@metadata][source_path] =~ /_kube-system_(tetragon|tetragon-operator)-.*\.log$/ {
  ruby {
    code => '
      raw_message = event.get("[event][original]") || event.get("message")
      event.set("[@metadata][raw_message]", raw_message) if raw_message
    '
  }
```

Y nghia:

- chi xu ly file `tetragon` hoac `tetragon-operator` trong `kube-system`
- lay raw log goc va dat vao `[@metadata][raw_message]`

Regex o dong `172` co 2 nhanh:

- `tetragon`
- `tetragon-operator`

## Dong 181-186

```conf
grok {
  match => {
    "[@metadata][raw_message]" => "^%{TIMESTAMP_ISO8601:cri_timestamp} %{WORD:stream} %{WORD:cri_flags} %{GREEDYDATA:app_message}$"
  }
}
```

Y nghia:

- boc lop CRI ben ngoai cua `tetragon`
- khong co gang parse sau vao qua som
- chi can lay:
  - `cri_timestamp`
  - `stream`
  - `cri_flags`
  - `app_message`

Tai sao don gian hon `cilium-agent`:

- `tetragon` khong dong deu bang `cilium-agent`
- de regex don gian hon, ben trong se dung Ruby de linh hoat suy ra field

## Dong 188-231

Day la block Ruby quan trong nhat cua nhanh `tetragon`.

### Dong 191-199: suy ra `service_name`

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

- doc `source_path`
- dung `File.basename(...)` de lay ten file bo phan thu muc
- neu ten file chua `tetragon-operator` thi gan:
  - `service_name = tetragon-operator`
- neu ten file chua `tetragon` thi gan:
  - `service_name = tetragon`

Tai sao khong lay tu noi dung log:

- ten file la cach chac chan nhat de biet log nay thuoc operator hay agent

### Dong 201-202: chon nguon text de parse

```ruby
app_message = event.get("app_message")
raw = app_message.is_a?(String) && !app_message.empty? ? app_message : event.get("message")
```

Y nghia:

- uu tien parse tu `app_message`
- neu `app_message` khong hop le thi fallback sang `message`

Tai sao:

- `app_message` la phan sau khi da boc lop CRI, sach hon

### Dong 204-215: suy ra `level`

```ruby
if raw.is_a?(String)
  if raw =~ /\blevel=(\w+)/i
    ...
  elsif raw =~ /\b(INFO|WARN|WARNING|ERROR|DEBUG|TRACE|FATAL)\b/i
    ...
  else
    stream = event.get("stream")
    event.set("level", stream == "stderr" ? "error" : "info")
  end
end
```

Y nghia:

- neu log co `level=...` thi lay truc tiep
- neu khong, thu tim cac chu `INFO/WARN/ERROR/...`
- neu van khong co, doan theo `stream`
  - `stderr` => `error`
  - nguoc lai => `info`

Dong `208-210` co them buoc:

- doi `warning` thanh `warn`
- muc tieu la chuan hoa gia tri `level`

### Dong 217-218: chuan hoa lai `level`

```ruby
level = event.get("level")
event.set("level", level.to_s.downcase) if level
```

Y nghia:

- neu da co `level`
- ep no thanh chu thuong de schema nhat quan

### Dong 220-228: suy ra `msg`

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

- neu co kieu:
  - `msg="..."`
  -> lay noi dung ben trong cap nhay
- neu co kieu:
  - `msg=...`
  -> lay phan sau dau `=`
- neu van khong co
  -> cho ca `raw` vao `msg`

Tai sao can fallback:

- `tetragon` co nhieu kieu log khac nhau
- fallback giup event van co `msg` de hien thi tren Kibana

### Dong 230: gan `timestamp`

```ruby
event.set("timestamp", event.get("cri_timestamp"))
```

Y nghia:

- lay timestamp o lop CRI ben ngoai
- gan thanh field chuan `timestamp`

Tai sao:

- timestamp CRI luon co mat khi file log da doc duoc
- day la nguon thoi gian on dinh nhat cho nhanh `tetragon`

## Dong 234-248

Day la block `mutate remove_field` cua `tetragon`.

No giong y tuong cua `cilium-agent`:

- xoa field tam
- giu document cuoi cung gon va de doc hon

Khac biet so voi `cilium-agent`:

- khong can xoa `time`
- khong co `extra_fields`

vi nhanh `tetragon` khong sinh ra cac field tam do.

## Dong 253-259

```conf
12-filter-keep-selected.conf: |
  filter {
    if ![@metadata][source_path] or [@metadata][source_path] !~ /_kube-system_(cilium-agent|tetragon|tetragon-operator|export-stdout)-.*\.log$/ {
      drop { }
    }
  }
```

Y nghia:

- day la bo loc cuoi de chan tat ca log khong nam trong tap nguon da chon
- neu:
  - khong co `source_path`
  - hoac `source_path` khong thuoc 1 trong 4 nhom:
    - `cilium-agent`
    - `tetragon`
    - `tetragon-operator`
    - `export-stdout`
- thi `drop {}`

Tai sao can block nay:

- tranh de cac log khac cung chui vao index `wk03-kube-system-write`
- giu schema va dashboard sach hon

## Dong 261

```yaml
13-filter-tetragon-export.conf: |
```

Y nghia:

- bat dau file pipeline con cho nhanh `tetragon-export`
- noi dung day du cua block nay nam o cac dong sau `261`, ngoai pham vi tai lieu hien tai

## Tom tat luong xu ly cua doan 81-261

1. Chuan hoa `source_path` tu metadata file input.
2. Neu la `cilium-agent`, parse log theo kieu `key=value`, gan `service_name`, `timestamp`, `level`, `msg`, `module`.
3. Neu la `tetragon` hoac `tetragon-operator`, boc lop CRI, roi dung Ruby de suy ra `service_name`, `level`, `msg`, `timestamp`.
4. Neu event khong thuoc dung cac nguon log da chon, thi `drop`.
5. Bat dau khai bao nhanh `tetragon-export` o dong `261`.

## Cong thuc tong quat rut ra tu doan nay

- Chuan hoa field:

```ruby
value = event.get("field_a") || event.get("field_b")
event.set("target_field", value) if value
```

- Loc theo ten file:

```conf
if [@metadata][source_path] =~ /regex/
```

- Parse thong tin bang `grok`:

```conf
grok {
  match => { "field" => "pattern" }
}
```

- Parse `key=value` bang `kv`:

```conf
kv {
  source => "field"
}
```

- Dung Ruby de fallback hoac suy luan them:

```ruby
if text =~ /pattern/
  event.set("field", value)
else
  event.set("field", fallback)
end
```

- Don field tam:

```conf
mutate {
  remove_field => [ ... ]
}
```

- Chan event ngoai pham vi:

```conf
drop { }
```
