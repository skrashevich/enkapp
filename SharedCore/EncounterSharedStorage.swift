import Foundation

enum EncounterSharedStorage {
    static let appGroupID = "group.com.svk-team.encx-cli"

    private static var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private static let storageDirectory: URL? = {
        guard !isRunningInPreview else { return nil }
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return nil
        }
        let directory = containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("EncounterSharedStorage", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }()

    static var isAvailable: Bool {
        storageDirectory != nil
    }

    static func data(forKey key: String) -> Data? {
        if let value = object(forKey: key) as? Data {
            return value
        }
        return UserDefaults.standard.data(forKey: key)
    }

    static func string(forKey key: String) -> String? {
        if let value = object(forKey: key) as? String {
            return value
        }
        return UserDefaults.standard.string(forKey: key)
    }

    static func object(forKey key: String) -> Any? {
        if let value = storedObject(forKey: key) {
            return value
        }
        return UserDefaults.standard.object(forKey: key)
    }

    static func set(_ value: Any?, forKey key: String) {
        if storageDirectory != nil {
            setStoredObject(value, forKey: key)
        } else {
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    static func removeObject(forKey key: String) {
        if let url = fileURL(forKey: key) {
            try? FileManager.default.removeItem(at: url)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func migrateFromStandard(keys: [String]) {
        guard storageDirectory != nil else { return }
        for key in keys {
            guard storedObject(forKey: key) == nil,
                  let value = UserDefaults.standard.object(forKey: key) else {
                continue
            }
            setStoredObject(value, forKey: key)
        }
    }

    private static func storedObject(forKey key: String) -> Any? {
        guard let url = fileURL(forKey: key),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
    }

    private static func setStoredObject(_ value: Any?, forKey key: String) {
        guard let value else {
            removeObject(forKey: key)
            return
        }
        guard PropertyListSerialization.propertyList(value, isValidFor: .binary),
              let url = fileURL(forKey: key),
              let data = try? PropertyListSerialization.data(
                fromPropertyList: value,
                format: .binary,
                options: 0
              ) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private static func fileURL(forKey key: String) -> URL? {
        guard let storageDirectory else { return nil }
        let fileName = Data(key.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return storageDirectory
            .appendingPathComponent(fileName)
            .appendingPathExtension("plist")
    }
}
