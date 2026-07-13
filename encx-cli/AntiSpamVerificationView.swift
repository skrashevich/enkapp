import SwiftUI

struct AntiSpamVerificationView: View {
    @Bindable var model: EncounterViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var webError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let url = model.antiSpamVerificationURL {
                    EncounterAuthenticatedWebView(
                        url: url,
                        cookiesData: model.sessionCookiesData ?? Data(),
                        isLoading: $isLoading,
                        errorMessage: $webError
                    )
                } else {
                    ContentUnavailableView(
                        "Нет адреса проверки",
                        systemImage: "exclamationmark.shield"
                    )
                }
            }
            .navigationTitle("Антиспам")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        finish()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        model.dismissAntiSpamVerification()
                        dismiss()
                    }
                }
            }
        }
    }

    private func finish() {
        model.completeAntiSpamVerification()
        dismiss()
        Task {
            await model.refreshGames()
        }
    }
}
