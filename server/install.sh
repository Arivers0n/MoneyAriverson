#!/usr/bin/env bash
# Установка сервера синхронизации «Копилки» на Debian/Ubuntu.
# Запуск:  sudo bash install.sh money.example.ru you@mail.ru
set -euo pipefail

DOMAIN="${1:-}"
EMAIL="${2:-}"
VER="0.40.6"
DIR="/opt/kopilka"
PORT_INTERNAL="8090"

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mОшибка: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "запустите через sudo"
[ -n "$DOMAIN" ] || read -rp "Домен для сервера (например money.example.ru): " DOMAIN
[ -n "$EMAIL" ] || read -rp "Ваша почта (для HTTPS-сертификата и админки): " EMAIL
[ -n "$DOMAIN" ] && [ -n "$EMAIL" ] || die "нужны домен и почта"

say "Проверяю, что домен $DOMAIN смотрит на этот сервер"
MYIP=$(curl -4 -fsS https://api.ipify.org || true)
DNSIP=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}' || true)
echo "IP сервера: ${MYIP:-?}, IP домена: ${DNSIP:-не найден}"
if [ -n "$MYIP" ] && [ "$MYIP" != "$DNSIP" ]; then
  echo "Внимание: домен пока не указывает на этот сервер. Добавьте A-запись $DOMAIN → $MYIP и дождитесь обновления DNS."
  read -rp "Продолжить всё равно? [y/N] " a; [ "${a:-n}" = "y" ] || exit 1
fi

say "Ставлю нужные пакеты"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl unzip sqlite3 ca-certificates >/dev/null

ARCH=$(uname -m); case "$ARCH" in x86_64) A=amd64;; aarch64|arm64) A=arm64;; *) die "неизвестная архитектура $ARCH";; esac

say "Скачиваю PocketBase $VER"
mkdir -p "$DIR/pb_hooks" "$DIR/pb_migrations" "$DIR/backups"
TMP=$(mktemp -d)
curl -fsSL -o "$TMP/pb.zip" "https://github.com/pocketbase/pocketbase/releases/download/v${VER}/pocketbase_${VER}_linux_${A}.zip"
unzip -oq "$TMP/pb.zip" pocketbase -d "$DIR"
chmod +x "$DIR/pocketbase"
rm -rf "$TMP"

