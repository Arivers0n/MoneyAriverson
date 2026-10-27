# Копилка — правила для Claude

Личное приложение для учёта финансов. Владелец — один человек (не программист), пользуется сам и с семьёй.

## Общение
- Всегда отвечай **на русском**.
- Объясняй просто, без лишней техники. Если что-то нужно сделать владельцу руками (SSH, ESign, настройки) — давай короткую пошаговую инструкцию с готовыми командами.
- Пароли на сервере **не меняем**.

## Из чего состоит
| Часть | Где | Стек |
|---|---|---|
| iPhone + iPad + виджет | `Koshelek/`, `KoshelekWidget/`, `project.yml` | SwiftUI, iOS 17+, SwiftData, XcodeGen |
| Android | `android/` | Kotlin 2.1, Jetpack Compose, minSdk 26, targetSdk 36 |
| Сервер синхронизации | `server/` | PocketBase 0.40 + JS-хуки на VPS |

- Bundle ID / applicationId: `ru.koshelek.app` (виджет `ru.koshelek.app.widget`). **Не менять** — иначе данные и обновления не перенесутся.
- Mac у владельца нет. Всё собирается в GitHub Actions:
  - `.github/workflows/build.yml` → `Koshelek.ipa` (macOS runner), ставится через ESign своим сертификатом;
  - `.github/workflows/android.yml` → подписанный `Kopilka.apk` (ключ `android/kopilka.keystore`), релиз `latest` + загрузка на сервер в коллекцию `kp_builds` для автообновления. `versionCode` = номер запуска CI.
- После пуша проверяй сборки: `gh run list -R Arivers0n/MoneyAriverson` и сообщай результат.

## Главное правило: две платформы — одно приложение
Любая новая функция или правка делается **и на iOS, и на Android** с одинаковым поведением, текстами и видом (с поправкой на родные элементы платформы). Если на одной платформе что-то сделать нельзя — сказать об этом явно.

Ориентир по файлам:
- главный экран: `Views/HomeView.swift`, `HomeBlocks.swift` ↔ `ui/HomeScreen.kt`;
- ввод операций, голос, скан: `InputViews.swift`, `VoiceOverlay.swift`, `ScanSupport.swift` ↔ `ui/TxForm.kt`, `Voice.kt`, `Scan.kt`, `Review.kt`;
- кредиты, долги, подписки: `DebtsView.swift`, `DebtDetailViews.swift` ↔ `ui/Payments.kt`;
- бюджеты, копилки, счета: `BudgetsView.swift`, `SavingsView.swift`, `Savings.swift` ↔ `ui/Goals.kt`;
- статистика, поиск, инсайты, советник: `StatsView.swift`, `MonthOverview.swift`, `Advisor.swift` ↔ `ui/Stats.kt`, `Overview.kt`;
- настройки, внешний вид: `SettingsView.swift`, `CustomizeViews.swift`, `Customization.swift` ↔ `ui/Settings.kt`, `Theme.kt`;
- логика и расчёты: `Logic.swift`, `Core.swift` ↔ `core/Logic.kt`;
- модели и синхронизация: `Models.swift`, `Sync.swift` ↔ `data/Models.kt`, `data/Sync.kt`, `data/Store.kt`.

## Дизайн
- Минималистично и «как родное приложение», ориентир — Qalta. Без перегруженности.
- iPad: колонка не растягивается на всю ширину; в ширину — две колонки. Android-планшеты (≥840dp) — так же.
- Всё на русском, суммы в рублях с пробелами между разрядами.
- Android: проверять вёрстку скриншот-тестами (`android/app/src/test/.../ScreensTest.kt`, Roborazzi; `./gradlew testDebugUnitTest -Proborazzi.test.record=true`, картинки в `app/build/screens/`).

## Синхронизация (общий формат, ломать нельзя)
Сервер хранит документы в `kp_docs`: `{space, cid, kind, data, deleted, cts, author}`.
- `kind`: `tx` (операция), `acc` (счёт), `debt` (кредит/долг), `rec` (регулярный платёж), `goal` (копилка), `prefs` (бюджет, лимиты, свои категории; `cid = "prefs"`).
- `cid` — UUID **в верхнем регистре**.
- `cts` — время изменения в **миллисекундах**; побеждает более новая правка.
- Даты верхнего уровня в `data` — секунды Unix. Даты, закодированные Swift `JSONEncoder` внутри вложенных структур, — секунды с 2001-01-01 (смещение 978307200).
- Платежи по долгу — плоский массив `[ключ, значение, ключ, значение, ...]`.
- Новые поля только **добавлять** и читать с безопасным значением по умолчанию — старые версии приложения на другом устройстве должны продолжать работать.

API сервера (`server/pb_hooks/kopilka.pb.js`): `/api/kp/pull`, `/api/kp/push`, `/api/kp/spaces`, `/api/kp/space/{create,join,leave,update}`, `/api/kp/invite`, `/api/kp/ping`, `/api/kp/oauth-callback`, `/api/kp/ai`, `/api/kp/ai/status`.
- Вход: Google и Яндекс через OAuth; сервер перекидывает обратно в приложение по ссылке `koshelek://oauth?...`.
- ИИ (голос, скан чека, советник) идёт **через сервер** с токеном пользователя; ключ лежит на сервере в `/etc/kopilka.env`, в приложения не вшивается.
- Семейный бюджет — общие «пространства» (`kp_spaces`), в каждой записи есть `author`.

