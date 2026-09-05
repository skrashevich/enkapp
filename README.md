# enkapp

[![iOS tagged release](https://github.com/skrashevich/enkapp/actions/workflows/ios-unsigned-ipa.yml/badge.svg)](https://github.com/skrashevich/enkapp/actions/workflows/ios-unsigned-ipa.yml)
[![TestFlight](https://img.shields.io/badge/TestFlight-Установить-0A84FF?logo=apple)](https://testflight.apple.com/join/QVfQ5Hzf)
[![License](https://img.shields.io/github/license/skrashevich/enkapp)](LICENSE)

Нативное iOS-приложение для [Encounter](https://en.cx): очередь кодов, уровни, Live Activity, уведомления.

Клиент API — [`Encx.xcframework`](https://github.com/skrashevich/encx-cli) (gomobile-обёртка над пакетом `encx` из репозитория [encx-cli](https://github.com/skrashevich/encx-cli)).

## Скачать и установить

### TestFlight (рекомендуется)

[![Download TestFlight](https://img.shields.io/badge/TestFlight-Установить-0A84FF?logo=apple)](https://testflight.apple.com/join/QVfQ5Hzf)

Самый простой способ: открой ссылку с iPhone, и TestFlight установит приложение.

### Sideloading (без TestFlight)

[Сборки по тегам (unsigned IPA)](https://github.com/skrashevich/enkapp/actions/workflows/ios-unsigned-ipa.yml)

1. Открой успешный запуск по тегу, скачай artifact `encx-cli-unsigned-ipa` (нужен вход в GitHub) и распакуй его. Внутри будет файл `.ipa`.
2. Установи любой sideloading-инструмент:
   - `AltStore` / `SideStore` для установки прямо на устройство
   - `Sideloadly` если удобнее ставить с компьютера
3. Импортируй `.ipa` в выбранный инструмент и подпиши своим Apple ID.
4. После установки на iPhone, если iOS попросит доверить профиль разработчика:
   `Настройки` -> `Основные` -> `VPN и управление устройством` -> доверить профиль.
5. Запусти `enkapp`.

Что важно:

- На бесплатном Apple ID такая установка обычно живёт 7 дней, потом приложение надо переустановить или переподписать.
- Название artifact и bundle местами ещё могут содержать старое имя `encx-cli`; это нормально.

## Требования

- macOS с Xcode 16+
- Для пересборки `Encx.xcframework`: Go 1.26+ и доступ в сеть — исходники [encx-cli](https://github.com/skrashevich/encx-cli) подтягиваются автоматически

## Сборка

```sh
# Пересобрать Encx.xcframework (опционально, если менялся API).
# Без переменных берёт последний коммит upstream в build/encx-cli-upstream/
make framework

# Собрать из локального чекаута encx-cli вместо upstream
make framework ENCX_CLI_ROOT=/path/to/encx-cli

# Зафиксировать версию upstream
make framework ENCX_CLI_REF=v0.12.0

# Unsigned / signed IPA (см. make help)
make unsigned-ipa
make signed-ipa DEVELOPMENT_TEAM=XXXXXXXXXX EXPORT_METHOD=release-testing

# Скриншоты для App Store / README
make screenshots
```

Открыть в Xcode: `encx-cli.xcodeproj`, схема `encx-cli`.

`Encx.xcframework` лежит в `encx-cli/Frameworks/`. После `make framework` он синхронизируется из `encx-cli/build/gomobile/`.

## Релизы в CI и внутренний TestFlight

Workflow `iOS tagged release` запускается только при push тега формата `v<major>.<minor>.<patch>.<build>`. Он сохраняет
unsigned IPA как artifact на 14 дней и отдельно собирает подписанный Release-архив
из того же коммита с готовым `Encx.xcframework`, затем загружает его в App Store Connect
как **TestFlight Internal Only**. Push веток, PR и ручной запуск релиз не собирают.
Например, `v0.2.25.71` задаёт `MARKETING_VERSION=0.2.25` и `CURRENT_PROJECT_VERSION=71`
для приложения, widget и App Clip, включая unsigned IPA. Xcode сохраняет эти значения
при загрузке. Повторная загрузка уже использованной версии и номера сборки Apple
не допускается: для следующей сборки увеличь последнюю часть тега. Неправильный формат
тега отклоняется до сборки и использования секретов.

В Settings → Secrets and variables → Actions добавь repository secrets:

| Secret | Значение |
|--------|----------|
| `APP_STORE_CONNECT_KEY_ID` | ID командного API-ключа App Store Connect |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID команды |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Полное содержимое файла `.p8`, включая BEGIN/END |
| `IOS_CERTIFICATES_P12_BASE64` | Base64 от `.p12` с сертификатами Apple Development и Apple Distribution и их приватными ключами |
| `IOS_CERTIFICATES_PASSWORD` | Непустой пароль этого `.p12` |

Ключу нужны права на загрузку сборок и Certificates, Identifiers & Profiles
(командный ключ `enkapp-github-actions` с ролью Developer). Сертификаты должны принадлежать команде `ZLQX2C6SX2`.
Provisioning profiles для приложения, widget и App Clip Xcode получает автоматически.
Приложение с bundle ID `com.svk-team.encx-cli` должно уже существовать в App Store Connect.
В TestFlight создай внутреннюю группу, добавь тестеров и включи **Enable automatic distribution**:
после обработки Apple сборка будет доступна этой группе. Требуемые Apple сведения
об экспортном соответствии должны быть заполнены. Такие сборки недоступны по публичной
ссылке внешнего TestFlight и не предназначены для публикации в App Store.
См. [инструкцию Apple по внутренним тестерам](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).

```sh
git tag v0.2.25.71
git push origin v0.2.25.71
```

Workflow скриншотов продолжает работать на ветках, PR и вручную; теги его не запускают.

## Скриншоты

<p>
  <img src="https://skrashevich.github.io/enkapp/screenshots/iphone/01-games.png" alt="Список игр" width="260">
  <img src="https://skrashevich.github.io/enkapp/screenshots/iphone/02-game.png" alt="Экран игры" width="260">
  <img src="https://skrashevich.github.io/enkapp/screenshots/iphone/03-settings.png" alt="Настройки" width="260">
  <img src="https://skrashevich.github.io/enkapp/screenshots/iphone/04-team.png" alt="Управление командой" width="260">
  <img src="https://skrashevich.github.io/enkapp/screenshots/iphone/05-tools.png" alt="Инструменты" width="260">
  <img src="https://skrashevich.github.io/enkapp/screenshots/iphone/06-anagramizer.png" alt="Анаграмайзер" width="260">
  <img src="https://skrashevich.github.io/enkapp/screenshots/iphone/07-onboarding.png" alt="Первоначальная настройка" width="260">
</p>

`make screenshots` собирает Debug-приложение для iOS Simulator, запускает его с `--screenshots` и сохраняет PNG в `build/screenshots/`.
В CI это делает workflow `iOS screenshots`; результат доступен как artifact `enkapp-ios-screenshots`
## Структура

| Путь | Назначение |
|------|------------|
| `encx-cli/` | Исходники приложения (SwiftUI) |
| `encx-cli-widget/` | Live Activity (Widget Extension) |
| `Shared/` | `ActivityAttributes`, общие с виджетом |
| `export/ExportOptions.plist` | Шаблон для `xcodebuild -exportArchive` |

## Ассистент в игре

В приложение встроен ИИ-ассистент на [PicoClaw](https://github.com/sipeed/picoclaw): агент
целиком живёт внутри `Encx.xcframework` и работает через тот же движок Encounter, что и само
приложение, — под вашей учётной записью.

Включается в «Настройки → Ассистент»: провайдер, модель и учётные данные. После включения кнопка ✨
появляется и в тулбаре списка игр, и в шапке экрана игры.

Аутентификация — на выбор:

- **Ключ API** для OpenAI, Anthropic или [Polza.AI](https://polza.ai/?referral=6GWIX1KxUI) —
  российского агрегатора с сотнями моделей по одному ключу. Можно указать свой endpoint, но он обязан
  обслуживать `/chat/completions`: агент ходит именно туда, поэтому шлюз, реализующий только
  Responses API, ответит 404.
- **Подписка ChatGPT** — вход по коду устройства: приложение показывает код, вы подтверждаете его
  на странице OpenAI. Ключ при этом не нужен.

**Учётные данные хранятся в Keychain устройства**, а не в UserDefaults; запросы уходят напрямую
выбранному провайдеру, так что данные игры покидают устройство вместе с ними.

Доступ к движку задаётся политикой:

| Политика | Что может ассистент |
|----------|---------------------|
| Чтение | Видит игру, уровень, секторы, бонусы, подсказки, лог кодов и статистику. Ничего не отправляет. |
| С подтверждением (по умолчанию) | То же плюс отправка кодов и бонусов, штрафные подсказки, заявка на игру — каждое такое действие подтверждается вами в диалоге. |
| Без подтверждения | Ассистент действует сам. Ошибочный код тратит время и может включить блокировку ответов, а штрафная подсказка необратимо добавляет команде штрафное время. |

В режиме с подтверждением вызов доходит до движка только после явного «Разрешить».

Внутри одного ответа ассистент кеширует прочитанное из движка, чтобы не дёргать
его повторно одним и тем же запросом. Кеш сбрасывается в начале каждого вопроса и
после любого действия, меняющего игру, — на новый вопрос ассистент всегда смотрит
свежие данные.

Ассистент видит картинки заданий: уровень отдаёт список изображений, а инструмент
просмотра скачивает их под вашей сессией и передаёт модели целиком. Ограничения —
8 МБ на файл и только адреса в пределах домена игры.

В чате есть диктовка: распознавание речи выполняется **только на устройстве**
(`requiresOnDeviceRecognition`), звук никуда не отправляется. Если локальная модель
для языка устройства недоступна, кнопка микрофона не показывается. С аппаратной
клавиатурой Enter отправляет сообщение, Shift+Enter переносит строку.

Инструменты движка, политики доступа и MCP-сервер для внешнего PicoClaw описаны в
[`docs/agent-tools.md`](https://github.com/skrashevich/encx-cli/blob/main/docs/agent-tools.md)
репозитория encx-cli.

## Связь с encx-cli

| Репозиторий | Содержимое |
|-------------|------------|
| [encx-cli](https://github.com/skrashevich/encx-cli) | Go-клиент, CLI `encli`, `mobile/encxmobile`, сборка xcframework |
| **enkapp** (этот репозиторий) | Только iOS UI и Xcode-проект |

Изменения API Encounter сначала вносятся в `encx-cli` (`encx` + `mobile/encxmobile`), затем `make framework` и обновление Swift в этом репозитории.

## Лицензия

Apache License 2.0 — см. [LICENSE](LICENSE).
