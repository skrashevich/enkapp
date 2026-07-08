# Раздел «Инструменты»: удобный вход и расширяемый хаб утилит — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Вынести анаграмайзер из глубины настроек в удобный расширяемый раздел «Инструменты», доступный шторкой из шапки игрового экрана и из тулбара.

**Architecture:** Единый реестр `enum PlayerTool` (источник правды для списка утилит) + шторка-хаб `ToolsHubView` со своим `NavigationStack`. Обе точки входа (кнопка в шапке игры и иконка в тулбаре) поднимают один флаг `EncounterViewModel.showToolsSheet`, по которому `ContentView` показывает `.sheet`.

**Tech Stack:** Swift, SwiftUI, Observation (`@Observable`/`@Bindable`), Xcode-проект `encx-cli.xcodeproj` (схема `encx-cli`).

## Global Constraints

- Язык UI и коммитов — русский; технические идентификаторы — латиницей.
- Тёмная тема через `GameTheme` (`SharedCore/GameTheme.swift`): фон `.background`, панели `.panel`/`.inputBackground`, текст `.text`, приглушённый `.muted`, акцент `.accent`, бирюзовый `.bonusTitle`.
- UI-тестов в проекте нет — цикл проверки каждой задачи = успешная сборка `xcodebuild` без новых ошибок/варнингов по затронутым файлам.
- Экранная модель: `EncounterViewModel` — `@Observable`-класс; во вьюхах используется как `@Bindable var model`.
- Существующий стиль строк — `DashboardSettingsRow(title:subtitle:systemImage:tint:) { accessory }` (`encx-cli/SharedComponents.swift:264`).
- Существующий стиль action-иконок в шапке игры — `headerAction(_ title:systemImage:)` (`encx-cli/LevelPlayView.swift:497`).
- `AnagramizerView()` открывается дефолтным init'ом без аргументов (`encx-cli/AnagramizerView.swift:8`).

**Команда сборки (общая для всех задач):**

```bash
xcodebuild -project encx-cli.xcodeproj -scheme encx-cli \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath build/PlanDerivedData build 2>&1 | tail -20
```
Ожидается: `** BUILD SUCCEEDED **`. Если симулятор `iPhone 16` недоступен — подставить любой доступный из `xcrun simctl list devices available`.

---

### Task 1: Реестр `PlayerTool` + шторка `ToolsHubView`

**Files:**
- Create: `encx-cli/PlayerTools.swift`
- Reference: `encx-cli/SharedComponents.swift:264` (`DashboardSettingsRow`), `encx-cli/AnagramizerView.swift:8` (`AnagramizerView()`), `SharedCore/GameTheme.swift`

**Interfaces:**
- Consumes: `DashboardSettingsRow`, `AnagramizerView`, `GameTheme` — уже существуют.
- Produces:
  - `enum PlayerTool: String, CaseIterable, Identifiable` со свойствами `id: String`, `title: String`, `subtitle: String`, `systemImage: String`, `tint: Color`, и `@ViewBuilder var destination: some View`.
  - `struct ToolsHubView: View` — самодостаточная шторка (свой `NavigationStack`, закрытие через `@Environment(\.dismiss)`), init без аргументов.

- [ ] **Step 1: Создать файл `encx-cli/PlayerTools.swift` целиком**

```swift
import SwiftUI

/// Единый реестр игровых утилит. Добавление новой утилиты =
/// один `case` + ветка в вычисляемых свойствах + View в `destination`.
enum PlayerTool: String, CaseIterable, Identifiable {
    case anagramizer
    // Следующие утилиты добавлять здесь, напр.: case caesar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anagramizer: return "Анаграмайзер"
        }
    }

    var subtitle: String {
        switch self {
        case .anagramizer: return "Поиск слов по шаблону, буквам или их сочетанию."
        }
    }

    var systemImage: String {
        switch self {
        case .anagramizer: return "textformat.abc.dottedunderline"
        }
    }

    var tint: Color {
        switch self {
        case .anagramizer: return GameTheme.bonusTitle
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .anagramizer: AnagramizerView()
        }
    }
}

/// Шторка со списком утилит. Открывается поверх любого экрана.
struct ToolsHubView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(PlayerTool.allCases) { tool in
                        NavigationLink {
                            tool.destination
                        } label: {
                            DashboardSettingsRow(
                                title: tool.title,
                                subtitle: tool.subtitle,
                                systemImage: tool.systemImage,
                                tint: tool.tint
                            ) {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(GameTheme.muted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(GameTheme.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("Инструменты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .tint(GameTheme.text)
                }
            }
            .toolbarBackground(GameTheme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ToolsHubView()
}
```

