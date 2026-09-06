import CoreLocation
import Foundation

/// One-shot GPS reads for the assistant's `enc_device_location` tool.
///
/// CLLocationManager answers through a delegate, so the async read is bridged
/// with continuations. The Go side already bounds the wait and serialises
/// nothing — several requests may overlap — so every waiter is queued and they
/// all resolve from the same fix.
@MainActor
final class AgentLocationProvider: NSObject {
    enum LocationError: LocalizedError {
        case denied
        case servicesDisabled

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Доступ к геолокации запрещён. Игрок может включить его в Настройках iOS."
            case .servicesDisabled:
                return "Службы геолокации выключены на устройстве."
            }
        }
    }

    /// The fields of a fix that survive the hop off the CoreLocation thread.
    private struct Fix: Sendable {
        let latitude: Double
        let longitude: Double
        let horizontalAccuracy: Double
        let altitude: Double
        let verticalAccuracy: Double
        let timestamp: Date
    }

    private let manager = CLLocationManager()
    private var fixWaiters: [CheckedContinuation<Fix, Error>] = []
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Reads the current position and renders it as the JSON payload the agent
    /// session forwards to the model.
    func currentLocationJSON() async throws -> String {
        let fix = try await currentFix()

        var payload: [String: Any] = [
            "latitude": fix.latitude,
            "longitude": fix.longitude,
        ]
        if fix.horizontalAccuracy >= 0 {
            payload["accuracy_m"] = fix.horizontalAccuracy
        }
        // A non-positive vertical accuracy means the altitude is invalid.
        if fix.verticalAccuracy > 0 {
            payload["altitude_m"] = fix.altitude
        }
        payload["timestamp"] = ISO8601DateFormatter().string(from: fix.timestamp)

        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw LocationError.servicesDisabled
        }
        return json
    }

    private func currentFix() async throws -> Fix {
        // The prompt is raised at most once; afterwards the status is either
        // granted or denied. Each loop iteration needs a real authorization
        // change to resume, so this cannot spin.
        while manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationWaiters.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        }

        switch manager.authorizationStatus {
        case .denied:
            throw LocationError.denied
        case .restricted:
            throw LocationError.denied
        default:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            fixWaiters.append(continuation)
            manager.requestLocation()
        }
    }

    private func authorizationChanged() {
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func finishFix(_ result: Result<Fix, Error>) {
        let waiters = fixWaiters
        fixWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }
}

extension AgentLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationChanged()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = Fix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.altitude,
            verticalAccuracy: location.verticalAccuracy,
            timestamp: location.timestamp
        )
        Task { @MainActor in
            self.finishFix(.success(fix))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.finishFix(.failure(error))
        }
    }
}
