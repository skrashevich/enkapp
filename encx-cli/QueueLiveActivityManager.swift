import ActivityKit
import Foundation

@MainActor
final class QueueLiveActivityManager {
    private var activity: Activity<QueueActivityAttributes>?

    static var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func endAll() async {
        for activity in Activity<QueueActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func sync(state: QueueActivityAttributes.ContentState?, gameTitle: String) async {
        guard Self.areActivitiesEnabled else { return }

        guard let state else {
            await end()
            return
        }

        let content = ActivityContent(state: state, staleDate: nil)

        if let activity = currentActivity() {
            await activity.update(content)
            return
        }

        let attributes = QueueActivityAttributes(gameTitle: gameTitle)
        activity = try? Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }

    func end() async {
        await Self.endAll()
        self.activity = nil
    }

    private func currentActivity() -> Activity<QueueActivityAttributes>? {
        if let activity {
            return activity
        }

        activity = Activity<QueueActivityAttributes>.activities.first
        return activity
    }
}
