"""Durable session counts; import only factual summaries through NEKO's memory API."""

import json
import threading
import uuid
from datetime import datetime
from pathlib import Path
from urllib.request import ProxyHandler, Request, build_opener


class Recording:
    def __init__(self, directory):
        self.path = Path(directory) / "recording.json"
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.lock = threading.RLock()
        try:
            self.data = json.loads(self.path.read_text())
        except (OSError, ValueError):
            self.data = {"active": False}

    def save(self):
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.data, ensure_ascii=False))
        temporary.replace(self.path)

    def action(self, action):
        with self.lock:
            if action == "start" and not self.data.get("active"):
                if self.data.get("summary") and not self.data.get("memory_saved"):
                    return dict(self.data, error="上次记录尚未写入记忆，请先重试保存喵～")
                self.data = dict(
                    active=True,
                    id=str(uuid.uuid4()),
                    start=datetime.now().astimezone().isoformat(timespec="seconds"),
                    pet=0,
                    ask=0,
                )
            elif action in ("pet", "ask") and self.data.get("active"):
                self.data[action] += 1
            elif action == "end" and self.data.get("active"):
                self.data.update(active=False, end=datetime.now().astimezone().isoformat(timespec="seconds"))
                self.data["summary"] = f"在此期间共摸头 {self.data['pet']} 次，询问 {self.data['ask']} 次喵～"
            elif action not in ("start", "pet", "ask", "end", "status", "retry"):
                raise ValueError("Unknown recording action")
            self.save()
            if action in ("end", "retry") and self.data.get("summary") and not self.data.get("memory_saved"):
                self.import_memory()
            return dict(self.data)

    def import_memory(self):
        text = (
            f"猫粮互动记录 {self.data['id']}：用户与 YUI 在 {self.data['start']} 至 {self.data['end']} 的记录模式期间，"
            f"点击人物摸头 {self.data['pet']} 次，点击气泡询问余额或空闲状态 {self.data['ask']} 次。"
        )
        payload = {
            "character_name": "YUI",
            "source_format": "auto",
            "files": [{"path": "MEMORY.md", "content": "# 猫粮互动记录\n\n- " + text + "\n"}],
        }
        try:
            req = Request(
                "http://127.0.0.1:48911/api/memory/external_import/commit",
                data=json.dumps(payload).encode(),
                headers={"Content-Type": "application/json"},
            )
            with build_opener(ProxyHandler({})).open(req, timeout=20) as response:
                result = json.load(response)
            self.data["memory_saved"] = bool(
                result.get("success") and (result.get("added_facts", 0) or result.get("skipped_duplicates", 0))
            )
        except Exception:
            self.data["memory_saved"] = False
        self.save()