say "Записываю логику синхронизации"
base64 -d > "$DIR/pb_migrations/1761350000_kopilka_init.js" <<'B64'
Ly8vIDxyZWZlcmVuY2UgcGF0aD0iLi4vcGJfZGF0YS90eXBlcy5kLnRzIiAvPgovLyDQmtC+0LvQu9C10LrRhtC40Lgg0JrQvtC/
0LjQu9C60LguINCU0L7RgdGC0YPQvyDQuiDQvdC40Lwg0YLQvtC70YzQutC+INGH0LXRgNC10Lcg0YHQstC+0Lgg0LzQsNGA0YjR
gNGD0YLRiyAvYXBpL2twLyogKNC/0YDQsNCy0LjQu9CwIEFQSSA9IG51bGwpLgoKbWlncmF0ZSgoYXBwKSA9PiB7CiAgICBjb25z
dCBzcGFjZXMgPSBuZXcgQ29sbGVjdGlvbih7CiAgICAgICAgdHlwZTogImJhc2UiLAogICAgICAgIG5hbWU6ICJrcF9zcGFjZXMi
LAogICAgICAgIGxpc3RSdWxlOiBudWxsLCB2aWV3UnVsZTogbnVsbCwgY3JlYXRlUnVsZTogbnVsbCwgdXBkYXRlUnVsZTogbnVs
bCwgZGVsZXRlUnVsZTogbnVsbCwKICAgICAgICBmaWVsZHM6IFsKICAgICAgICAgICAgeyB0eXBlOiAidGV4dCIsIG5hbWU6ICJu
YW1lIiwgbWF4OiA4MCB9LAogICAgICAgICAgICB7IHR5cGU6ICJ0ZXh0IiwgbmFtZTogImNvZGUiLCBtYXg6IDIwIH0sCiAgICAg
ICAgICAgIHsgdHlwZTogInRleHQiLCBuYW1lOiAib3duZXIiLCBtYXg6IDQwIH0sCiAgICAgICAgICAgIHsgdHlwZTogImpzb24i
LCBuYW1lOiAibWVtYmVycyIsIG1heFNpemU6IDIwMDAwMCB9LAogICAgICAgICAgICB7IHR5cGU6ICJib29sIiwgbmFtZTogInBl
cnNvbmFsIiB9LAogICAgICAgICAgICB7IHR5cGU6ICJhdXRvZGF0ZSIsIG5hbWU6ICJjcmVhdGVkIiwgb25DcmVhdGU6IHRydWUs
IG9uVXBkYXRlOiBmYWxzZSB9LAogICAgICAgICAgICB7IHR5cGU6ICJhdXRvZGF0ZSIsIG5hbWU6ICJ1cGRhdGVkIiwgb25DcmVh
dGU6IHRydWUsIG9uVXBkYXRlOiB0cnVlIH0sCiAgICAgICAgXSwKICAgICAgICBpbmRleGVzOiBbCiAgICAgICAgICAgICJDUkVB
VEUgSU5ERVggaWR4X2twX3NwYWNlc19jb2RlIE9OIGtwX3NwYWNlcyAoY29kZSkiLAogICAgICAgICAgICAiQ1JFQVRFIElOREVY
IGlkeF9rcF9zcGFjZXNfb3duZXIgT04ga3Bfc3BhY2VzIChvd25lcikiLAogICAgICAgIF0sCiAgICB9KQogICAgYXBwLnNhdmUo
c3BhY2VzKQoKICAgIGNvbnN0IGRvY3MgPSBuZXcgQ29sbGVjdGlvbih7CiAgICAgICAgdHlwZTogImJhc2UiLAogICAgICAgIG5h
bWU6ICJrcF9kb2NzIiwKICAgICAgICBsaXN0UnVsZTogbnVsbCwgdmlld1J1bGU6IG51bGwsIGNyZWF0ZVJ1bGU6IG51bGwsIHVw
ZGF0ZVJ1bGU6IG51bGwsIGRlbGV0ZVJ1bGU6IG51bGwsCiAgICAgICAgZmllbGRzOiBbCiAgICAgICAgICAgIHsgdHlwZTogInRl
eHQiLCBuYW1lOiAic3BhY2UiLCByZXF1aXJlZDogdHJ1ZSwgbWF4OiA0MCB9LAogICAgICAgICAgICB7IHR5cGU6ICJ0ZXh0Iiwg
bmFtZTogImNpZCIsIHJlcXVpcmVkOiB0cnVlLCBtYXg6IDY0IH0sCiAgICAgICAgICAgIHsgdHlwZTogInRleHQiLCBuYW1lOiAi
a2luZCIsIG1heDogMzAgfSwKICAgICAgICAgICAgeyB0eXBlOiAianNvbiIsIG5hbWU6ICJkYXRhIiwgbWF4U2l6ZTogMTAwMDAw
MCB9LAogICAgICAgICAgICB7IHR5cGU6ICJib29sIiwgbmFtZTogImRlbGV0ZWQiIH0sCiAgICAgICAgICAgIHsgdHlwZTogIm51
bWJlciIsIG5hbWU6ICJjdHMiIH0sCiAgICAgICAgICAgIHsgdHlwZTogIm51bWJlciIsIG5hbWU6ICJzcnYiIH0sCiAgICAgICAg
ICAgIHsgdHlwZTogInRleHQiLCBuYW1lOiAiYXV0aG9yIiwgbWF4OiA0MCB9LAogICAgICAgICAgICB7IHR5cGU6ICJhdXRvZGF0
ZSIsIG5hbWU6ICJjcmVhdGVkIiwgb25DcmVhdGU6IHRydWUsIG9uVXBkYXRlOiBmYWxzZSB9LAogICAgICAgICAgICB7IHR5cGU6
ICJhdXRvZGF0ZSIsIG5hbWU6ICJ1cGRhdGVkIiwgb25DcmVhdGU6IHRydWUsIG9uVXBkYXRlOiB0cnVlIH0sCiAgICAgICAgXSwK
ICAgICAgICBpbmRleGVzOiBbCiAgICAgICAgICAgICJDUkVBVEUgVU5JUVVFIElOREVYIGlkeF9rcF9kb2NzX3NwYWNlX2NpZCBP
TiBrcF9kb2NzIChzcGFjZSwgY2lkKSIsCiAgICAgICAgICAgICJDUkVBVEUgSU5ERVggaWR4X2twX2RvY3Nfc3BhY2Vfc3J2IE9O
IGtwX2RvY3MgKHNwYWNlLCBzcnYpIiwKICAgICAgICBdLAogICAgfSkKICAgIGFwcC5zYXZlKGRvY3MpCn0sIChhcHApID0+IHsK
ICAgIGZvciAoY29uc3QgbiBvZiBbImtwX2RvY3MiLCAia3Bfc3BhY2VzIl0pIHsKICAgICAgICB0cnkgeyBhcHAuZGVsZXRlKGFw
cC5maW5kQ29sbGVjdGlvbkJ5TmFtZU9ySWQobikpIH0gY2F0Y2ggKF8pIHt9CiAgICB9Cn0pCg==
B64
base64 -d > "$DIR/pb_hooks/kp_utils.js" <<'B64'
Ly8g0J7QsdGJ0LjQtSDRhNGD0L3QutGG0LjQuCDQtNC70Y8g0LzQsNGA0YjRgNGD0YLQvtCyINCa0L7Qv9C40LvQutC4LiDQn9C+
0LTQutC70Y7Rh9Cw0Y7RgtGB0Y8g0YfQtdGA0LXQtyByZXF1aXJlKCkg0LLQvdGD0YLRgNC4INC60LDQttC00L7Qs9C+INC+0LHR
gNCw0LHQvtGC0YfQuNC60LAuCgpmdW5jdGlvbiBtZW1iZXJzKHJlYykgewogICAgdHJ5IHsKICAgICAgICBjb25zdCByYXcgPSBy
ZWMuZ2V0U3RyaW5nKCJtZW1iZXJzIikKICAgICAgICBjb25zdCBhcnIgPSBKU09OLnBhcnNlKHJhdyB8fCAiW10iKQogICAgICAg
IHJldHVybiBBcnJheS5pc0FycmF5KGFycikgPyBhcnIgOiBbXQogICAgfSBjYXRjaCAoXykgeyByZXR1cm4gW10gfQp9CgpmdW5j
dGlvbiBpc01lbWJlcihyZWMsIHVpZCkgewogICAgcmV0dXJuIG1lbWJlcnMocmVjKS5pbmRleE9mKHVpZCkgPj0gMAp9CgpmdW5j
dGlvbiBzcGFjZUpTT04oYXBwLCByZWMpIHsKICAgIGNvbnN0IGlkcyA9IG1lbWJlcnMocmVjKQogICAgY29uc3QgcGVvcGxlID0g
W10KICAgIGZvciAoY29uc3QgaWQgb2YgaWRzKSB7CiAgICAgICAgdHJ5IHsKICAgICAgICAgICAgY29uc3QgdSA9IGFwcC5maW5k
UmVjb3JkQnlJZCgidXNlcnMiLCBpZCkKICAgICAgICAgICAgcGVvcGxlLnB1c2goeyBpZDogaWQsIG5hbWU6IHUuZ2V0U3RyaW5n
KCJuYW1lIiksIGVtYWlsOiB1LmdldFN0cmluZygiZW1haWwiKSB9KQogICAgICAgIH0gY2F0Y2ggKF8pIHsKICAgICAgICAgICAg
cGVvcGxlLnB1c2goeyBpZDogaWQsIG5hbWU6ICIiLCBlbWFpbDogIiIgfSkKICAgICAgICB9CiAgICB9CiAgICByZXR1cm4gewog
ICAgICAgIGlkOiByZWMuaWQsCiAgICAgICAgbmFtZTogcmVjLmdldFN0cmluZygibmFtZSIpLAogICAgICAgIGNvZGU6IHJlYy5n
ZXRCb29sKCJwZXJzb25hbCIpID8gIiIgOiByZWMuZ2V0U3RyaW5nKCJjb2RlIiksCiAgICAgICAgb3duZXI6IHJlYy5nZXRTdHJp
bmcoIm93bmVyIiksCiAgICAgICAgcGVyc29uYWw6IHJlYy5nZXRCb29sKCJwZXJzb25hbCIpLAogICAgICAgIG1lbWJlcnM6IHBl
b3BsZSwKICAgIH0KfQoKZnVuY3Rpb24gdXNlclNwYWNlcyhhcHAsIHVpZCkgewogICAgY29uc3QgZm91bmQgPSBhcHAuZmluZFJl
Y29yZHNCeUZpbHRlcigia3Bfc3BhY2VzIiwgIm1lbWJlcnMgfiB7OnF9IiwgImNyZWF0ZWQiLCAyMDAsIDAsIHsgcTogJyInICsg
dWlkICsgJyInIH0pCiAgICByZXR1cm4gZm91bmQuZmlsdGVyKChyKSA9PiBpc01lbWJlcihyLCB1aWQpKQp9CgpmdW5jdGlvbiBy
ZXF1aXJlU3BhY2UoYXBwLCBzcGFjZUlkLCB1aWQpIHsKICAgIGxldCByZWMKICAgIHRyeSB7IHJlYyA9IGFwcC5maW5kUmVjb3Jk
QnlJZCgia3Bfc3BhY2VzIiwgc3BhY2VJZCkgfSBjYXRjaCAoXykgeyB0aHJvdyBuZXcgTm90Rm91bmRFcnJvcigi0J/RgNC+0YHR
gtGA0LDQvdGB0YLQstC+INC90LUg0L3QsNC50LTQtdC90L4iKSB9CiAgICBpZiAoIWlzTWVtYmVyKHJlYywgdWlkKSkgdGhyb3cg
bmV3IEZvcmJpZGRlbkVycm9yKCLQndC10YIg0LTQvtGB0YLRg9C/0LAg0Log0Y3RgtC+0LzRgyDQv9GA0L7RgdGC0YDQsNC90YHR
gtCy0YMiKQogICAgcmV0dXJuIHJlYwp9CgpmdW5jdGlvbiBuZXdDb2RlKCkgewogICAgcmV0dXJuICRzZWN1cml0eS5yYW5kb21T
dHJpbmdXaXRoQWxwaGFiZXQoNiwgIkFCQ0RFRkdISktMTU5QUVJTVFVWV1hZWjIzNDU2Nzg5IikKfQoKbW9kdWxlLmV4cG9ydHMg
PSB7IG1lbWJlcnMsIGlzTWVtYmVyLCBzcGFjZUpTT04sIHVzZXJTcGFjZXMsIHJlcXVpcmVTcGFjZSwgbmV3Q29kZSB9Cg==
B64
base64 -d > "$DIR/pb_hooks/kopilka.pb.js" <<'B64'
Ly8vIDxyZWZlcmVuY2UgcGF0aD0iLi4vcGJfZGF0YS90eXBlcy5kLnRzIiAvPgovLyDQnNCw0YDRiNGA0YPRgtGLINGB0LjQvdGF
0YDQvtC90LjQt9Cw0YbQuNC4INCa0L7Qv9C40LvQutC4LiDQktGB0LUg0YLRgNC10LHRg9GO0YIg0LLRhdC+0LQg0L/QvtC70YzQ
t9C+0LLQsNGC0LXQu9GPICjQutC+0LvQu9C10LrRhtC40Y8gdXNlcnMpLgoKLy8g0KHQv9C40YHQvtC6INC/0YDQvtGB0YLRgNCw
0L3RgdGC0LIg0L/QvtC70YzQt9C+0LLQsNGC0LXQu9GPOyDQu9C40YfQvdC+0LUg0YHQvtC30LTQsNGR0YLRgdGPINCw0LLRgtC+
0LzQsNGC0LjRh9C10YHQutC4Lgpyb3V0ZXJBZGQoIlBPU1QiLCAiL2FwaS9rcC9zcGFjZXMiLCAoZSkgPT4gewogICAgY29uc3Qg
dSA9IHJlcXVpcmUoYCR7X19ob29rc30va3BfdXRpbHMuanNgKQogICAgY29uc3QgdWlkID0gZS5hdXRoLmlkCiAgICBsZXQgbGlz
dCA9IHUudXNlclNwYWNlcyhlLmFwcCwgdWlkKQogICAgaWYgKCFsaXN0LnNvbWUoKHIpID0+IHIuZ2V0Qm9vbCgicGVyc29uYWwi
KSAmJiByLmdldFN0cmluZygib3duZXIiKSA9PT0gdWlkKSkgewogICAgICAgIGNvbnN0IGNvbCA9IGUuYXBwLmZpbmRDb2xsZWN0
aW9uQnlOYW1lT3JJZCgia3Bfc3BhY2VzIikKICAgICAgICBjb25zdCByZWMgPSBuZXcgUmVjb3JkKGNvbCkKICAgICAgICByZWMu
c2V0KCJuYW1lIiwgItCb0LjRh9C90L7QtSIpCiAgICAgICAgcmVjLnNldCgib3duZXIiLCB1aWQpCiAgICAgICAgcmVjLnNldCgi
bWVtYmVycyIsIFt1aWRdKQogICAgICAgIHJlYy5zZXQoInBlcnNvbmFsIiwgdHJ1ZSkKICAgICAgICByZWMuc2V0KCJjb2RlIiwg
dS5uZXdDb2RlKCkpCiAgICAgICAgZS5hcHAuc2F2ZShyZWMpCiAgICAgICAgbGlzdCA9IHUudXNlclNwYWNlcyhlLmFwcCwgdWlk
KQogICAgfQogICAgcmV0dXJuIGUuanNvbigyMDAsIHsgc3BhY2VzOiBsaXN0Lm1hcCgocikgPT4gdS5zcGFjZUpTT04oZS5hcHAs
IHIpKSB9KQp9LCAkYXBpcy5yZXF1aXJlQXV0aCgidXNlcnMiKSkKCi8vINCh0L7Qt9C00LDRgtGMINC+0LHRidC10LUg0L/RgNC+
0YHRgtGA0LDQvdGB0YLQstC+ICjQvdCw0L/RgNC40LzQtdGALCDCq9Ch0LXQvNGM0Y/CuykuCnJvdXRlckFkZCgiUE9TVCIsICIv
YXBpL2twL3NwYWNlL2NyZWF0ZSIsIChlKSA9PiB7CiAgICBjb25zdCB1ID0gcmVxdWlyZShgJHtfX2hvb2tzfS9rcF91dGlscy5q
c2ApCiAgICBjb25zdCBib2R5ID0gZS5yZXF1ZXN0SW5mbygpLmJvZHkgfHwge30KICAgIGNvbnN0IG5hbWUgPSBTdHJpbmcoYm9k
eS5uYW1lIHx8ICLQodC10LzRjNGPIikudHJpbSgpLnNsaWNlKDAsIDgwKSB8fCAi0KHQtdC80YzRjyIKICAgIGNvbnN0IGNvbCA9
IGUuYXBwLmZpbmRDb2xsZWN0aW9uQnlOYW1lT3JJZCgia3Bfc3BhY2VzIikKICAgIGNvbnN0IHJlYyA9IG5ldyBSZWNvcmQoY29s
KQogICAgcmVjLnNldCgibmFtZSIsIG5hbWUpCiAgICByZWMuc2V0KCJvd25lciIsIGUuYXV0aC5pZCkKICAgIHJlYy5zZXQoIm1l
bWJlcnMiLCBbZS5hdXRoLmlkXSkKICAgIHJlYy5zZXQoInBlcnNvbmFsIiwgZmFsc2UpCiAgICByZWMuc2V0KCJjb2RlIiwgdS5u
ZXdDb2RlKCkpCiAgICBlLmFwcC5zYXZlKHJlYykKICAgIHJldHVybiBlLmpzb24oMjAwLCB7IHNwYWNlOiB1LnNwYWNlSlNPTihl
LmFwcCwgcmVjKSB9KQp9LCAkYXBpcy5yZXF1aXJlQXV0aCgidXNlcnMiKSkKCi8vINCS0YHRgtGD0L/QuNGC0Ywg0L/QviDQutC+
0LTRgyDQv9GA0LjQs9C70LDRiNC10L3QuNGPLgpyb3V0ZXJBZGQoIlBPU1QiLCAiL2FwaS9rcC9zcGFjZS9qb2luIiwgKGUpID0+
IHsKICAgIGNvbnN0IHUgPSByZXF1aXJlKGAke19faG9va3N9L2twX3V0aWxzLmpzYCkKICAgIGNvbnN0IGJvZHkgPSBlLnJlcXVl
c3RJbmZvKCkuYm9keSB8fCB7fQogICAgY29uc3QgY29kZSA9IFN0cmluZyhib2R5LmNvZGUgfHwgIiIpLnRyaW0oKS50b1VwcGVy
Q2FzZSgpCiAgICBpZiAoY29kZS5sZW5ndGggPCA0KSB0aHJvdyBuZXcgQmFkUmVxdWVzdEVycm9yKCLQktCy0LXQtNC40YLQtSDQ
utC+0LQg0L/RgNC40LPQu9Cw0YjQtdC90LjRjyIpCiAgICBsZXQgcmVjCiAgICB0cnkgeyByZWMgPSBlLmFwcC5maW5kRmlyc3RS
ZWNvcmRCeUZpbHRlcigia3Bfc3BhY2VzIiwgImNvZGUgPSB7OmN9ICYmIHBlcnNvbmFsID0gZmFsc2UiLCB7IGM6IGNvZGUgfSkg
fQogICAgY2F0Y2ggKF8pIHsgdGhyb3cgbmV3IE5vdEZvdW5kRXJyb3IoItCa0L7QtCDQvdC1INC90LDQudC00LXQvS4g0J/RgNC+
0LLQtdGA0YzRgtC1INC10LPQviDRgyDQstC70LDQtNC10LvRjNGG0LAg0LHRjtC00LbQtdGC0LAuIikgfQogICAgY29uc3QgbSA9
IHUubWVtYmVycyhyZWMpCiAgICBpZiAobS5pbmRleE9mKGUuYXV0aC5pZCkgPCAwKSB7IG0ucHVzaChlLmF1dGguaWQpOyByZWMu
c2V0KCJtZW1iZXJzIiwgbSk7IGUuYXBwLnNhdmUocmVjKSB9CiAgICByZXR1cm4gZS5qc29uKDIwMCwgeyBzcGFjZTogdS5zcGFj
ZUpTT04oZS5hcHAsIHJlYykgfSkKfSwgJGFwaXMucmVxdWlyZUF1dGgoInVzZXJzIikpCgovLyDQktGL0LnRgtC4INC40Lcg0L7Q
sdGJ0LXQs9C+INC/0YDQvtGB0YLRgNCw0L3RgdGC0LLQsCAo0LLQu9Cw0LTQtdC70LXRhiDQv9C10YDQtdC00LDRkdGCINC/0YDQ
sNCy0LAg0YHQu9C10LTRg9GO0YnQtdC80YMg0YPRh9Cw0YHRgtC90LjQutGDKS4Kcm91dGVyQWRkKCJQT1NUIiwgIi9hcGkva3Av
c3BhY2UvbGVhdmUiLCAoZSkgPT4gewogICAgY29uc3QgdSA9IHJlcXVpcmUoYCR7X19ob29rc30va3BfdXRpbHMuanNgKQogICAg
Y29uc3QgYm9keSA9IGUucmVxdWVzdEluZm8oKS5ib2R5IHx8IHt9CiAgICBjb25zdCByZWMgPSB1LnJlcXVpcmVTcGFjZShlLmFw
cCwgU3RyaW5nKGJvZHkuc3BhY2UgfHwgIiIpLCBlLmF1dGguaWQpCiAgICBpZiAocmVjLmdldEJvb2woInBlcnNvbmFsIikpIHRo
cm93IG5ldyBCYWRSZXF1ZXN0RXJyb3IoItCY0Lcg0LvQuNGH0L3QvtCz0L4g0L/RgNC+0YHRgtGA0LDQvdGB0YLQstCwINCy0YvQ
udGC0Lgg0L3QtdC70YzQt9GPIikKICAgIGNvbnN0IG0gPSB1Lm1lbWJlcnMocmVjKS5maWx0ZXIoKHgpID0+IHggIT09IGUuYXV0
aC5pZCkKICAgIHJlYy5zZXQoIm1lbWJlcnMiLCBtKQogICAgaWYgKHJlYy5nZXRTdHJpbmcoIm93bmVyIikgPT09IGUuYXV0aC5p
ZCAmJiBtLmxlbmd0aCA+IDApIHJlYy5zZXQoIm93bmVyIiwgbVswXSkKICAgIGUuYXBwLnNhdmUocmVjKQogICAgcmV0dXJuIGUu
anNvbigyMDAsIHsgb2s6IHRydWUgfSkKfSwgJGFwaXMucmVxdWlyZUF1dGgoInVzZXJzIikpCgovLyDQn9C10YDQtdC40LzQtdC9
0L7QstCw0YLRjCwg0L7QsdC90L7QstC40YLRjCDQutC+0LQg0LjQu9C4INGD0LTQsNC70LjRgtGMINGD0YfQsNGB0YLQvdC40LrQ
sCAo0YLQvtC70YzQutC+INCy0LvQsNC00LXQu9C10YYpLgpyb3V0ZXJBZGQoIlBPU1QiLCAiL2FwaS9rcC9zcGFjZS91cGRhdGUi
LCAoZSkgPT4gewogICAgY29uc3QgdSA9IHJlcXVpcmUoYCR7X19ob29rc30va3BfdXRpbHMuanNgKQogICAgY29uc3QgYm9keSA9
IGUucmVxdWVzdEluZm8oKS5ib2R5IHx8IHt9CiAgICBjb25zdCByZWMgPSB1LnJlcXVpcmVTcGFjZShlLmFwcCwgU3RyaW5nKGJv
ZHkuc3BhY2UgfHwgIiIpLCBlLmF1dGguaWQpCiAgICBpZiAocmVjLmdldFN0cmluZygib3duZXIiKSAhPT0gZS5hdXRoLmlkKSB0
aHJvdyBuZXcgRm9yYmlkZGVuRXJyb3IoItCt0YLQviDQvNC+0LbQtdGCINGC0L7Qu9GM0LrQviDQstC70LDQtNC10LvQtdGGIikK
ICAgIGlmIChib2R5Lm5hbWUpIHJlYy5zZXQoIm5hbWUiLCBTdHJpbmcoYm9keS5uYW1lKS50cmltKCkuc2xpY2UoMCwgODApKQog
ICAgaWYgKGJvZHkubmV3Q29kZSkgcmVjLnNldCgiY29kZSIsIHUubmV3Q29kZSgpKQogICAgaWYgKGJvZHkua2ljayAmJiBib2R5
LmtpY2sgIT09IGUuYXV0aC5pZCkgcmVjLnNldCgibWVtYmVycyIsIHUubWVtYmVycyhyZWMpLmZpbHRlcigoeCkgPT4geCAhPT0g
Ym9keS5raWNrKSkKICAgIGUuYXBwLnNhdmUocmVjKQogICAgcmV0dXJuIGUuanNvbigyMDAsIHsgc3BhY2U6IHUuc3BhY2VKU09O
KGUuYXBwLCByZWMpIH0pCn0sICRhcGlzLnJlcXVpcmVBdXRoKCJ1c2VycyIpKQoKLy8g0JfQsNCx0YDQsNGC0Ywg0LjQt9C80LXQ
vdC10L3QuNGPINC/0L7RgdC70LUg0LrRg9GA0YHQvtGA0LAgc2luY2UgKNGB0LXRgNCy0LXRgNC90L7QtSDQstGA0LXQvNGPINC3
0LDQv9C40YHQuCkuCnJvdXRlckFkZCgiUE9TVCIsICIvYXBpL2twL3B1bGwiLCAoZSkgPT4gewogICAgY29uc3QgdSA9IHJlcXVp
cmUoYCR7X19ob29rc30va3BfdXRpbHMuanNgKQogICAgY29uc3QgYm9keSA9IGUucmVxdWVzdEluZm8oKS5ib2R5IHx8IHt9CiAg
ICBjb25zdCBzcGFjZSA9IFN0cmluZyhib2R5LnNwYWNlIHx8ICIiKQogICAgdS5yZXF1aXJlU3BhY2UoZS5hcHAsIHNwYWNlLCBl
LmF1dGguaWQpCiAgICBjb25zdCBzaW5jZSA9IE51bWJlcihib2R5LnNpbmNlIHx8IDApCiAgICBjb25zdCBsaW1pdCA9IDUwMAog
ICAgY29uc3QgcmVjcyA9IGUuYXBwLmZpbmRSZWNvcmRzQnlGaWx0ZXIoImtwX2RvY3MiLCAic3BhY2UgPSB7OnN9ICYmIHNydiA+
IHs6c2luY2V9IiwgInNydiIsIGxpbWl0ICsgMSwgMCwgeyBzOiBzcGFjZSwgc2luY2U6IHNpbmNlIH0pCiAgICBjb25zdCBtb3Jl
ID0gcmVjcy5sZW5ndGggPiBsaW1pdAogICAgY29uc3Qgb3V0ID0gW10KICAgIGxldCBjdXJzb3IgPSBzaW5jZQogICAgZm9yIChj
b25zdCByIG9mIHJlY3Muc2xpY2UoMCwgbGltaXQpKSB7CiAgICAgICAgbGV0IGRhdGEgPSB7fQogICAgICAgIHRyeSB7IGRhdGEg
PSBKU09OLnBhcnNlKHIuZ2V0U3RyaW5nKCJkYXRhIikgfHwgInt9IikgfSBjYXRjaCAoXykge30KICAgICAgICBvdXQucHVzaCh7
IGNpZDogci5nZXRTdHJpbmcoImNpZCIpLCBraW5kOiByLmdldFN0cmluZygia2luZCIpLCBkYXRhOiBkYXRhLCBkZWxldGVkOiBy
LmdldEJvb2woImRlbGV0ZWQiKSwKICAgICAgICAgICAgICAgICAgIGN0czogci5nZXRGbG9hdCgiY3RzIiksIHNydjogci5nZXRG
bG9hdCgic3J2IiksIGF1dGhvcjogci5nZXRTdHJpbmcoImF1dGhvciIpIH0pCiAgICAgICAgY3Vyc29yID0gci5nZXRGbG9hdCgi
c3J2IikKICAgIH0KICAgIHJldHVybiBlLmpzb24oMjAwLCB7IGRvY3M6IG91dCwgY3Vyc29yOiBjdXJzb3IsIG1vcmU6IG1vcmUg
fSkKfSwgJGFwaXMucmVxdWlyZUF1dGgoInVzZXJzIikpCgovLyDQntGC0L/RgNCw0LLQuNGC0Ywg0LjQt9C80LXQvdC10L3QuNGP
LiDQn9C+0LHQtdC20LTQsNC10YIg0LHQvtC70LXQtSDRgdCy0LXQttCw0Y8g0L/RgNCw0LLQutCwICjQv9C+INCy0YDQtdC80LXQ
vdC4INC60LvQuNC10L3RgtCwKS4Kcm91dGVyQWRkKCJQT1NUIiwgIi9hcGkva3AvcHVzaCIsIChlKSA9PiB7CiAgICBjb25zdCB1
ID0gcmVxdWlyZShgJHtfX2hvb2tzfS9rcF91dGlscy5qc2ApCiAgICBjb25zdCBib2R5ID0gZS5yZXF1ZXN0SW5mbygpLmJvZHkg
fHwge30KICAgIGNvbnN0IHNwYWNlID0gU3RyaW5nKGJvZHkuc3BhY2UgfHwgIiIpCiAgICB1LnJlcXVpcmVTcGFjZShlLmFwcCwg
c3BhY2UsIGUuYXV0aC5pZCkKICAgIGNvbnN0IGRvY3MgPSBBcnJheS5pc0FycmF5KGJvZHkuZG9jcykgPyBib2R5LmRvY3Muc2xp
Y2UoMCwgNTAwKSA6IFtdCiAgICBjb25zdCBjb2wgPSBlLmFwcC5maW5kQ29sbGVjdGlvbkJ5TmFtZU9ySWQoImtwX2RvY3MiKQog
ICAgY29uc3QgYmFzZSA9IERhdGUubm93KCkgKiAxMDAwCiAgICBsZXQgaSA9IDAsIHNhdmVkID0gMCwgc2tpcHBlZCA9IDAKICAg
IGZvciAoY29uc3QgZCBvZiBkb2NzKSB7CiAgICAgICAgY29uc3QgY2lkID0gU3RyaW5nKGQuY2lkIHx8ICIiKQogICAgICAgIGlm
ICghY2lkKSBjb250aW51ZQogICAgICAgIGxldCByZWMgPSBudWxsCiAgICAgICAgdHJ5IHsgcmVjID0gZS5hcHAuZmluZEZpcnN0
UmVjb3JkQnlGaWx0ZXIoImtwX2RvY3MiLCAic3BhY2UgPSB7OnN9ICYmIGNpZCA9IHs6Y30iLCB7IHM6IHNwYWNlLCBjOiBjaWQg
fSkgfSBjYXRjaCAoXykge30KICAgICAgICBjb25zdCBjdHMgPSBOdW1iZXIoZC5jdHMgfHwgMCkKICAgICAgICBpZiAocmVjICYm
IHJlYy5nZXRGbG9hdCgiY3RzIikgPiBjdHMpIHsgc2tpcHBlZCsrOyBjb250aW51ZSB9CiAgICAgICAgaWYgKCFyZWMpIHsgcmVj
ID0gbmV3IFJlY29yZChjb2wpOyByZWMuc2V0KCJzcGFjZSIsIHNwYWNlKTsgcmVjLnNldCgiY2lkIiwgY2lkKSB9CiAgICAgICAg
cmVjLnNldCgia2luZCIsIFN0cmluZyhkLmtpbmQgfHwgIiIpKQogICAgICAgIHJlYy5zZXQoImRhdGEiLCBkLmRhdGEgfHwge30p
CiAgICAgICAgcmVjLnNldCgiZGVsZXRlZCIsICEhZC5kZWxldGVkKQogICAgICAgIHJlYy5zZXQoImN0cyIsIGN0cykKICAgICAg
ICByZWMuc2V0KCJzcnYiLCBiYXNlICsgKGkrKykpCiAgICAgICAgcmVjLnNldCgiYXV0aG9yIiwgZC5hdXRob3IgPyBTdHJpbmco
ZC5hdXRob3IpIDogZS5hdXRoLmlkKQogICAgICAgIGUuYXBwLnNhdmUocmVjKQogICAgICAgIHNhdmVkKysKICAgIH0KICAgIHJl
dHVybiBlLmpzb24oMjAwLCB7IHNhdmVkOiBzYXZlZCwgc2tpcHBlZDogc2tpcHBlZCB9KQp9LCAkYXBpcy5yZXF1aXJlQXV0aCgi
dXNlcnMiKSkKCi8vINCf0YDQvtCy0LXRgNC60LAsINGH0YLQviDRgdC10YDQstC10YAg0LbQuNCy0L7QuSAo0LTQu9GPINGN0LrR
gNCw0L3QsCDQvdCw0YHRgtGA0L7QtdC6KS4Kcm91dGVyQWRkKCJHRVQiLCAiL2FwaS9rcC9waW5nIiwgKGUpID0+IHsKICAgIHJl
dHVybiBlLmpzb24oMjAwLCB7IG9rOiB0cnVlLCBhcHA6ICJrb3BpbGthIiwgdmVyc2lvbjogMSB9KQp9KQoKLy8g0JLRhdC+0LQg
0YfQtdGA0LXQtyBHb29nbGUsINCv0L3QtNC10LrRgSDQuCBBcHBsZTog0YHQtdGA0LLQuNGBINCy0L7Qt9Cy0YDQsNGJ0LDQtdGC
INC/0L7Qu9GM0LfQvtCy0LDRgtC10LvRjyDRgdGO0LTQsCwg0LAg0LzRiyDQv9C10YDQtdC00LDRkdC8INC60L7QtCDQsiDQv9GA
0LjQu9C+0LbQtdC90LjQtS4KLy8gUmVkaXJlY3QgVVJJINCy0L4g0LLRgdC10YUg0LrQsNCx0LjQvdC10YLQsNGFOiBodHRwczov
L9CS0JDQqC3QlNCe0JzQldCdL2FwaS9rcC9vYXV0aC1jYWxsYmFjawpyb3V0ZXJBZGQoIkdFVCIsICIvYXBpL2twL29hdXRoLWNh
bGxiYWNrIiwgKGUpID0+IHsKICAgIGNvbnN0IHEgPSBlLnJlcXVlc3QudXJsLnJhd1F1ZXJ5IHx8ICIiCiAgICByZXR1cm4gZS5y
ZWRpcmVjdCgzMDIsICJrb3NoZWxlazovL29hdXRoPyIgKyBxKQp9KQovLyBBcHBsZSDQv9GA0LjRgdGL0LvQsNC10YIg0LrQvtC0
IFBPU1Qt0LfQsNC/0YDQvtGB0L7QvCAoZm9ybV9wb3N0KS4Kcm91dGVyQWRkKCJQT1NUIiwgIi9hcGkva3Avb2F1dGgtY2FsbGJh
Y2siLCAoZSkgPT4gewogICAgY29uc3QgaW5mbyA9IGUucmVxdWVzdEluZm8oKQogICAgY29uc3QgYiA9IGluZm8uYm9keSB8fCB7
fQogICAgY29uc3QgcGFydHMgPSBbXQogICAgZm9yIChjb25zdCBrIG9mIFsiY29kZSIsICJzdGF0ZSIsICJlcnJvciJdKSB7CiAg
ICAgICAgaWYgKGJba10pIHBhcnRzLnB1c2goayArICI9IiArIGVuY29kZVVSSUNvbXBvbmVudChTdHJpbmcoYltrXSkpKQogICAg
fQogICAgcmV0dXJuIGUucmVkaXJlY3QoMzAzLCAia29zaGVsZWs6Ly9vYXV0aD8iICsgcGFydHMuam9pbigiJiIpKQp9KQoKLy8g
0J/RgNC+0LLQsNC50LTQtdGA0Ysg0LLRhdC+0LTQsCDQuNC3IC9ldGMva29waWxrYS5lbnY6IEtQX0dPT0dMRV9JRC9LUF9HT09H
TEVfU0VDUkVULCBLUF9ZQU5ERVhfSUQvS1BfWUFOREVYX1NFQ1JFVCwgS1BfQVBQTEVfSUQvS1BfQVBQTEVfU0VDUkVULgpvbkJv
b3RzdHJhcCgoZSkgPT4gewogICAgZS5uZXh0KCkKICAgIGNvbnN0IGxpc3QgPSBbXQogICAgZm9yIChjb25zdCBbbmFtZSwga2V5
XSBvZiBbWyJnb29nbGUiLCAiR09PR0xFIl0sIFsieWFuZGV4IiwgIllBTkRFWCJdLCBbImFwcGxlIiwgIkFQUExFIl1dKSB7CiAg
ICAgICAgY29uc3QgaWQgPSAkb3MuZ2V0ZW52KCJLUF8iICsga2V5ICsgIl9JRCIpCiAgICAgICAgY29uc3Qgc2VjcmV0ID0gJG9z
LmdldGVudigiS1BfIiArIGtleSArICJfU0VDUkVUIikKICAgICAgICBpZiAoaWQgJiYgc2VjcmV0KSBsaXN0LnB1c2goeyBuYW1l
OiBuYW1lLCBjbGllbnRJZDogaWQsIGNsaWVudFNlY3JldDogc2VjcmV0IH0pCiAgICB9CiAgICBpZiAoIWxpc3QubGVuZ3RoKSBy
ZXR1cm4KICAgIHRyeSB7CiAgICAgICAgY29uc3QgYyA9IGUuYXBwLmZpbmRDb2xsZWN0aW9uQnlOYW1lT3JJZCgidXNlcnMiKQog
ICAgICAgIHVubWFyc2hhbCh7IG9hdXRoMjogeyBlbmFibGVkOiB0cnVlLCBtYXBwZWRGaWVsZHM6IHsgbmFtZTogIm5hbWUiLCBh
dmF0YXJVUkw6ICIiIH0sIHByb3ZpZGVyczogbGlzdCB9IH0sIGMpCiAgICAgICAgZS5hcHAuc2F2ZShjKQogICAgICAgIGNvbnNv
bGUubG9nKCJLb3BpbGthOiDQstGF0L7QtCDRh9C10YDQtdC3ICIgKyBsaXN0Lm1hcCgocCkgPT4gcC5uYW1lKS5qb2luKCIsICIp
ICsgIiDQstC60LvRjtGH0ZHQvSIpCiAgICB9IGNhdGNoIChlcnIpIHsKICAgICAgICBjb25zb2xlLmxvZygiS29waWxrYTog0L3Q
tSDRg9C00LDQu9C+0YHRjCDQstC60LvRjtGH0LjRgtGMINCy0YXQvtC0INGH0LXRgNC10Lcg0YHQtdGA0LLQuNGB0Ys6IiwgZXJy
KQogICAgfQp9KQo=
B64

