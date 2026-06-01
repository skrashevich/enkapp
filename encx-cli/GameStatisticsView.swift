import SwiftUI

struct GameStatisticsView: View {
    @Bindable var model: EncounterViewModel
    let gameID: Int64

    @State private var cookiesData: Data?
    @State private var reloadID = UUID()
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var pageURL: URL {
        model.statisticsPageURL(for: gameID)
    }

    var body: some View {
        ZStack {
            if let cookiesData {
                EncounterAuthenticatedWebView(
                    url: pageURL,
                    cookiesData: cookiesData,
                    reloadID: reloadID,
                    isLoading: $isLoading,
                    errorMessage: $errorMessage
                )
            }

            if isLoading {
                ProgressView("Загрузка статистики…")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            if let errorMessage {
                if cookiesData == nil {
                    statisticsError(errorMessage)
                } else {
                    VStack {
                        Spacer()
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                            .padding()
                    }
                }
            }
        }
        .background(Color.black)
        .navigationTitle("Статистика")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading && cookiesData == nil)
            }
        }
        .task {
            await reload()
        }
    }

    private func statisticsError(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(GameTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Повторить") {
                Task { await reload() }
            }
            .buttonStyle(.borderedProminent)
            .tint(GameTheme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil

        do {
            cookiesData = try await model.exportSessionCookies()
            reloadID = UUID()
        } catch {
            cookiesData = nil
            errorMessage = EncounterClient.userFacingDescription(for: error)
            isLoading = false
        }
    }
}