## Сервер
- VPS: `https://2-27-25-140.sslip.io:8443` (Ubuntu, PocketBase за nginx).
- Хуки, утилиты и миграции из `server/` **встроены в `server/install.sh` в base64**. После любой правки в `server/pb_hooks` или `server/pb_migrations` нужно заново встроить их в `install.sh`.
- Владелец обновляет сервер сам: загружает `install.sh` в `/root` по SFTP и запускает
  `bash /root/install.sh 2-27-25-140.sslip.io andreychichkanov69@gmail.com`.
  Если правка затрагивает сервер — обязательно напомнить об этом.
- Настройки ключей (`KP_GOOGLE_*`, `KP_YANDEX_*`, `KP_AI_KEY`, `KP_AI_BASE`, `KP_AI_MODEL`) — в `/etc/kopilka.env`, в репозиторий их не класть.

## Связь с HabitFlow
HabitFlow (репо `Arivers0n/HabitFlow`, трекер привычек) взял отсюда вход, синхронизацию, ИИ-слой и кастомизацию и живёт **на том же сервере**: свои маршруты `/api/hf/*`, **общий аккаунт (коллекция `users`)**, данные раздельные.
Изменения общего (`/api/kp/ai`, `/api/kp/oauth-callback`, `users`, `install.sh`) могут сломать оба приложения — проверять оба и не терять чужие хуки при пересборке `install.sh`.

## Что уже есть
Бюджет и счета, копилки с автоправилами, кредиты/долги/микрозаймы с графиком платежей, подписки и календарь, голосовой ввод своими словами и скан чеков, ИИ-советник и инсайты, семейный бюджет, вход и синхронизация iPhone/iPad/Android, Siri, виджет, кастомизация (темы, фоны, 16 значков, вкладки Тема/Иконки/Экран), iPad в две колонки + сочетания клавиш.

На Android пока **нет**: напоминаний о платежах, бэкапа в файл и восстановления, импорта CSV, создания своих категорий, выбора значка.

## Виджеты со своим дизайном
- Настройки → «Виджеты»: 6 слотов («Виджет 1…6»), размеры малый/средний/большой (на iPhone ещё три для экрана блокировки — на Android их нет), пресеты, фон, раскладка, блоки (кольцо бюджета, баланс, копилка, платёж, неделя, напарник и др.), живой предпросмотр.
- Дизайны хранятся на устройстве и **не синхронизируются**. Названия значений в JSON одинаковы на обеих платформах.
- iOS: `Koshelek/Widgets/` (`Shared/` ещё и компилируется в расширение `KoshelekWidget`: WidgetConfig, WidgetSnapshot, WidgetRenderer, WidgetStorage; `WidgetStore`, `WidgetBuilderView`, `WidgetBlockEditor`). Данные идут через App Group `group.ru.koshelek.app` (запасной путь — общая связка ключей); ESign добавляет права из профиля сертификата. Виджет «Мой виджет» (`KoshelekDesign`) выбирает слот через AppIntent; быстрый виджет `KoshelekQuick` остался.
- Android: `core/WidgetConfig.kt`, `core/WidgetSnapshot.kt` (те же правила и тексты), `widget/WidgetRender.kt` (рисует в картинку — и виджет, и предпросмотр), `widget/WidgetStore.kt` (дизайны, провайдеры Small/Medium/Large, окно выбора слота), `ui/WidgetBuilder.kt`. Обновление — по изменению данных с паузой 1 с и раз в 30 минут.
- Правила расчёта и подписи блоков менять **одновременно** в `WidgetSnapshot.swift` и `WidgetSnapshot.kt`; раскладку — в `WidgetRenderer.swift` и `WidgetRender.kt`.
- Тест `WidgetTest` рисует виджеты в `build/screens/widgets`.

## Пожелания владельца
- Приложение только про деньги, не «приложение для жизни».
- Очень удобный голосовой ввод.
- Синхронизация с Obsidian: отчёты и перенос данных из приложения в Obsidian (не сделано).

## Коммиты
- Сообщения коммитов — на русском, коротко о том, что изменилось для пользователя.
- Работаем прямо в `main` (каждый пуш = новая сборка обеих платформ).

## Напарник (питомец)
- Каталог питомцев и их тексты генерируются из `tools/companions/spec.py` скриптом `tools/companions/gen_code.py` в `Koshelek/CompanionCatalog.swift` и `core/CompanionCatalog.kt` — руками не править, править spec.py и запускать скрипт.
- Картинки: `tools/companions/install_assets.py`; звуки синтезируются `make_sounds.py` (в `Koshelek/Sounds` и `res/raw`).
- Опыт, уровень, настроение и угощения выводятся из операций (`CompanionEngine.swift` ↔ `core/CompanionEngine.kt`, правила одинаковые, счёт с 27.10.2026). Выбранный питомец и число угощений хранятся только на устройстве, в синхронизацию не попадают.
