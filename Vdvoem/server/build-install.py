#!/usr/bin/env python3
"""Собирает install-vd.sh из файлов pb_hooks и pb_migrations (запускать после любой правки сервера)."""
import glob, os
here = os.path.dirname(os.path.abspath(__file__))
files = sorted(glob.glob(os.path.join(here, "pb_migrations", "*.js"))) + sorted(glob.glob(os.path.join(here, "pb_hooks", "*.js")))
out = ['''#!/usr/bin/env bash
# Добавляет на уже работающий сервер маршруты и коллекции приложения «Вдвоём».
# Ничего не переустанавливает и не трогает файлы Кошелька и HabitFlow: только файлы vdvoem*.
# Можно запускать повторно — это безопасно.
# Запуск:  sudo bash /root/install-vd.sh
set -euo pipefail

DIR="/opt/kopilka"
say() { printf '\\n\\033[1;34m==> %s\\033[0m\\n' "$*"; }
die() { printf '\\n\\033[1;31mОшибка: %s\\033[0m\\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "запустите через sudo"
[ -x "$DIR/pocketbase" ] || die "не найден $DIR/pocketbase — сначала должен быть установлен сервер Кошелька"

say "Делаю копию базы на всякий случай"
mkdir -p "$DIR/backups"
BK="$DIR/backups/before-vdvoem-$(date +%F-%H%M).db"
sqlite3 "$DIR/pb_data/data.db" ".backup '$BK'"
echo "Копия: $BK"

NEW=""
put() { # put <путь>  (содержимое со stdin)
  [ -e "$1" ] || NEW="$NEW $1"
  cat > "$1"
}

say "Кладу файлы «Вдвоём»"
''']
for f in files:
    sub = "pb_migrations" if "pb_migrations" in f else "pb_hooks"
    out.append(f'put "$DIR/{sub}/{os.path.basename(f)}" <<\'VDEOF\'\n{open(f, encoding="utf-8").read().rstrip()}\nVDEOF\n')
out.append('''chown -R kopilka:kopilka "$DIR/pb_hooks" "$DIR/pb_migrations" 2>/dev/null || true

rollback() {
  printf '\\n\\033[1;31mСервер не поднялся после добавления «Вдвоём». Откатываю.\\033[0m\\n'
  for f in $NEW; do rm -f "$f"; done
  systemctl stop kopilka || true
  cp "$BK" "$DIR/pb_data/data.db"
  systemctl start kopilka || true
  die "изменения отменены, Кошелёк работает как раньше. Пришлите вывод: journalctl -u kopilka -n 50"
}

say "Перезапускаю сервер"
systemctl restart kopilka
ok=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  sleep 2
  if curl -fsS http://127.0.0.1:8090/api/kp/ping >/dev/null 2>&1 && curl -fsS http://127.0.0.1:8090/api/vd/ping >/dev/null 2>&1; then ok=1; break; fi
done
[ "$ok" = 1 ] || rollback

say "Готово"
echo "Кошелёк и «Вдвоём» отвечают. Можно открывать приложение «Вдвоём»."
''')
open(os.path.join(here, "install-vd.sh"), "w", encoding="utf-8").write("\n".join(out))
print("ok", len(files), "файлов")

# ---- install-push.sh: служба отправки пушей в Apple ----
push_py = open(os.path.join(here, "push", "vd-push.py"), encoding="utf-8").read().rstrip()
sh = r'''#!/usr/bin/env bash
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
''' + push_py + r'''
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
'''
open(os.path.join(here, "install-push.sh"), "w", encoding="utf-8").write(sh)
print("ok push")