id kopilka >/dev/null 2>&1 || useradd --system --home "$DIR" --shell /usr/sbin/nologin kopilka
chown -R kopilka:kopilka "$DIR"

cat > /etc/systemd/system/kopilka.service <<UNIT
[Unit]
Description=Kopilka sync server (PocketBase)
After=network.target

[Service]
User=kopilka
Group=kopilka
WorkingDirectory=$DIR
EnvironmentFile=-/etc/kopilka.env
ExecStart=$DIR/pocketbase serve --http=127.0.0.1:$PORT_INTERNAL --dir=$DIR/pb_data --hooksDir=$DIR/pb_hooks --migrationsDir=$DIR/pb_migrations
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now kopilka >/dev/null
sleep 3
curl -fsS "http://127.0.0.1:$PORT_INTERNAL/api/kp/ping" >/dev/null || die "сервер не отвечает: journalctl -u kopilka -n 50"

say "Готовлю команду для входа через Google, Яндекс и Apple"
cat > /usr/local/bin/kopilka-login <<'GOOG'
#!/usr/bin/env bash
# Включить вход через сервисы: sudo kopilka-login
set -e
[ "$(id -u)" -eq 0 ] || { echo "запустите через sudo"; exit 1; }
URL=$(cat /opt/kopilka/url 2>/dev/null || echo "https://ВАШ-ДОМЕН")
ENV=/etc/kopilka.env
touch "$ENV"; chmod 600 "$ENV"
echo "Redirect URI для всех сервисов:"
echo "    $URL/api/kp/oauth-callback"
echo
echo "Что настраиваем?  1) Google   2) Яндекс   3) Apple   4) Выключить сервис"
read -rp "> " C
case "$C" in
  1) K=GOOGLE ;; 2) K=YANDEX ;; 3) K=APPLE ;;
  4) read -rp "Какой (google/yandex/apple): " X; K=$(echo "$X" | tr a-z A-Z)
     sed -i "/^KP_${K}_/d" "$ENV"; systemctl restart kopilka; echo "Выключено."; exit 0 ;;
  *) echo "нужно 1-4"; exit 1 ;;
