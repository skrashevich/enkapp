import Foundation

#if !ANALYTICS_DISABLED && canImport(MetricKit)
import MetricKit
#endif

enum TelemetryService {
    private static var configured = false
    private static let sessionID = UUID().uuidString
    #if !ANALYTICS_DISABLED && canImport(MetricKit)
    private static let metricKitSubscriber = MetricKitTelemetrySubscriber()
    #endif

    static var isCompiledIn: Bool {
        #if ANALYTICS_DISABLED
        return false
        #else
        return true
        #endif
    }

    static func configure(settings: DomainSettings) {
        guard isCompiledIn else { return }
        guard settings.analyticsEnabled else { return }
        configured = true
        #if !ANALYTICS_DISABLED && canImport(MetricKit)
        metricKitSubscriber.start()
        #endif
    }

    static func updateEnabled(_ enabled: Bool) {
        guard isCompiledIn else { return }
        if enabled, !configured {
            configure(settings: EncounterSessionStore.loadSettings())
        }
        track(enabled ? "analytics_enabled" : "analytics_disabled")
    }

    static func track(_ name: String, properties: [String: Any] = [:]) {
        #if !ANALYTICS_DISABLED
        guard shouldSend else { return }
        guard let appKey = TelemetryConfiguration.aptabaseAppKey,
              let host = TelemetryConfiguration.aptabaseHost,
              let url = URL(string: host)?.appending(path: "api/v0/events") else {
            return
        }

        let safeProperties = sanitized(properties)
        let payload: [[String: Any]] = [
            [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "eventName": name,
                "systemProps": systemProperties(),
                "props": safeProperties,
            ],
        ]

        sendJSON(payload, to: url, headers: ["App-Key": appKey])
        #endif
    }

    static func capture(_ error: Error, context: [String: Any] = [:]) {
        #if !ANALYTICS_DISABLED
        guard shouldSend else { return }
        let safeContext = sanitized(context)

        var properties = safeContext
        properties["error_type"] = String(describing: type(of: error))
        track("error", properties: properties)

        guard let dsn = TelemetryConfiguration.glitchtipDSN,
              let endpoint = SentryStoreEndpoint(dsn: dsn) else {
            return
        }

        let payload: [String: Any] = [
            "event_id": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "platform": "cocoa",
            "level": "error",
            "logger": "enkapp",
            "environment": TelemetryConfiguration.environment,
            "release": TelemetryConfiguration.releaseName,
            "exception": [
                "values": [
                    [
                        "type": String(describing: type(of: error)),
                        "value": String(describing: error),
                    ],
                ],
            ],
            "tags": [
                "app_version": TelemetryConfiguration.appVersion,
                "build": TelemetryConfiguration.buildNumber,
            ],
            "extra": safeContext,
        ]
        sendJSON(payload, to: endpoint.url, headers: endpoint.headers)
        #endif
    }

    static func captureMetricKitDiagnostic(_ data: Data) {
        #if !ANALYTICS_DISABLED
        guard shouldSend else { return }
        let payload = String(data: data, encoding: .utf8) ?? ""
        track("metrickit_diagnostic", properties: [
            "payload_bytes": data.count,
        ])

        guard let dsn = TelemetryConfiguration.glitchtipDSN,
              let endpoint = SentryStoreEndpoint(dsn: dsn) else {
            return
        }

        let payloadPrefix = String(payload.prefix(60_000))
        let event: [String: Any] = [
            "event_id": UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "platform": "cocoa",
            "level": "fatal",
            "logger": "enkapp.metrickit",
            "environment": TelemetryConfiguration.environment,
            "release": TelemetryConfiguration.releaseName,
            "message": "MetricKit diagnostic payload",
            "tags": [
                "app_version": TelemetryConfiguration.appVersion,
                "build": TelemetryConfiguration.buildNumber,
                "source": "metrickit",
            ],
            "extra": [
                "payload": payloadPrefix,
                "payload_bytes": data.count,
                "truncated": payloadPrefix.count < payload.count,
            ],
        ]
        sendJSON(event, to: endpoint.url, headers: endpoint.headers)
        #endif
    }

    private static var shouldSend: Bool {
        guard isCompiledIn, configured else { return false }
        return EncounterSessionStore.loadSettings().analyticsEnabled
    }

