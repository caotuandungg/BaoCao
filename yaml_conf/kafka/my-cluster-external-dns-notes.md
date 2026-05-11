# DNS records needed for my-cluster external Kafka

Create these DNS records so they point to the same public IP used by the NGINX
Ingress TLS passthrough listener:

```text
dung-my-cluster-bs.kafka.vnpost.cloud -> <NGINX_INGRESS_PUBLIC_IP>
dung-my-cluster-b0.kafka.vnpost.cloud -> <NGINX_INGRESS_PUBLIC_IP>
```

The existing shared Kafka uses the same pattern:

```text
global-shared-1-bs.kafka.vnpost.cloud
global-shared-1-b0.kafka.vnpost.cloud (hiện tại chỉ có 1 kafka nên chỉ đang dùng cái này)
global-shared-1-b1.kafka.vnpost.cloud ( có thêm con nữa thì dùng cái này )
global-shared-1-b2.kafka.vnpost.cloud ( có thêm con nữa thì dùng cái này )
```

For this lab Kafka cluster there is only one broker, so only bootstrap and
broker-0 hostnames are needed.
