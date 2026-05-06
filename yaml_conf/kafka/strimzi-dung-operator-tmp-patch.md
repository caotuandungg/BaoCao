# Strimzi dung operator /tmp patch

The Strimzi operator in `kafka-dung` originally had `/tmp` mounted as a 1Mi
memory `emptyDir`. Certificate generation for the external Kafka listener failed
with:

```text
java.io.IOException: No space left on device
```

The live cluster was patched with:

```powershell
$patchPath = Join-Path $env:TEMP 'strimzi-tmp-patch.json'
'{"spec":{"template":{"spec":{"volumes":[{"name":"strimzi-tmp","emptyDir":{"medium":"Memory","sizeLimit":"64Mi"}},{"name":"co-config-volume","configMap":{"name":"strimzi-cluster-operator","defaultMode":420}}]}}}}' |
  Set-Content -NoNewline -Encoding ascii $patchPath

kubectl patch deploy strimzi-cluster-operator -n kafka-dung --type=merge --patch-file $patchPath
kubectl rollout status deploy/strimzi-cluster-operator -n kafka-dung
```

Verify:

```bash
kubectl exec -n kafka-dung deploy/strimzi-cluster-operator -- df -h /tmp
```