esac
if [ "$K" = APPLE ]; then
  echo "Для Apple: Client ID = Services ID (например ru.koshelek.signin),"
  echo "Client secret = JWT, который генерирует админка PocketBase (Users → OAuth2 → Apple → Generate secret). Действует 6 месяцев."
fi
read -rp "Client ID: " ID
read -rp "Client secret: " SECRET
[ -n "$ID" ] && [ -n "$SECRET" ] || { echo "нужны оба значения"; exit 1; }
sed -i "/^KP_${K}_/d" "$ENV"
printf 'KP_%s_ID=%s\nKP_%s_SECRET=%s\n' "$K" "$ID" "$K" "$SECRET" >> "$ENV"
systemctl restart kopilka
sleep 3
N=$(echo "$K" | tr A-Z a-z)
if curl -fsS http://127.0.0.1:8090/api/collections/users/auth-methods | grep -q "\"$N\""; then
  echo "Готово: в приложении появится кнопка входа через $N."
else
  echo "Не получилось — посмотрите: journalctl -u kopilka -n 30"
fi
GOOG
chmod +x /usr/local/bin/kopilka-login
ln -sf /usr/local/bin/kopilka-login /usr/local/bin/kopilka-google

say "Создаю администратора"
ADMIN_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
sudo -u kopilka "$DIR/pocketbase" superuser upsert "$EMAIL" "$ADMIN_PASS" --dir="$DIR/pb_data" >/dev/null

