"""Real Win32 hide/re-hide/restore test using two harmless NEKO-named fixture windows."""

import ctypes
import json
import os
import shutil
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

user = ctypes.windll.user32
user.IsWindowVisible.argtypes = [ctypes.c_void_p]
user.ShowWindow.argtypes = [ctypes.c_void_p, ctypes.c_int]
user.GetWindowThreadProcessId.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
callback_type = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
user.EnumWindows.argtypes = [callback_type, ctypes.c_void_p]
phase = "start"
reports = []


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/phase":
            body = phase.encode()
        elif self.path.startswith("/report?"):
            reports.append(self.path)
            body = b"ok"
        else:
            body = b"""<!doctype html><script>
            let previous='';window.catfoodNativeState=d=>fetch('/report?ok='+d.ok);
            setInterval(async()=>{const p=await (await fetch('/phase')).text();if(p!==previous){previous=p;chrome.webview.postMessage(p==='start'?'recordStart':p==='end'?'recordEnd':'hide');}},200);
            </script>"""
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def windows(pid):
    result = []

    @callback_type
    def collect(handle, unused):
        owner = ctypes.c_ulong()
        user.GetWindowThreadProcessId(handle, ctypes.byref(owner))
        if owner.value == pid:
            result.append(handle)
        return True

    user.EnumWindows(collect, None)
    return result


def wait_for(check, message, seconds=30):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if check():
            return
        time.sleep(0.2)
    raise AssertionError(message)


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
fixture = widget = None
try:
    executable = Path("out/CatFood.exe").resolve()
    fixture_exe = executable.with_name("NEKO.exe")
    shutil.copy2(executable, fixture_exe)
    fixture = subprocess.Popen([str(fixture_exe), "--fixture"])
    wait_for(lambda: len([w for w in windows(fixture.pid) if user.IsWindowVisible(w)]) >= 2, "fixture not visible")
    targets = [w for w in windows(fixture.pid) if user.IsWindowVisible(w)]
    with tempfile.TemporaryDirectory() as directory:
        widget = subprocess.Popen(
            [str(executable), str(os.getpid()), f"http://127.0.0.1:{server.server_port}", str(Path(directory) / "stop")]
        )
        wait_for(lambda: reports and all(not user.IsWindowVisible(w) for w in targets), "host windows not hidden")
        for w in targets:
            user.ShowWindow(w, 8)
        wait_for(lambda: all(not user.IsWindowVisible(w) for w in targets), "reopened host windows not hidden")
        phase = "end"
        wait_for(lambda: all(user.IsWindowVisible(w) for w in targets), "host windows not restored")
        phase = "close"
        widget.wait(timeout=15)
        assert widget.returncode == 0
        print(json.dumps({"windows": len(targets), "hide": "PASS", "rehide": "PASS", "restore": "PASS"}))
finally:
    for proc in (widget, fixture):
        if proc and proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=10)
    server.shutdown()
    server.server_close()
