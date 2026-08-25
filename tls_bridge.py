#!/usr/bin/env python3
"""TLS bridge: local http -> https://api.deepseek.com (OpenSSL TLS, works on iSH).
Codex talks plain HTTP to 127.0.0.1:8787; this forwards to DeepSeek over TLS.
"""
import http.server
import http.client
import ssl
import sys

TARGET = "api.deepseek.com"
PORT = 8787

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _forward(self):
        try:
            body = None
            cl = self.headers.get("Content-Length")
            if cl:
                body = self.rfile.read(int(cl))
            conn = http.client.HTTPSConnection(
                TARGET, 443, timeout=120,
                context=ssl.create_default_context(),
            )
            headers = {}
            for k, v in self.headers.items():
                kl = k.lower()
                if kl in ("host", "connection", "accept-encoding", "content-length"):
                    continue
                headers[k] = v
            conn.request(self.command, self.path, body=body, headers=headers)
            resp = conn.getresponse()
            self.send_response(resp.status)
            for k, v in resp.getheaders():
                kl = k.lower()
                if kl in ("transfer-encoding", "connection", "content-length", "keep-alive"):
                    continue
                self.send_header(k, v)
            self.send_header("Connection", "close")
            self.end_headers()
            while True:
                chunk = resp.read(8192)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
            conn.close()
        except Exception as e:
            try:
                self.send_response(502)
                self.end_headers()
                self.wfile.write(str(e).encode())
            except Exception:
                pass

    def do_POST(self):
        self._forward()

    def do_GET(self):
        self._forward()

    def do_OPTIONS(self):
        self._forward()

    def log_message(self, *a):
        pass

if __name__ == "__main__":
    srv = http.server.HTTPServer(("127.0.0.1", PORT), Handler)
    print(f"bridge listening on 127.0.0.1:{PORT} -> https://{TARGET}", flush=True)
    srv.serve_forever()