say "Настраиваю ежедневный бэкап базы (хранится 14 дней)"
cat > /etc/cron.daily/kopilka-backup <<CRON
#!/bin/sh
sqlite3 $DIR/pb_data/data.db ".backup '$DIR/backups/data-\$(date +%F).db'"
find $DIR/backups -name 'data-*.db' -mtime +14 -delete
CRON
chmod +x /etc/cron.daily/kopilka-backup

say "Настраиваю HTTPS через Nginx"
command -v nginx >/dev/null 2>&1 || apt-get install -y -qq nginx >/dev/null
apt-get install -y -qq certbot python3-certbot-nginx >/dev/null

owner_of() { ss -ltnpH "sport = :$1" 2>/dev/null | grep -o 'users:(("[^"]*' | head -1 | sed 's/users:(("//'; }
P80=$(owner_of 80); P443=$(owner_of 443)
echo "Порт 80 занят: ${P80:-свободен}; порт 443 занят: ${P443:-свободен}"
if [ -n "$P80" ] && [ "$P80" != "nginx" ]; then
  die "порт 80 занят процессом '$P80'. Он нужен для выпуска сертификата. Освободите его или напишите мне — подскажу обход."
fi
PUBPORT=443
if [ -n "$P443" ] && [ "$P443" != "nginx" ]; then
  PUBPORT=8443
  echo "Порт 443 занят '$P443' (скорее всего Xray/3X-UI). Сервер будет на порту 8443 — VPN не пострадает."
