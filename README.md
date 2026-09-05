# enkapp

[![iOS unsigned IPA](https://github.com/skrashevich/enkapp/actions/workflows/ios-unsigned-ipa.yml/badge.svg)](https://github.com/skrashevich/enkapp/actions/workflows/ios-unsigned-ipa.yml)
[![TestFlight](https://img.shields.io/badge/TestFlight-Установить-0A84FF?logo=apple)](https://testflight.apple.com/join/QVfQ5Hzf)
[![Download nightly IPA](https://img.shields.io/badge/dawnl.ink-download%20IPA-0A84FF)](https://dawnl.ink/skrashevich/enkapp/workflows/ios-unsigned-ipa/main/encx-cli-unsigned-ipa)
[![License](https://img.shields.io/github/license/skrashevich/enkapp)](LICENSE)

Нативное iOS-приложение для [Encounter](https://en.cx): очередь кодов, уровни, Live Activity, уведомления.

Клиент API — [`Encx.xcframework`](https://github.com/skrashevich/encx-cli) (gomobile-обёртка над пакетом `encx` из репозитория [encx-cli](https://github.com/skrashevich/encx-cli)).

## Скачать и установить

### TestFlight (рекомендуется)

[![Download TestFlight](https://img.shields.io/badge/TestFlight-Установить-0A84FF?logo=apple)](https://testflight.apple.com/join/QVfQ5Hzf)

Самый простой способ: открой ссылку с iPhone, и TestFlight установит приложение.

### Sideloading (без TestFlight)

[Последний билд (unsigned IPA)](https://dawnl.ink/skrashevich/enkapp/workflows/ios-unsigned-ipa/main/encx-cli-unsigned-ipa)

1. Скачай архив по ссылке выше и распакуй его. Внутри будет файл `.ipa`.
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
- Если ссылка на `dawnl.ink` не открывается, виноват обычно не iPhone, а сеть между тобой и `dawnl.ink`.

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

- **Ключ API** для OpenAI, Anthropic или OpenRouter. Можно указать свой endpoint, но он обязан
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
