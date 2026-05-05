import json
import random
import time
from datetime import datetime, timezone

paths = ["/", "/home", "/login", "/products", "/cart"]

while True:
    payload = {
        "@timestamp": datetime.now(timezone.utc).isoformat(),
        "service": "frontend",
        "level": random.choice(["INFO", "INFO", "INFO", "WARN", "ERROR"]),
        "event": random.choice(["page_view", "asset_load", "ui_action"]),
        "environment": "lab",
        "path": random.choice(paths),
        "user_id": f"u{random.randint(1, 20):03}",
        "session_id": f"s{random.randint(1000, 9999)}",
        "response_time_ms": random.randint(20, 1500),
        "message": "frontend generated log",
    }
    print(json.dumps(payload), flush=True)
    time.sleep(2)