fi

CONF=/etc/nginx/conf.d/kopilka.conf
cat > "$CONF" <<NGX
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host:$PUBPORT\$request_uri; }
}
NGX
mkdir -p /var/www/html
nginx -t && systemctl reload nginx || systemctl restart nginx
certbot certonly --webroot -w /var/www/html -d "$DOMAIN" -m "$EMAIL" --agree-tos -n --keep-until-expiring

cat > "$CONF" <<NGX
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host:$PUBPORT\$request_uri; }
}
server {
    listen $PUBPORT ssl;
    http2 on;
    server_name $DOMAIN;
    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    client_max_body_size 20m;
    location / {
        proxy_pass http://127.0.0.1:$PORT_INTERNAL;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_read_timeout 360s;
    }
}
NGX
nginx -t || { sed -i 's/^    http2 on;$//' "$CONF"; sed -i "s/listen $PUBPORT ssl;/listen $PUBPORT ssl http2;/" "$CONF"; nginx -t; }
systemctl reload nginx
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
printf '#!/bin/sh\nsystemctl reload nginx\n' > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q active; then ufw allow 80/tcp >/dev/null; ufw allow "$PUBPORT"/tcp >/dev/null; fi

URL="https://$DOMAIN"; [ "$PUBPORT" = "443" ] || URL="https://$DOMAIN:$PUBPORT"
echo "$URL" > "$DIR/url"
sleep 1
curl -fsS "$URL/api/kp/ping" >/dev/null && OK="да" || OK="не отвечает снаружи — проверьте фаервол хостинга (порт $PUBPORT)"

cat <<DONE

$(printf '\033[1;32m')Готово!$(printf '\033[0m')

  Адрес сервера для приложения:  $URL
  Проверка снаружи:              $OK
  Админка:                       $URL/_/
  Вход в админку:                $EMAIL / $ADMIN_PASS   (сохраните пароль)
  Бэкапы базы:                   $DIR/backups (каждый день, 14 дней)
  Логи:                          journalctl -u kopilka -f

В приложении: Настройки → Синхронизация → вставьте адрес сервера → зарегистрируйтесь.
Вход через Google / Яндекс / Apple (по желанию): sudo kopilka-login
DONE
