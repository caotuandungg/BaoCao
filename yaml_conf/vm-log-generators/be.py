import json
import random
import time
from datetime import datetime, timezone

endpoints = ["/api/login", "/api/orders", "/api/profile", "/api/payment"]

while True:
    status_code = random.choice([200, 200, 200, 201, 400, 500, 503])
    level = "ERROR" if status_code >= 500 else ("WARN" if status_code >= 400 else "INFO")
    payload = {
        "@timestamp": datetime.now(timezone.utc).isoformat(),
        "service": "backend",
        "level": level,
        "event": "api_request",
        "environment": "lab",
        "endpoint": random.choice(endpoints),
        "request_id": f"req-{random.randint(10000, 99999)}",
        "status_code": status_code,
        "error_code": random.choice(["NONE", "ORDER_TIMEOUT", "DB_CONN_FAIL", "BAD_REQUEST"]),
        "message": "backend generated log",
    }
    print(json.dumps(payload), flush=True)
    time.sleep(3)
