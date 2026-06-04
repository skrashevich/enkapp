# enkapp

[![iOS unsigned IPA](https://github.com/skrashevich/enkapp/actions/workflows/ios-unsigned-ipa.yml/badge.svg)](https://github.com/skrashevich/enkapp/actions/workflows/ios-unsigned-ipa.yml)
[![Download nightly IPA](https://img.shields.io/badge/nightly.link-download%20IPA-0A84FF)](https://nightly.link/skrashevich/enkapp/workflows/ios-unsigned-ipa/main/encx-cli-unsigned-ipa)
[![License](https://img.shields.io/github/license/skrashevich/enkapp)](LICENSE)

Нативное iOS-приложение для [Encounter](https://en.cx): очередь кодов, уровни, Live Activity, уведомления.

Клиент API — [`Encx.xcframework`](https://github.com/skrashevich/encx-cli) (gomobile-обёртка над пакетом `encx` из репозитория [encx-cli](https://github.com/skrashevich/encx-cli)).

## Скачать

[Последний билд (unsigned IPA)](https://nightly.link/skrashevich/enkapp/workflows/ios-unsigned-ipa/main/encx-cli-unsigned-ipa)

Учти: скачивание через `nightly.link` может не открываться или работать криво без "специальных сетевых сервисов".

## Как установить на iPhone

Самый простой путь сейчас: скачать `unsigned IPA` и установить его через sideloading. Публичного TestFlight пока нет, а всех в `Internal Testers` Apple добавлять не даёт без лишнего цирка.

1. Скачай архив по ссылке выше и распакуй его. Внутри будет файл `.ipa`.
2. Установи любой sideloading-инструмент:
   - `AltStore` / `SideStore` для установки прямо на устройство
   - `Sideloadly` если удобнее ставить с компьютера
3. Импортируй `.ipa` в выбранный инструмент и подпиши его своим Apple ID.
4. После установки на iPhone, если iOS попросит доверить профиль разработчика:
   `Настройки` -> `Основные` -> `VPN и управление устройством` -> доверить профиль.
5. Запусти `enkapp`.

Что важно:

- На бесплатном Apple ID такая установка обычно живёт 7 дней, потом приложение надо переустановить или переподписать.
- Название artifact и bundle местами ещё могут содержать старое имя `encx-cli`; это нормально.
- Если ссылка на `nightly.link` не открывается, виноват обычно не iPhone, а сеть между тобой и `nightly.link`.

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
```

Открыть в Xcode: `encx-cli.xcodeproj`, схема `encx-cli`.

`Encx.xcframework` лежит в `encx-cli/Frameworks/`. После `make framework` он синхронизируется из `encx-cli/build/gomobile/`.

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
