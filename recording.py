"""Durable interaction history and a retryable, asynchronous memory outbox."""

import copy
import json
import os
import threading
import uuid
from datetime import datetime
from pathlib import Path
from urllib.request import ProxyHandler, Request, build_opener


def now():
    return datetime.now().astimezone().isoformat(timespec="seconds")


class Recording:
    def __init__(self, directory, importer=None):
        self.path = Path(directory) / "recording.json"
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.lock = threading.RLock()
        self.importer = importer or self.import_memory
        self.wake = threading.Event()
        self.stop = threading.Event()
        self.worker = None
        self.load_error = None
        raw = None
        for path in (self.path, self.path.with_suffix(".bak")):
            try:
                raw = json.loads(path.read_text())
                if not isinstance(raw, dict):
                    raise ValueError()
                break
            except (OSError, ValueError):
                raw = None
        if raw is None and self.path.exists():
            # Never overwrite the only copy of a damaged record.
            self.load_error = "互动记录文件无法读取，已保留原文件；请先修复或备份后重试喵～"
        if raw and raw.get("version") == 2:
            self.data = raw
        else:
            sessions = [raw] if raw and raw.get("id") else []
            self.data = {"version": 2, "sessions": sessions}
        self.data.setdefault("sessions", [])

    def save(self):
        if self.load_error:
            raise ValueError(self.load_error)
        raw = json.dumps(self.data, ensure_ascii=False)
        for path in (self.path, self.path.with_suffix(".bak")):
            temporary = path.with_suffix(path.suffix + ".tmp")
            fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as stream:
                stream.write(raw)
                stream.flush()
                os.fsync(stream.fileno())
            temporary.replace(path)

    def snapshot(self):
        with self.lock:
            sessions = self.data["sessions"]
            current = sessions[-1] if sessions else {"active": False}
            def clean(row):
                return {k: v for k, v in row.items() if k != "events"}
            return dict(
                clean(current),
                initialized=bool(sessions),
                history=[clean(row) for row in reversed(sessions[-100:])],
                totals={
                    "pet": sum(row.get("pet", 0) for row in sessions),
                    "ask": sum(row.get("ask", 0) for row in sessions),
                    "sessions": len(sessions),
                },
                pending_memory=sum(bool(row.get("summary") and not row.get("memory_saved")) for row in sessions),
                error=self.load_error,
            )

    def action(self, action, event_id=None, session_id=None):
        if action not in ("start", "pet", "ask", "end", "status", "retry"):
            raise ValueError("Unknown recording action")
        if event_id is not None and (not isinstance(event_id, str) or not 1 <= len(event_id) <= 100):
            raise ValueError("Invalid event id")
        with self.lock:
            if self.load_error:
                return self.snapshot()
            sessions = self.data["sessions"]
            current = sessions[-1] if sessions else None
            if action == "start" and not (current and current.get("active")):
                current = dict(active=True, id=str(uuid.uuid4()), start=now(), pet=0, ask=0, events=[])
                sessions.append(current)
            elif action in ("pet", "ask"):
                # Replayed clicks are attributed to their original session, even after a crash/exit.
                target = next((row for row in sessions if row["id"] == session_id), None) if session_id else current
                if target and (target.get("active") or session_id):
                    seen = target.setdefault("events", [])
                    if not event_id or event_id not in seen:
                        target[action] = target.get(action, 0) + 1
                        if event_id:
                            seen.append(event_id)
                        if target.get("summary"):
                            target["summary"] = self.summary(target)
                            target["memory_saved"] = False
            elif action == "end" and current and current.get("active"):
                current.update(active=False, end=now(), memory_saved=False)
                current["summary"] = self.summary(current)
            if action != "status":
                self.save()
            if action in ("end", "retry"):
                self.wake.set()
            return self.snapshot()

    @staticmethod
    def summary(row):
        return f"在此期间共摸头 {row.get('pet', 0)} 次，询问 {row.get('ask', 0)} 次喵～"

    def flush_pending(self):
        with self.lock:
            pending = [
                copy.deepcopy(row)
                for row in self.data["sessions"]
                if row.get("summary") and not row.get("memory_saved")
            ]
        for row in pending:
            if self.stop.is_set():
                break
            try:
                saved = bool(self.importer(row))
            except Exception:
                saved = False
            with self.lock:
                target = next(item for item in self.data["sessions"] if item["id"] == row["id"])
                if target.get("summary") == row.get("summary"):
                    target["memory_saved"] = saved
                    target["memory_error"] = None if saved else "本机记录已保存，YUI 记忆待重试"
                    self.save()

    def start(self):
        if self.worker and self.worker.is_alive():
            return
        if self.load_error:
            return

        def run():
            while not self.stop.is_set():
                self.wake.clear()
                try:
                    self.flush_pending()
                except Exception:
                    pass
                self.wake.wait(60)

        self.worker = threading.Thread(target=run, daemon=True)
        self.worker.start()

    def close(self):
        self.stop.set()
        self.wake.set()
        if self.worker:
            self.worker.join(1)

    @staticmethod
    def import_memory(row):
        text = (
            f"猫粮互动记录 {row['id']}：用户与 YUI 在 {row['start']} 至 {row['end']} 的记录模式期间，"
            f"点击人物摸头 {row['pet']} 次，点击气泡询问余额或空闲状态 {row['ask']} 次。"
        )
        payload = {
            "character_name": "YUI",
            "source_format": "auto",
            "files": [{"path": "MEMORY.md", "content": "# 猫粮互动记录\n\n- " + text + "\n"}],
        }
        req = Request(
            "http://127.0.0.1:48911/api/memory/external_import/commit",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        with build_opener(ProxyHandler({})).open(req, timeout=30) as response:
            result = json.load(response)
        return bool(result.get("success") and (result.get("added_facts", 0) or result.get("skipped_duplicates", 0)))