- [ ] **Step 2: Добавить файл в таргет `encx-cli`**

Если сборка на шаге 3 не видит `ToolsHubView`/`PlayerTool`, значит файл не попал в таргет. Открыть `encx-cli.xcodeproj`, убедиться, что `PlayerTools.swift` включён в Target Membership → `encx-cli` (обычно Xcode добавляет автоматически при создании через IDE; при ручном создании файла нужно проверить `project.pbxproj`).

- [ ] **Step 3: Сборка**

Run: команда сборки из Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add encx-cli/PlayerTools.swift encx-cli.xcodeproj/project.pbxproj
git commit -m "feat(tools): реестр PlayerTool и шторка-хаб ToolsHubView"
```

---

### Task 2: Флаг состояния, `.sheet` и вход из тулбара в `ContentView`

**Files:**
- Modify: `encx-cli/EncounterViewModel.swift` (рядом с `showAntiSpamVerification`)
- Modify: `encx-cli/ContentView.swift:31` (блок `.sheet` в `mainContent`), `encx-cli/ContentView.swift:57-83` (toolbar `topBarTrailing`)

**Interfaces:**
- Consumes: `ToolsHubView` (Task 1).
- Produces: `EncounterViewModel.showToolsSheet: Bool` (по умолчанию `false`) — используется в Task 3.

- [ ] **Step 1: Добавить флаг в `EncounterViewModel`**

Найти существующее `var showAntiSpamVerification` в `encx-cli/EncounterViewModel.swift` и добавить рядом:

```swift
    var showToolsSheet = false
```

(Если рядом нет `showAntiSpamVerification` — добавить строку в блок обычных `var`-свойств класса, не в `private`.)

- [ ] **Step 2: Добавить `.sheet` в `mainContent`**

В `encx-cli/ContentView.swift`, в `mainContent`, сразу после существующего блока:

```swift
            .sheet(isPresented: $model.showAntiSpamVerification) {
                AntiSpamVerificationView(model: model)
            }
```

добавить второй sheet:

```swift
            .sheet(isPresented: $model.showToolsSheet) {
                ToolsHubView()
            }
```

- [ ] **Step 3: Добавить иконку «Инструменты» в тулбар**

В `encx-cli/ContentView.swift`, внутри `ToolbarItem(placement: .topBarTrailing)` → `HStack(spacing: 16)`, между кнопкой команды и `NavigationLink { SettingsView(model: model) }`, вставить:

```swift
                        Button {
                            model.showToolsSheet = true
                        } label: {
                            Image(systemName: "wrench.and.screwdriver")
                        }
                        .tint(GameTheme.text)
                        .disabled(model.isBusy)
                        .accessibilityLabel("Инструменты")
```

- [ ] **Step 4: Сборка**

Run: команда сборки из Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add encx-cli/EncounterViewModel.swift encx-cli/ContentView.swift
git commit -m "feat(tools): вход в инструменты из тулбара и презентация шторки"
```

---

### Task 3: Вход из шапки игрового экрана (`LevelPlayView`)

**Files:**
- Modify: `encx-cli/LevelPlayView.swift:453-468` (`HStack(spacing: 18)` внутри `gameHeader`)

**Interfaces:**
- Consumes: `model.showToolsSheet` (Task 2), `headerAction(_:systemImage:)` (`encx-cli/LevelPlayView.swift:497`).
- Produces: —

- [ ] **Step 1: Добавить кнопку «Инструменты» в ряд действий шапки**

В `encx-cli/LevelPlayView.swift`, внутри `gameHeader`, в `HStack(spacing: 18)` (сейчас: «Обновить», «Статистика», «Коды»), добавить первым элементом (перед кнопкой «Обновить»):

