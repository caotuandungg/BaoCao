$ErrorActionPreference = "Stop"

$env:HTTP_PROXY = ""
$env:HTTPS_PROXY = ""
$env:ALL_PROXY = ""
$env:NO_PROXY = "172.18.0.50,localhost,127.0.0.1,::1"

kubectl get secret my-cluster-cluster-ca-cert -n kafka-dung `
  -o jsonpath="{.data.ca\.crt}" |
  ForEach-Object {
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_))
  } |
  Set-Content -NoNewline -Encoding ascii .\yaml_conf\kafka\my-cluster-ca.crt

Write-Host "Wrote yaml_conf/kafka/my-cluster-ca.crt"
