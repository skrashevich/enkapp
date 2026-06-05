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
- Для пересборки `Encx.xcframework`: Go 1.26+, checkout [encx-cli](https://github.com/skrashevich/encx-cli) и `ENCX_CLI_ROOT` (по умолчанию `../encx-cli`, если клон лежит рядом под другим именем — укажите путь явно)

## Сборка

```sh
# Пересобрать Encx.xcframework из encx-cli (опционально, если менялся API)
make framework

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
  <img src="https://skrashevich.github.io/enkapp/screenshots/01-games.png" alt="Список игр" width="260">
  <img src="https://skrashevich.github.io/enkapp/screenshots/02-game.png" alt="Экран игры" width="260">
  <img src="https://skrashevich.github.io/enkapp/screenshots/03-settings.png" alt="Настройки" width="260">
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

## Связь с encx-cli

| Репозиторий | Содержимое |
|-------------|------------|
| [encx-cli](https://github.com/skrashevich/encx-cli) | Go-клиент, CLI `encli`, `mobile/encxmobile`, сборка xcframework |
| **enkapp** (этот репозиторий) | Только iOS UI и Xcode-проект |

Изменения API Encounter сначала вносятся в `encx-cli` (`encx` + `mobile/encxmobile`), затем `make framework` и обновление Swift в этом репозитории.

## Лицензия

Apache License 2.0 — см. [LICENSE](LICENSE).
