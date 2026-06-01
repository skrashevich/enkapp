# enkapp

Нативное iOS-приложение для [Encounter](https://en.cx): очередь кодов, уровни, Live Activity, уведомления.

Клиент API — [`Encx.xcframework`](https://github.com/skrashevich/encx-cli) (gomobile-обёртка над пакетом `encx` из репозитория [encx-cli](https://github.com/skrashevich/encx-cli)).

## Скачать

[Последний билд (unsigned IPA)](https://nightly.link/skrashevich/enkapp/workflows/iOS%20unsigned%20IPA/main/encx-cli-unsigned-ipa.zip)

Учти: скачивание через `nightly.link` может не открываться или работать криво без "специальных сетевых сервисов".

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
