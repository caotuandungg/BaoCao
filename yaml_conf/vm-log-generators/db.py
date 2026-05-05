import json
import random
import time
from datetime import datetime, timezone

query_types = ["SELECT", "INSERT", "UPDATE", "DELETE"]
events = ["connection_ok", "slow_query", "auth_failed", "deadlock_detected"]

while True:
    event = random.choice(events)
    level = "INFO"
    if event == "slow_query":
        level = "WARN"
    elif event in ["auth_failed", "deadlock_detected"]:
        level = "ERROR"

    payload = {
        "@timestamp": datetime.now(timezone.utc).isoformat(),
        "service": "database",
        "level": level,
        "event": event,
        "environment": "lab",
        "db_name": "appdb",
        "query_type": random.choice(query_types),
        "duration_ms": random.randint(5, 3000),
        "db_user": random.choice(["app_user", "report_user", "admin"]),
        "message": "database generated log",
    }
    print(json.dumps(payload), flush=True)
    time.sleep(4)
