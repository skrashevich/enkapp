# Раздел «Инструменты»: удобный вход и расширяемый хаб утилит

Дата: 2026-07-08
Статус: утверждён к реализации

## Проблема

Анаграмайзер сейчас спрятан глубоко: `Настройки → «Инструменты» → NavigationLink → AnagramizerView`
(`encx-cli/SettingsView.swift:315`). Игроку он нужен прямо во время разгадывания задания, а
путь до него — три экрана и потеря игрового контекста. Впереди появятся и другие утилиты,
упрощающие жизнь игроку (декодер Цезаря и т. п.), поэтому нужен не просто перенос одной кнопки,
а расширяемый контейнер.

## Цели

- Быстрый доступ к утилитам прямо во время игры, без потери контекста задания.
- Доступ к утилитам и вне активной игры.
- Контейнер, в который добавление новой утилиты — минимальное изменение (один case + одна View).

## Решения (по итогам брейншторма)

1. Утилиты чаще всего нужны **прямо во время игры** → основной вход на игровом экране.
2. Открытие — **шторка (sheet)**: игровой экран остаётся под ней, свайп вниз быстро возвращает к заданию.
3. Доступ вне игры — **через иконку в тулбаре** (не только в бою). Пункт в настройках убираем.

## Архитектура

### Реестр инструментов — единый источник правды

Новый файл `encx-cli/PlayerTools.swift`:

```swift
enum PlayerTool: String, CaseIterable, Identifiable {
    case anagramizer
    // case caesar   ← добавить новый инструмент здесь

    var id: String { rawValue }
    var title: String { … }
    var subtitle: String { … }
    var systemImage: String { … }
    var tint: Color { … }

    @ViewBuilder var destination: some View { … }   // AnagramizerView() и т.д.
}
```

Добавление декодера Цезаря = один `case` + его View. Навигацию, шапку и тулбар трогать не нужно.

Отвергнутая альтернатива: хардкодить строки прямо в хабе — при 3–5 утилитах разъедется дублирование.

### Хаб-шторка `ToolsHubView`

- Живёт в том же файле `PlayerTools.swift`.
- Внутри — собственный `NavigationStack`.
- Корень: список `ForEach(PlayerTool.allCases)`, строки в стиле существующего `DashboardSettingsRow`
  (иконка + заголовок + подзаголовок + шеврон).
- Тап по строке — push внутрь шторки в `tool.destination`, с кнопкой «Назад».
- Заголовок навигации «Инструменты», кнопка «Готово»/свайп вниз закрывает шторку.
- Даже пока инструмент один — показываем список (паттерн готов к росту).

### Точки входа (обе открывают один флаг)

Флаг состояния: `EncounterViewModel.showToolsSheet: Bool = false`.

- **Игровой экран** — в `LevelPlayView.gameHeader` (`encx-cli/LevelPlayView.swift:433`) добавляется
  action-кнопка «Инструменты» (иконка `wrench.and.screwdriver`) в ряд с «Обновить / Статистика / Коды».
  Использует стиль `headerAction(...)`. По тапу: `model.showToolsSheet = true`.
- **Тулбар** — в `ContentView.screenContent` toolbar (`topBarTrailing`, `encx-cli/ContentView.swift:57`)
  добавляется иконка «Инструменты» рядом с командой/шестерёнкой. Тулбар виден на экранах,
  где `selectedScreen != .game`, что покрывает доступ вне игры. По тапу: `model.showToolsSheet = true`.

### Presentation

`.sheet(isPresented: $model.showToolsSheet) { ToolsHubView() }` вешается в `ContentView.mainContent`
(`encx-cli/ContentView.swift:25`), рядом с существующим `.sheet` для `AntiSpamVerificationView`.
Так шторка открывается поверх любого экрана, включая `.game`, где тулбар скрыт.

## Затронутые файлы

- **new** `encx-cli/PlayerTools.swift` — `enum PlayerTool` + `ToolsHubView`.
- `encx-cli/EncounterViewModel.swift` — `+ var showToolsSheet = false`.
- `encx-cli/ContentView.swift` — `.sheet(...)` в `mainContent` + иконка в тулбаре.
- `encx-cli/LevelPlayView.swift` — кнопка «Инструменты» в `gameHeader`.
- `encx-cli/SettingsView.swift` — удалить `toolsSection` и её вызов.

## Обработка ошибок / крайние случаи

- Инструменты (анаграмайзер) работают офлайн и не зависят от активной игры — открытие шторки безопасно
  на любом экране, даже без выбранной игры.
- Существующий screenshot-режим (`--screenshot-anagramizer`, `encx_cliApp.swift:26`) не затрагивается:
  он открывает `AnagramizerView` напрямую, минуя хаб.

## Проверка

- UI-тестов в проекте нет.
- Верификация: сборка `xcodebuild` (без ошибок/варнингов по затронутым файлам) + ручная/скриншотная
  проверка, что оба входа открывают шторку и анаграмайзер работает из неё.
```