    #if !ANALYTICS_DISABLED
    private static func sendJSON(_ value: Any, to url: URL, headers: [String: String]) {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        URLSession.shared.dataTask(with: request).resume()
    }

    private static func systemProperties() -> [String: Any] {
        [
            "isDebug": _isDebugAssertConfiguration(),
            "locale": Locale.current.identifier,
            "osName": "iOS",
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "sdkVersion": "enkapp-http",
            "sessionId": sessionID,
            "appVersion": TelemetryConfiguration.appVersion,
            "buildNumber": TelemetryConfiguration.buildNumber,
        ]
    }
    #endif

    private static func sanitized(_ properties: [String: Any]) -> [String: Any] {
        var sanitized: [String: Any] = [
            "app_version": TelemetryConfiguration.appVersion,
            "build": TelemetryConfiguration.buildNumber,
            "ios_version": ProcessInfo.processInfo.operatingSystemVersionString,
        ]

        for (key, value) in properties {
            guard !sensitiveKeys.contains(key.lowercased()) else { continue }
            switch value {
            case let value as String:
                sanitized[key] = String(value.prefix(120))
            case let value as Int:
                sanitized[key] = value
            case let value as Int64:
                sanitized[key] = value
            case let value as Double:
                sanitized[key] = value
            case let value as Bool:
                sanitized[key] = value
            default:
                sanitized[key] = String(describing: value).prefix(120).description
            }
        }

        return sanitized
    }

    private static let sensitiveKeys: Set<String> = [
        "code",
        "answer",
        "password",
        "login",
        "team",
        "team_name",
        "html",
        "cookie",
        "cookies",
        "token",
    ]
}

private enum TelemetryConfiguration {
    static var aptabaseAppKey: String? {
        nonEmptyInfoString("ENKAPPAptabaseAppKey")
    }

    static var aptabaseHost: String? {
        nonEmptyInfoString("ENKAPPAptabaseHost")
    }

    static var glitchtipDSN: String? {
        nonEmptyInfoString("ENKAPPGlitchtipDSN")
    }

    static var environment: String {
        nonEmptyInfoString("ENKAPPTelemetryEnvironment") ?? "production"
    }

    static var appVersion: String {
        nonEmptyInfoString("CFBundleShortVersionString") ?? "unknown"
    }

    static var buildNumber: String {
        nonEmptyInfoString("CFBundleVersion") ?? "unknown"
    }

    static var releaseName: String {
        "\(Bundle.main.bundleIdentifier ?? "enkapp")@\(appVersion)+\(buildNumber)"
    }

    private static func nonEmptyInfoString(_ key: String) -> String? {
        guard let value = Bundle.main.infoDictionary?[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("$(") { return nil }
        return trimmed
    }
}

private struct SentryStoreEndpoint {
    let url: URL
    let headers: [String: String]

    init?(dsn: String) {
        guard let dsnURL = URL(string: dsn),
              let host = dsnURL.host,
              let publicKey = dsnURL.user,
              let scheme = dsnURL.scheme,
              let projectID = dsnURL.pathComponents.last else {
            return nil
        }

        let basePath = dsnURL.pathComponents.dropFirst().dropLast().joined(separator: "/")
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = dsnURL.port
        components.path = "/"
        if !basePath.isEmpty {
            components.path += "\(basePath)/"
        }
        components.path += "api/\(projectID)/store/"
        components.queryItems = [
            URLQueryItem(name: "sentry_key", value: publicKey),
            URLQueryItem(name: "sentry_version", value: "7"),
        ]

        guard let url = components.url else { return nil }
        self.url = url
        self.headers = [
            "X-Sentry-Auth": "Sentry sentry_version=7, sentry_key=\(publicKey), sentry_client=enkapp-http/1.0",
        ]
    }
}

#if !ANALYTICS_DISABLED && canImport(MetricKit)
private final class MetricKitTelemetrySubscriber: NSObject, MXMetricManagerSubscriber {
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            TelemetryService.captureMetricKitDiagnostic(payload.jsonRepresentation())
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        // Product analytics are sent explicitly; metric payloads are intentionally ignored for now.
    }
}
#endif
