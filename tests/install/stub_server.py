# ABOUTME: A stand-in for shulportal.com in the install test: answers every check with {"install":"9.0.1"},
# ABOUTME: logs each check body, and serves release files from a folder. Usage: stub_server.py DIR PORT LOG.
import http.server
import sys

folder, port, log = sys.argv[1], int(sys.argv[2]), sys.argv[3]
PREFIX = "/api/pi/release/9.0.1/"


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        with open(log, "a") as f:
            f.write(body + "\n")
        self.reply(200, b'{"install":"9.0.1"}', "application/json")

    def do_GET(self):
        name = self.path[len(PREFIX):]
        if not self.path.startswith(PREFIX) or "/" in name or name not in (
            "shulportal-pi_9.0.1_all.deb",
            "shulportal-pi_9.0.1_all.deb.sig",
        ):
            return self.reply(404, b"not found", "text/plain")
        with open(f"{folder}/{name}", "rb") as f:
            self.reply(200, f.read(), "application/octet-stream")

    def reply(self, code, data, kind):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
