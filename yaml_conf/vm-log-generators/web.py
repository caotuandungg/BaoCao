import json
import random
import time
from datetime import datetime, timezone

methods = ["GET", "POST"]
paths = ["/", "/index.html", "/healthz", "/images/logo.png", "/api/proxy"]

while True:
    status_code = random.choice([200, 200, 200, 404, 500, 502])
    level = "ERROR" if status_code >= 500 else ("WARN" if status_code == 404 else "INFO")
    payload = {
        "@timestamp": datetime.now(timezone.utc).isoformat(),
        "service": "webserver",
        "level": level,
        "event": "access_log",
        "environment": "lab",
        "method": random.choice(methods),
        "path": random.choice(paths),
        "status_code": status_code,
        "client_ip": f"10.42.0.{random.randint(2, 254)}",
        "message": "web generated log",
    }
    print(json.dumps(payload), flush=True)
    time.sleep(2)
