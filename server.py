import json
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def start_server(monitor, port=48923, request_reply=None, agent_status=None, recording=None):
    csrf = secrets.token_urlsafe(32)
    reply_lock = threading.Lock()
    last_reply = [None]

    class LocalServer(ThreadingHTTPServer):
        def server_bind(self):
            # HTTPServer normally does a blocking reverse-DNS lookup during bind.
            # A loopback-only widget needs no DNS and must start inside NEKO's deadline.
            import socketserver

            socketserver.TCPServer.server_bind(self)
            self.server_name = "127.0.0.1"
            self.server_port = self.server_address[1]

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def send(self, status, payload, content_type="application/json; charset=utf-8"):
            raw = (
                payload
                if isinstance(payload, bytes)
                else payload.encode()
                if isinstance(payload, str)
                else json.dumps(payload, ensure_ascii=False).encode()
            )
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header(
                "Content-Security-Policy",
                "default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'",
            )
            self.end_headers()
            self.wfile.write(raw)

        def allowed(self):
            expected = f"127.0.0.1:{self.server.server_port}"
            return (
                self.headers.get("Host") == expected
                and self.headers.get("Origin", "http://" + expected) == "http://" + expected
            )

        def do_GET(self):
            if not self.allowed():
                return self.send(403, {"error": "仅允许本机同源访问"})
            path = self.path.split("?")[0]
            if path == "/api/status":
                return self.send(200, dict(monitor.snapshot(), csrf=csrf))
            if path == "/api/agent":
                return self.send(200, agent_status.snapshot() if agent_status else {"status": "unknown"})
            names = {
                "/": ("index.html", "text/html; charset=utf-8"),
                "/widget": ("widget.html", "text/html; charset=utf-8"),
                "/settings.js": ("settings.js", "text/javascript; charset=utf-8"),
                "/settings.css": ("settings.css", "text/css; charset=utf-8"),
                "/account-page.js": ("account-page.js", "text/javascript; charset=utf-8"),
                "/widget.js": ("widget.js", "text/javascript; charset=utf-8"),
                "/widget.css": ("widget.css", "text/css; charset=utf-8"),
                "/yui-chibi.png": ("yui-chibi.png", "image/png"),
                "/app.js": ("app.js", "text/javascript; charset=utf-8"),
            }
            if path not in names:
                return self.send(404, {"error": "Not found"})
            name, content_type = names[path]
            self.send(200, (Path(__file__).parent / "static" / name).read_bytes(), content_type)

        def do_POST(self):
            if not self.allowed() or not secrets.compare_digest(self.headers.get("X-Neko-CSRF", ""), csrf):
                return self.send(403, {"error": "请重新打开本机面板"})
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 4096:
                    return self.send(413, {"error": "请求过大或为空"})
                body = json.loads(self.rfile.read(length))
                if not isinstance(body, dict):
                    raise ValueError()
                if self.path == "/api/recording":
                    return self.send(
                        200, recording.action(body.get("action", "status")) if recording else {"active": False}
                    )
                if self.path == "/api/usage":
                    return self.send(200, monitor.record_usage(body))
                if self.path == "/api/select":
                    return self.send(200, monitor.select(body.get("profile")))
                if self.path == "/api/config":
                    monitor.configure(body)
                    return self.send(200, monitor.refresh())
                if self.path == "/api/refresh":
                    return self.send(200, monitor.refresh())
                if self.path == "/api/reply":
                    if request_reply is None:
                        return self.send(503, {"error": "原软件回应通道尚未连接"})
                    with reply_lock:
                        if last_reply[0] is not None and time.monotonic() - last_reply[0] < 30:
                            return self.send(429, {"error": "本喵刚收到啦，等一会再叫我喵～"})
                        last_reply[0] = time.monotonic()
                        line = body.get("line")
                        if line is not None and (not isinstance(line, str) or not 1 <= len(line) <= 140):
                            return self.send(400, {"error": "台词格式无效"})
                        result = request_reply(line) if line else request_reply()
                    return self.send(200 if result.get("submitted") else 503, result)
                return self.send(404, {"error": "Not found"})
            except (ValueError, TypeError, AttributeError):
                return self.send(400, {"error": "设置无效：请检查密钥、币种及数字范围"})
            except Exception:
                return self.send(500, {"error": "保存失败，请检查本机数据目录权限"})

    server = LocalServer(("127.0.0.1", port), Handler)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread
