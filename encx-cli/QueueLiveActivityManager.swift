import ActivityKit
import Foundation

@MainActor
final class QueueLiveActivityManager {
    private var activity: Activity<QueueActivityAttributes>?

    func sync(state: QueueActivityAttributes.ContentState?, gameTitle: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard let state else {
            await end()
            return
        }

        let content = ActivityContent(state: state, staleDate: nil)

        if let activity {
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
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }
}
