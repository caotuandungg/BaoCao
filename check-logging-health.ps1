# Script giam sat suc khoe he thong Logging toan dien (Full Stack Health Check)
$elkNs = "elk-dung"      # Thay thanh "elk" neu ban dung namespace ngan
$kafkaNs = "kafka-dung"
$esUser = "elastic"
$esPass = "1xNIfTEXaH0MsbQN"
$kafkaGroup = "logstash-consumer-group-2"
$kafkaTopic = "dung-logs-topic"
$indices = @("dung-fe-*", "dung-be-*", "dung-db-*", "dung-web-*")

Clear-Host
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "     HE THONG GIAM SAT LOGGING FULL-STACK     " -ForegroundColor Cyan
Write-Host "     Thoi gian: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host "======================================================" -ForegroundColor Cyan

# --- TANG 1: FLUENT BIT (COLLECTOR) ---
Write-Host "`n[1/5] KIEM TRA TANG THU THAP (FLUENT BIT):" -ForegroundColor White
$fbPods = kubectl get pods -n $elkNs -l app.kubernetes.io/name=fluent-bit --no-headers 2>$null
if ($fbPods) {
    $fbRunning = ($fbPods | Select-String -Pattern "Running").Count
    Write-Host " - Pods Fluent Bit: $fbRunning Running" -ForegroundColor Green
    kubectl rollout status daemonset/fluent-bit -n $elkNs --timeout=10s 2>$null | Out-Null
    Write-Host " - DaemonSet Status: OK" -ForegroundColor Green
} else {
    Write-Host " - ERROR: Khong tim thay Fluent Bit trong namespace $elkNs" -ForegroundColor Red
}

# --- TANG 2: KAFKA CLUSTER & TOPIC (BROKER) ---
Write-Host "`n[2/5] KIEM TRA TANG KAFKA (BROKER):" -ForegroundColor White
$kafkaPods = kubectl get pods -n $kafkaNs -l strimzi.io/name=my-cluster-kafka --no-headers 2>$null
$kafkaRunning = ($kafkaPods | Select-String -Pattern "Running").Count
Write-Host " - Kafka Brokers: $kafkaRunning Running" -ForegroundColor Green

Write-Host " - Topic Metadata ($kafkaTopic):" -ForegroundColor Cyan
$descCmd = "kubectl exec -n $kafkaNs my-cluster-combined-0 -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic $kafkaTopic"
$descOutput = Invoke-Expression $descCmd 2>$null
if ($descOutput) {
    $descOutput | Select-String -Pattern "PartitionCount|ReplicationFactor|Isr" | ForEach-Object { Write-Host "   > $($_.ToString().Trim())" -ForegroundColor Gray }
}

# --- TANG 3: KAFKA SAMPLE DATA (FLOW CHECK) ---
Write-Host "`n[3/5] DOC NHANH 20 MESSAGES DE XEM CO DU LIEU VAO TOPIC KHONG:" -ForegroundColor White
$sampleCmd = "kubectl exec -n $kafkaNs my-cluster-combined-0 -- /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic $kafkaTopic --max-messages 20 --timeout-ms 10000"
$sampleData = Invoke-Expression $sampleCmd 2>$null
if ($sampleData) {
    Write-Host " - [PASS] Da doc duoc du lieu thoi gian thuc tu Kafka." -ForegroundColor Green
} else {
    Write-Host " - [WARN] Khong doc duoc message nao tu Kafka (co the topic dang trong)." -ForegroundColor Yellow
}

# --- TANG 4: LOGSTASH (TRANSFORMER & LAG) ---
Write-Host "`n[4/5] KIEM TRA TANG XU LY (LOGSTASH):" -ForegroundColor White
# Kiem tra Lag
$lagCmd = "kubectl exec -n $kafkaNs my-cluster-combined-0 -- /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group $kafkaGroup"
$lagLines = Invoke-Expression $lagCmd 2>$null | Select-String -Pattern "$kafkaGroup"
if ($lagLines) {
    Write-Host " - Consumer Group '$kafkaGroup' dang hoat dong." -ForegroundColor Green
}

# Kiem tra Error Log
$errors = kubectl logs -n $elkNs -l app.kubernetes.io/name=logstash --since=10m 2>$null | Select-String -Pattern "ERROR|Elasticsearch Unreachable"
if ($errors) {
    Write-Host " - [FAIL] Tim thay $($errors.Count) loi trong log Logstash!" -ForegroundColor Red
} else {
    Write-Host " - [PASS] Logstash khong co loi ket noi ES." -ForegroundColor Green
}

# --- TANG 5: ELASTICSEARCH (STORAGE) ---
Write-Host "`n[5/5] KIEM TRA DU LIEU CUOI (ELASTICSEARCH):" -ForegroundColor White
foreach ($idx in $indices) {
    $displayName = $idx.Replace("dung-", "").Replace("-*", "").ToUpper()
    $url = "https://localhost:9200/$idx/_count?q=@timestamp:%5Bnow-15m%20TO%20now%5D"
    $countRes = kubectl exec -n $elkNs elasticsearch-master-0 -- curl -sk -u $esUser`:$esPass "$url" 2>$null
    if ($countRes -match '\{.*\}') {
        $count = ($countRes | ConvertFrom-Json).count
        Write-Host " - Service [$displayName]:`t" -NoNewline
        if ($count -gt 0) { Write-Host "OK ($count logs)" -ForegroundColor Green } else { Write-Host "EMPTY" -ForegroundColor Yellow }
    }
}

Write-Host "`n=== KET THUC KIEM TRA TOAN DIEN ===" -ForegroundColor Cyan
