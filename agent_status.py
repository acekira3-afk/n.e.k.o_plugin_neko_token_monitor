"""Read task status only; never change agent flags or fetch task contents for UI."""

import json
import threading
import time
import urllib.request


def classify(payload):
    if not isinstance(payload, dict) or payload.get("error") or not isinstance(payload.get("tasks"), list):
        return {"status": "unknown"}
    tasks = payload["tasks"]
    if any(
        not isinstance(t, dict)
        or t.get("status")
        not in ("queued", "running", "completed", "failed", "cancelled", "canceled", "timeout", "timed_out")
        for t in tasks
    ):
        return {"status": "unknown"}
    busy = any(t["status"] in ("running", "queued") for t in tasks)
    return {"status": "busy" if busy else "idle"}


class AgentStatus:
    def __init__(self):
        self.lock = threading.Lock()
        self.checked = 0
        self.cached = {"status": "unknown"}

    def snapshot(self):
        with self.lock:
            if time.monotonic() - self.checked < 4:
                return self.cached
            try:
                # Ignore configured external proxies for this local read.
                opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
                with opener.open("http://127.0.0.1:48911/api/agent/tasks", timeout=2) as response:
                    self.cached = classify(json.loads(response.read(1048576)))
            except Exception:
                self.cached = {"status": "unknown"}
            self.checked = time.monotonic()
            return self.cached
