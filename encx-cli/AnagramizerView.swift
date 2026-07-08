import SwiftUI
import UIKit

struct AnagramizerView: View {
    @State private var model: AnagramizerViewModel
    @State private var copiedWord: String?

    init(engine: AnagramEngine? = nil) {
        _model = State(initialValue: AnagramizerViewModel(engine: engine))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                modeSection
                inputSection
                optionsSection
                resultsSection
                attributionSection
            }
            .padding()
        }
        .background(GameTheme.background)
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .navigationTitle("Анаграмайзер")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(GameTheme.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            model.loadDictionaryIfNeeded()
        }
    }

    // MARK: - Режим

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Режим поиска")
            Picker("Режим", selection: $model.mode) {
                Text("Шаблон").tag(AnagramMode.pattern)
                Text("Из букв").tag(AnagramMode.anagram)
                Text("Подслова").tag(AnagramMode.subword)
                Text("Комбо").tag(AnagramMode.combined)
            }
            .pickerStyle(.segmented)
            .onChange(of: model.mode) { _, _ in
                model.scheduleSearch()
            }
        }
        .sectionPanel()
    }

    // MARK: - Ввод

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Ввод")

            if showsPatternField {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Шаблон, напр. «к_т»", text: $model.pattern)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(GameTheme.text)
                        .padding(12)
                        .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
                        .onChange(of: model.pattern) { _, _ in
                            model.scheduleSearch()
                        }
                    Text("Джокер на одну позицию: «_», «.», «?» или «*».")
                        .font(.caption)
                        .foregroundStyle(GameTheme.muted)
                }
            }

            if showsLettersField {
                TextField("Буквы, напр. «автомобиль»", text: $model.letters)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(GameTheme.text)
                    .padding(12)
                    .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
                    .onChange(of: model.letters) { _, _ in
                        model.scheduleSearch()
                    }
            }

            Button {
                model.searchNow()
            } label: {
                Label("Найти", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(GameTheme.accent)
            .disabled(model.dictionaryState != .ready)
        }
        .sectionPanel()
    }

    private var showsPatternField: Bool {
        model.mode == .pattern || model.mode == .combined
    }

    private var showsLettersField: Bool {
        model.mode == .anagram || model.mode == .subword || model.mode == .combined
    }

    // MARK: - Опции

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Опции")

            DashboardSettingsRow(
                title: "ё = е",
                subtitle: "Не различать «ё» и «е» при поиске.",
                systemImage: "textformat.abc",
                tint: GameTheme.bonusTitle
            ) {
                Toggle("ё = е", isOn: $model.foldYo)
                    .labelsHidden()
                    .tint(GameTheme.accent)
                    .onChange(of: model.foldYo) { _, _ in
                        model.scheduleSearch()
                    }
            }

            HStack(spacing: 10) {
                lengthField(title: "Мин. длина", value: $model.minLength)
                lengthField(title: "Макс. длина", value: $model.maxLength)
            }

            Picker("Сортировка", selection: $model.sort) {
                Text("Длиннее сначала").tag(AnagramSort.byLengthDesc)
                Text("Короче сначала").tag(AnagramSort.byLengthAsc)
                Text("По алфавиту").tag(AnagramSort.alphabetical)
            }
            .pickerStyle(.menu)
            .tint(GameTheme.accent)
            .onChange(of: model.sort) { _, _ in
                model.scheduleSearch()
            }
        }
        .sectionPanel()
    }

    private func lengthField(title: String, value: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(GameTheme.muted)
            TextField("—", text: Binding(
                get: { value.wrappedValue.map(String.init) ?? "" },
                set: { newValue in
                    value.wrappedValue = Int(newValue.filter(\.isNumber))
                    model.scheduleSearch()
                }
            ))
            .keyboardType(.numberPad)
            .foregroundStyle(GameTheme.text)
            .padding(10)
            .background(GameTheme.inputBackground, in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Результаты

    @ViewBuilder
    private var resultsSection: some View {
        switch model.dictionaryState {
        case .loading:
            statusPanel(systemImage: "hourglass", text: "Загрузка словаря…", showsProgress: true)
        case .error(let message):
            statusPanel(systemImage: "exclamationmark.triangle", text: message, tint: .orange)
        case .ready:
            readyResultsSection
        }
    }

    @ViewBuilder
    private var readyResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Результаты")
                Spacer()
                if model.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let errorMessage = model.searchErrorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else if model.hasSearched {
                Text("Найдено: \(model.totalCount)")
                    .font(.caption)
                    .foregroundStyle(GameTheme.muted)
            }

            if model.hasSearched, model.words.isEmpty, model.searchErrorMessage == nil {
                Text("Ничего не найдено")
                    .font(.subheadline)
                    .foregroundStyle(GameTheme.muted)
            } else {
                ForEach(model.words, id: \.self) { word in
                    wordRow(word)
                }

                if model.hasMore {
                    Button {
                        model.loadMore()
                    } label: {
                        Text("Показать ещё")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(GameTheme.accent)
                    .disabled(model.isSearching)
                }
            }
        }
        .sectionPanel()
    }

    private func wordRow(_ word: String) -> some View {
        Button {
            copyWord(word)
        } label: {
            HStack {
                Text(word)
                    .font(.body.monospaced())
                    .foregroundStyle(GameTheme.text)
                Spacer(minLength: 0)
                Image(systemName: copiedWord == word ? "checkmark" : "doc.on.doc")
                    .font(.subheadline)
                    .foregroundStyle(copiedWord == word ? GameTheme.accent : GameTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(GameTheme.panel, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: copiedWord)
    }

    private func statusPanel(
        systemImage: String,
        text: String,
        tint: Color = GameTheme.muted,
        showsProgress: Bool = false
    ) -> some View {
        VStack(spacing: 10) {
            if showsProgress {
                ProgressView()
            } else {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(tint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .sectionPanel()
    }

    // MARK: - Атрибуция словаря

    private var attributionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Словарь: содержит данные OpenCorpora (© OpenCorpora contributors, CC BY-SA) и словарь © 1997–2008 Alexander I. Lebedev (лицензия BSD, модифицированная версия).")
                .font(.caption)
                .foregroundStyle(GameTheme.muted)

            NavigationLink {
                AnagramizerLicenseView()
            } label: {
                Text("Полный текст лицензий")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GameTheme.accent)
            }
        }
        .sectionPanel()
    }

    private func copyWord(_ word: String) {
        UIPasteboard.general.string = word
        copiedWord = word
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedWord == word {
                copiedWord = nil
            }
        }
    }
}

#Preview {
    NavigationStack {
        AnagramizerView(engine: MockAnagramEngine())
    }
}
