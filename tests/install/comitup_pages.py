# ABOUTME: Drives comitup's own web app (comitupweb.py) over ShulPortal's Wi-Fi pages with a fake comitup:
# ABOUTME: every page renders, its forms post what comitup reads, and every file a page asks for is served.
"""Usage: python3 comitup_pages.py [path/to/comitupweb.py]

Without a path it uses the installed comitup (CI's install job). COMITUP_TEMPLATES points comitup at
another template folder, and a stand-in comitup.client is used when the real one isn't installed.
"""
import glob
import logging
import os
import re
import sys
import types
from html.parser import HTMLParser
from urllib.parse import urlencode


def load_comitupweb(path):
    if path is None:
        found = glob.glob("/usr/share/comitup/**/comitupweb.py", recursive=True) + glob.glob(
            "/usr/lib/python3*/dist-packages/**/comitupweb.py", recursive=True
        )
        if not found:
            sys.exit("FAIL: comitupweb.py not found")
        path = found[0]
    try:
        import comitup.client  # noqa: F401
    except ImportError:
        pkg = types.ModuleType("comitup")
        client = types.ModuleType("comitup.client")
        client.can_blink = lambda: True
        client.blink = lambda: None
        pkg.client = client
        sys.modules["comitup"], sys.modules["comitup.client"] = pkg, client
    sys.path.insert(0, os.path.dirname(path))
    import comitupweb

    return comitupweb


class FakeComitup:
    def __init__(self, points):
        self.points = points
        self.connects = []

    def ciu_points(self):
        return [dict(p) for p in self.points]

    def ciu_info(self):
        return {"imode": "single"}

    def ciu_connect(self, ssid, password):
        self.connects.append((ssid, password))


class Page(HTMLParser):
    """The forms (action, method, fields), links, and files a page asks for."""

    def __init__(self, html):
        super().__init__()
        self.forms, self.links, self.assets = [], [], []
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "form":
            self.forms.append({"action": a.get("action"), "method": (a.get("method") or "get").lower(), "fields": {}})
        elif tag == "input" and self.forms and a.get("name"):
            self.forms[-1]["fields"][a["name"]] = a.get("value", "")
        elif tag == "a" and a.get("href"):
            self.links.append(a["href"])
        elif tag == "link" and a.get("rel") == "stylesheet":
            self.assets.append(a["href"])
        elif tag in ("script", "img") and a.get("src"):
            self.assets.append(a["src"])


failures = []


def check(ok, what):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok:
        failures.append(what)


def main():
    web = load_comitupweb(sys.argv[1] if len(sys.argv) > 1 else None)
    if os.environ.get("COMITUP_TEMPLATES"):
        web.TEMPLATE_PATH = os.environ["COMITUP_TEMPLATES"]
    web.ciu.can_blink = lambda: True
    web.ciu.blink = lambda: None
    # comitup runs the connect in a child process; run it here so the fake sees it.
    web.Process = lambda target, args: types.SimpleNamespace(start=lambda: target(*args))
    web.time = types.SimpleNamespace(sleep=lambda s: None)

    fake = FakeComitup(
        [
            {"ssid": "Keter Torah", "security": "encrypted"},
            {"ssid": "Guest <b>&</b>", "security": "unencrypted"},
        ]
    )
    web.ciu_client = fake
    app = web.create_app(logging.getLogger("test"))
    app.testing = True
    http = app.test_client()

    def get(url):
        r = http.get(url)
        return r.status_code, r.get_data(as_text=True)

    # The list
    status, html = get("/")
    check(status == 200, "list page renders")
    check("ShulPortal" in html and "css/shulportal.css" in html, "list page is ShulPortal's")
    check("ComitUp" not in html and "uikit" not in html, "list page has none of comitup's look")
    check("Guest &lt;b&gt;&amp;&lt;/b&gt;" in html, "network names are escaped")
    check('id="ledimg"' in html and "blink()" in html, "list page keeps Locate")
    page = Page(html)
    nets = [link for link in page.links if link.startswith("confirm?")]
    check(len(nets) == 2, "each network links to its password page")

    assets = set(page.assets)
    for url in sorted(assets):
        check(http.get("/" + url).status_code == 200, f"serves {url}")
    css = http.get("/css/shulportal.css").get_data(as_text=True)
    for font in re.findall(r'url\("([^"]+)"\)', css):
        check(http.get("/css/" + font).status_code == 200, f"serves font css/{font}")
    check(http.get("/img/ledon.gif").status_code == 200, "serves the Locate light")

    # A secured network: the password page posts ssid + password, and comitup connects with them.
    status, html = get("/" + nets[0])
    check(status == 200, "password page renders for a secured network")
    form = Page(html).forms[0]
    check((form["action"], form["method"]) == ("/connect", "post"), "password form posts to /connect")
    check('type="password"' in html, "secured network asks for a password")
    fields = dict(form["fields"], password="hunter2 shalom")
    r = http.post(form["action"], data=fields)
    check(r.status_code == 200 and "Connecting the TV" in r.get_data(as_text=True), "connecting page renders")
    check(fake.connects[-1:] == [("Keter Torah", b"hunter2 shalom")], "comitup connects with the name and password")

    # An open network: no password box, but the field comitup reads is still sent.
    status, html = get("/" + nets[1])
    check(status == 200 and 'type="password"' not in html, "open network asks for no password")
    form = Page(html).forms[0]
    check("password" in form["fields"], "open network still sends an empty password")
    r = http.post(form["action"], data=form["fields"])
    check(r.status_code == 200, "open network connects without a 500")
    check(fake.connects[-1:] == [("Guest <b>&</b>", b"")], "comitup gets the open network's real name")

    # A network typed by hand.
    form = Page(get("/")[1]).forms[0]
    check(form["action"] == "/confirm", "hidden network form goes to the password page")
    status, html = get("/confirm?" + urlencode(dict(form["fields"], ssid="Back Office")))
    check(status == 200 and "Back Office" in html, "hidden network gets a password page")

    # No networks found yet.
    fake.points = []
    web.ttl_cache.clear()
    status, html = get("/")
    check(status == 200 and "Look again" in html, "empty list offers to look again")

    if failures:
        sys.exit(f"{len(failures)} check(s) failed")
    print("comitup pages: OK")


main()
