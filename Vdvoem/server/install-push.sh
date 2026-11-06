#!/usr/bin/env bash
# Включает пуш-уведомления «Вдвоём». Нужен ключ Apple (файл AuthKey_XXXXXXXXXX.p8), загруженный в /root.
# Запуск:  sudo bash /root/install-push.sh ВАШ_TEAM_ID
set -euo pipefail
say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mОшибка: %s\033[0m\n' "$*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "запустите через sudo"
TEAM="${1:-}"
[ -n "$TEAM" ] || die "укажите Team ID: bash /root/install-push.sh ABCDE12345"
KEYFILE="$(ls /root/AuthKey_*.p8 2>/dev/null | head -1 || true)"
[ -n "$KEYFILE" ] || die "не найден файл ключа /root/AuthKey_XXXXXXXXXX.p8 — загрузите его в /root по SFTP"
KEYID="$(basename "$KEYFILE" .p8)"; KEYID="${KEYID#AuthKey_}"

say "Ставлю нужные пакеты"
apt-get install -y python3-venv python3-pip >/dev/null
mkdir -p /opt/vd-push /etc/vdvoem
[ -d /opt/vd-push/venv ] || python3 -m venv /opt/vd-push/venv
/opt/vd-push/venv/bin/pip install -q --upgrade "httpx[http2]" "pyjwt[crypto]"

say "Кладу службу и ключ"
cat > /opt/vd-push/vd-push.py <<'VDPUSH'
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
VDPUSH
install -m 600 "$KEYFILE" /etc/vdvoem/AuthKey.p8
cat > /etc/vdvoem-push.env <<ENVEOF
APNS_KEY_ID=$KEYID
APNS_TEAM_ID=$TEAM
APNS_TOPIC=ru.vdvoem.app
APNS_KEY_FILE=/etc/vdvoem/AuthKey.p8
ENVEOF
chmod 600 /etc/vdvoem-push.env
cat > /etc/systemd/system/vd-push.service <<'UNIT'
[Unit]
Description=Vdvoem push (APNs)
After=network-online.target

[Service]
EnvironmentFile=/etc/vdvoem-push.env
ExecStart=/opt/vd-push/venv/bin/python /opt/vd-push/vd-push.py
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable vd-push >/dev/null 2>&1
systemctl restart vd-push
sleep 2
if curl -fsS http://127.0.0.1:8788/ >/dev/null 2>&1; then
  say "Готово: служба пушей работает"
  echo "Ключ: $KEYID, Team ID: $TEAM. Теперь откройте приложение и разрешите уведомления."
else
  journalctl -u vd-push -n 30 --no-pager
  die "служба не запустилась — пришлите вывод выше"
fi
