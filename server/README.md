# Сервер синхронизации Копилки

PocketBase (один файл, SQLite) и логика синхронизации в `pb_hooks`. Сервер поддерживает:
- аккаунты: вход по почте и паролю;
- синхронизацию iPhone, iPad и других устройств;
- общие бюджеты для семьи, вход по коду приглашения;
- ежедневные бэкапы базы.

## Установка на VPS (Debian/Ubuntu)

1. В DNS вашего домена добавьте A-запись, например `money.ваш-домен.ru` → IP сервера.
2. На сервере выполните:

```
sudo bash install.sh money.ваш-домен.ru вы@почта.ru
```

Скрипт:
- скачает PocketBase;
- запустит его как службу `kopilka`;
- выпустит HTTPS-сертификат и настроит Nginx;
- включит ежедневные бэкапы.

Если порт 443 занят VPN (Xray/3X-UI), сервер встанет на порт 8443, а VPN не пострадает.

В конце скрипт покажет **адрес сервера** для приложения и пароль от админки.

## Обслуживание

- Логи: `journalctl -u kopilka -f`
- Перезапуск: `systemctl restart kopilka`
- Бэкапы: `/opt/kopilka/backups`
- Админка: `https://ваш-адрес/_/`

## Вход через Google, Яндекс и Apple

Сначала обновите сервер: снова запустите `sudo bash install.sh ваш-домен почта` (данные не пропадут).
Адрес возврата (Redirect URI) для всех сервисов один: `https://ВАШ-ДОМЕН/api/kp/oauth-callback`
(если сервер на порту 8443 — `https://ВАШ-ДОМЕН:8443/api/kp/oauth-callback`).
Ключи вводятся командой `sudo kopilka-login` — она спросит сервис, Client ID и secret.

### Google (бесплатно)
1. https://console.cloud.google.com → новый проект → **Google Auth Platform** → **Get started**: имя «Копилка», ваша почта, тип **External**.
2. **Audience** → **Publish app** (или добавьте свою почту и почту семьи в Test users).
3. **Clients** → **Create client** → **Web application** → в **Authorized redirect URIs** — адрес возврата.
4. Client ID и Client secret → `sudo kopilka-login` → 1.

### Яндекс (бесплатно)
1. https://oauth.yandex.ru/client/new → «Создать приложение» → платформа **Веб-сервисы**.
2. **Redirect URI** — адрес возврата. Доступы: **Доступ к адресу электронной почты** и **Доступ к логину, имени и фамилии**.
3. ClientID и Client secret → `sudo kopilka-login` → 2.

### Apple (нужен свой Apple Developer, 99 $ в год)
1. https://developer.apple.com/account → Identifiers → **Services IDs** → создайте, например `ru.koshelek.signin`, включите **Sign in with Apple**, в Return URLs — адрес возврата, домен — ваш домен.
2. Keys → новый ключ с **Sign in with Apple** → скачайте `.p8`, запишите Key ID и Team ID.
3. В админке сервера (`https://ВАШ-ДОМЕН/_/`) → Collections → users → ⚙ → OAuth2 → Apple → **Generate secret** (вставьте Team ID, Key ID, .p8). Получится длинный ключ (JWT), он действует 6 месяцев.
4. `sudo kopilka-login` → 3 → Client ID = Services ID, secret = этот ключ. Через полгода повторите шаги 3–4.

Один и тот же человек может входить любым способом: если почта совпадает, сервер узнаёт аккаунт.
