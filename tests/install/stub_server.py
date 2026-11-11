# ABOUTME: A stand-in for shulportal.com in the install test: answers every check with {"install":"<DIR/target>"},
# ABOUTME: logs each check body, and serves that version's release files from DIR. Usage: stub_server.py DIR PORT LOG.
import http.server
import sys

folder, port, log = sys.argv[1], int(sys.argv[2]), sys.argv[3]


def target():
    with open(f"{folder}/target") as f:
        return f.read().strip()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        with open(log, "a") as f:
            f.write(body + "\n")
        self.reply(200, ('{"install":"%s"}' % target()).encode(), "application/json")

    def do_GET(self):
        v = target()
        prefix = f"/api/pi/release/{v}/"
        name = self.path[len(prefix):]
        if not self.path.startswith(prefix) or name not in (f"shulportal-pi_{v}_all.deb", f"shulportal-pi_{v}_all.deb.sig"):
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
