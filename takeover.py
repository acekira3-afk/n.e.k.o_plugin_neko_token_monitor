"""Transient acknowledgement for a native character takeover attempt."""

import threading


class TakeoverState:
    def __init__(self):
        self.lock = threading.Lock()
        self.event = threading.Event()
        self.session_id = None
        self.result = None

    def begin(self, session_id):
        with self.lock:
            if self.session_id != session_id:
                self.session_id = session_id
                self.result = None
                self.event.clear()

    def report(self, session_id, ok, reason=None):
        with self.lock:
            if session_id != self.session_id or self.result is not None:
                return False
            self.result = {"ok": ok, "reason": reason}
            self.event.set()
            return True

    def wait(self, session_id, timeout):
        self.event.wait(timeout)
        with self.lock:
            return self.result if self.session_id == session_id else None
