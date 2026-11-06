#!/usr/bin/env python3
"""Служба пуш-уведомлений «Вдвоём»: принимает от PocketBase (127.0.0.1:8788) задания и отправляет их в Apple (APNs).
Настройки — в /etc/vdvoem-push.env: APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC, APNS_KEY_FILE."""
import json, os, time, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import httpx, jwt

KEY_ID = os.environ["APNS_KEY_ID"]
TEAM_ID = os.environ["APNS_TEAM_ID"]
TOPIC = os.environ.get("APNS_TOPIC", "ru.vdvoem.app")
KEY = open(os.environ["APNS_KEY_FILE"]).read()
HOSTS = ["https://api.push.apple.com", "https://api.sandbox.push.apple.com"]

_tok = {"v": None, "t": 0}
_lock = threading.Lock()
client = httpx.Client(http2=True, timeout=10)
# Какой сервер Apple подошёл токену (боевой или тестовый) — запоминаем, чтобы не гадать каждый раз.
env_of = {}


def bearer():
    with _lock:
        if not _tok["v"] or time.time() - _tok["t"] > 40 * 60:
            _tok["v"] = jwt.encode({"iss": TEAM_ID, "iat": int(time.time())}, KEY, algorithm="ES256", headers={"kid": KEY_ID})
            _tok["t"] = time.time()
        return _tok["v"]


def send_one(token, payload):
    """Возвращает 'ok', 'dead' (токен недействителен) или 'fail'."""
    order = [env_of[token]] if token in env_of else [0, 1]
    if token in env_of:
        order.append(1 - env_of[token])
    last = "fail"
    for i in order:
        try:
            r = client.post(f"{HOSTS[i]}/3/device/{token}", content=json.dumps(payload).encode(), headers={
                "authorization": f"bearer {bearer()}", "apns-topic": TOPIC, "apns-push-type": "alert", "apns-priority": "10"})
        except Exception as e:
            print("apns error", e, flush=True)
            continue
        if r.status_code == 200:
            env_of[token] = i
            return "ok"
        reason = ""
        try: reason = r.json().get("reason", "")
        except Exception: pass
        print("apns", HOSTS[i].split("//")[1], r.status_code, reason, flush=True)
        if r.status_code == 410 or reason == "Unregistered":
            return "dead"
        if reason in ("BadDeviceToken", "DeviceTokenNotForTopic"):
            last = "dead"   # возможно, токен от другого сервера — пробуем следующий
            continue
        last = "fail"
    return last


class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def do_POST(self):
        if self.path != "/send":
            self.send_response(404); self.end_headers(); return
        try:
            n = int(self.headers.get("content-length", "0"))
            req = json.loads(self.rfile.read(n))
            payload = {"aps": {"alert": {"title": req.get("title", ""), "body": req.get("body", "")}, "sound": "default",
                               "thread-id": req.get("thread", ""), "mutable-content": 1}}
            payload.update(req.get("data") or {})
            dead = [t for t in req.get("tokens", []) if send_one(t, payload) == "dead"]
            out = json.dumps({"dead": dead}).encode()
            self.send_response(200); self.send_header("content-type", "application/json"); self.end_headers(); self.wfile.write(out)
        except Exception as e:
            print("handler error", e, flush=True)
            self.send_response(500); self.end_headers()

    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8788), H).serve_forever()
