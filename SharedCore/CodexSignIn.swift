import Foundation

#if canImport(Encx)
import Encx
#endif

/// Drives the ChatGPT device-authorization login.
///
/// The device flow is the right shape for a phone: OpenAI hands out a short code,
/// the player approves it in a browser, and the app polls. There is no redirect
/// URI to register and no local callback listener to run.
@MainActor
@Observable
final class CodexSignInModel {
    enum Phase: Equatable {
        case idle
        case requesting
        case awaitingApproval(userCode: String, verifyURL: URL?)
        case signedIn
        case failed(String)
    }

    /// How long to wait for the player to approve the code.
    static let approvalTimeoutSeconds: Int64 = 900

    private(set) var phase: Phase = .idle

    #if canImport(Encx)
    private var login: EncxmobileCodexDeviceLogin?
    #endif
    private var waitTask: Task<Void, Never>?

    var isBusy: Bool {
        switch phase {
        case .requesting, .awaitingApproval: return true
        case .idle, .signedIn, .failed: return false
        }
    }

    var userCode: String? {
        if case .awaitingApproval(let code, _) = phase { return code }
        return nil
    }

    var verifyURL: URL? {
        if case .awaitingApproval(_, let url) = phase { return url }
        return nil
    }

    /// Requests a device code and then waits for the player to approve it.
    func start() {
        guard !isBusy else { return }
        phase = .requesting

        #if canImport(Encx)
        // gomobile exports this as a C function, so the NSError** stays explicit
        // instead of being imported as a throwing call.
        var error: NSError?
        guard let login = EncxmobileStartCodexDeviceLogin(&error) else {
            phase = .failed(error?.localizedDescription ?? "Не удалось начать вход в ChatGPT.")
            return
        }
        self.login = login
        phase = .awaitingApproval(
            userCode: login.userCode(),
            verifyURL: URL(string: login.verifyURL())
        )
        awaitApproval(login)
        #else
        phase = .failed(AgentSessionError.bindingsUnavailable.localizedDescription)
        #endif
    }

    /// Aborts a login that is waiting for approval.
    func cancel() {
        #if canImport(Encx)
        login?.cancel()
        #endif
        waitTask?.cancel()
        waitTask = nil
        if isBusy {
            phase = .idle
        }
    }

    /// Forgets the stored ChatGPT credential.
    func signOut() {
        cancel()
        AgentCredentialsStore.deleteCodexCredential()
        phase = .idle
    }

    #if canImport(Encx)
    private func awaitApproval(_ login: EncxmobileCodexDeviceLogin) {
        waitTask?.cancel()
        waitTask = Task { [weak self] in
            // Wait blocks while polling, so it has to stay off the main actor.
            let result: Result<String, Swift.Error> = await Task.detached(priority: .userInitiated) {
                do {
                    var error: NSError?
                    // The player has to switch to a browser, sign in and type a
                    // code, so the wait is generous.
                    let credentialJSON = login.wait(Self.approvalTimeoutSeconds, error: &error)
                    if let error { throw error }
                    return .success(credentialJSON)
                } catch {
                    return .failure(error)
                }
            }.value

            // Store the credential before considering cancellation: the player
            // approved in the browser, and throwing that away because the screen
            // closed would look like the login simply did nothing.
            var storeError: Swift.Error?
            if case .success(let credentialJSON) = result, !credentialJSON.isEmpty {
                do {
                    try AgentCredentialsStore.save(codexCredential: credentialJSON)
                } catch {
                    storeError = error
                }
            }

            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success:
                self.phase = storeError.map { .failed($0.localizedDescription) } ?? .signedIn
            case .failure(let error):
                self.phase = .failed(error.localizedDescription)
            }
            self.waitTask = nil
        }
    }
    #endif
}