```swift
                Button {
                    model.showToolsSheet = true
                } label: {
                    headerAction("Инструменты", systemImage: "wrench.and.screwdriver")
                }
                .disabled(model.isBusy)
```

- [ ] **Step 2: Сборка**

Run: команда сборки из Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add encx-cli/LevelPlayView.swift
git commit -m "feat(tools): кнопка «Инструменты» в шапке игрового экрана"
```

---

### Task 4: Удалить пункт «Инструменты» из настроек

**Files:**
- Modify: `encx-cli/SettingsView.swift:36` (вызов `toolsSection` в body), `encx-cli/SettingsView.swift:314` (определение `private var toolsSection`)

**Interfaces:**
- Consumes: —
- Produces: —

- [ ] **Step 1: Убрать вызов `toolsSection` из body**

В `encx-cli/SettingsView.swift`, в `LazyVStack` (строки 31–39), удалить строку:

```swift
                toolsSection
```

- [ ] **Step 2: Удалить определение `toolsSection`**

Удалить целиком блок `private var toolsSection: some View { … }` (начинается на `encx-cli/SettingsView.swift:314`, заканчивается `.sectionPanel()` + `}`). Это тот блок, что содержит `SectionTitle("Инструменты")`, `NavigationLink { AnagramizerView() }` и `DashboardSettingsRow(title: "Анаграмайзер", …)`.

- [ ] **Step 3: Проверить, что `AnagramizerView` больше не импортируется зря**

Никаких дополнительных импортов удалять не нужно (`AnagramizerView` в том же модуле). Убедиться, что в `SettingsView.swift` не осталось других ссылок на `toolsSection`:

Run: `grep -n "toolsSection" encx-cli/SettingsView.swift`
Expected: пустой вывод.

- [ ] **Step 4: Сборка**

Run: команда сборки из Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add encx-cli/SettingsView.swift
git commit -m "refactor(settings): убрать раздел «Инструменты» — переехал в хаб-шторку"
```

---

### Task 5: Финальная ручная/скриншотная проверка

**Files:** —

**Interfaces:** Consumes: всё выше.

- [ ] **Step 1: Запустить приложение в симуляторе и проверить сценарии**

1. Экран «Игры» → в тулбаре есть иконка гаечного ключа → тап → открывается шторка «Инструменты» со строкой «Анаграмайзер».
2. Тап по «Анаграмайзер» в шторке → открывается анаграмайзер (push внутри шторки, есть «Назад»).
3. Свайп шторки вниз / «Готово» → возврат на исходный экран.
4. На экране «Игра» (с активной игрой) → в шапке в ряду действий есть кнопка «Инструменты» → тап → та же шторка поверх игры; свайп вниз возвращает к заданию.
5. Настройки → раздела «Инструменты» больше нет.

- [ ] **Step 2: Убедиться, что screenshot-режим не сломан**

Run: `grep -n "screenshot-anagramizer" encx-cli/encx_cliApp.swift`
Expected: строка присутствует; `AnagramizerView(model: .screenshotModel())` открывается напрямую, минуя хаб (эту ветку не трогали).

- [ ] **Step 3: Финальная сборка «начисто»**

Run: команда сборки из Global Constraints (можно с предварительным `rm -rf build/PlanDerivedData`).
Expected: `** BUILD SUCCEEDED **`.

---

## Self-Review

**Spec coverage:**
- Реестр `PlayerTool` → Task 1. ✅
- Шторка `ToolsHubView` со своим `NavigationStack` и списком → Task 1. ✅
- Флаг `showToolsSheet` + `.sheet` в `ContentView` → Task 2. ✅
- Вход из тулбара (вне игры) → Task 2. ✅
- Вход из шапки игры (в бою) → Task 3. ✅
- Удаление пункта из настроек → Task 4. ✅
- Screenshot-режим не затронут → проверка в Task 5. ✅

**Placeholder scan:** плейсхолдеров нет — весь код приведён целиком.

**Type consistency:** `showToolsSheet` (Task 2) используется одинаково в Task 2/3; `PlayerTool`/`ToolsHubView` (Task 1) — в Task 2; `headerAction(_:systemImage:)` и `DashboardSettingsRow` совпадают с существующими сигнатурами.
