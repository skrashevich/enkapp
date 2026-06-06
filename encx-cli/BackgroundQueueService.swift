import BackgroundTasks
import UIKit

@MainActor
final class BackgroundQueueService {
    static let shared = BackgroundQueueService()
    static let taskIdentifier = "com.svk-team.encx-cli.queue-flush"

    var flushHandler: (() async -> Bool)?

    private init() {}

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await self.handleProcessingTask(processingTask)
            }
        }
    }

    func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Retries until the queue is empty or iOS background time runs out.
    func runAggressiveFlushLoop(
        interval: TimeInterval = 0.35,
        operation: @escaping () async -> Bool
    ) {
        Task { @MainActor in
            var taskID = beginBackgroundTask()
            guard taskID != .invalid else { return }

            var rounds = 0
            while taskID != .invalid {
                let done = await operation()
                if done { break }

                rounds += 1
                try? await Task.sleep(for: .seconds(interval))

                if rounds.isMultiple(of: 12) {
                    let nextID = beginBackgroundTask()
                    if nextID != .invalid {
                        endBackgroundTask(taskID)
                        taskID = nextID
                    }
                }
            }

            endBackgroundTask(taskID)
            scheduleProcessing()
        }
    }

    private func handleProcessingTask(_ task: BGProcessingTask) async {
        scheduleProcessing()

        let work = Task { @MainActor in
            await self.runAggressiveFlushLoopInternal(maxSeconds: 25) {
                await self.flushHandler?() ?? true
            }
        }

        task.expirationHandler = {
            work.cancel()
        }

        await work.value
        task.setTaskCompleted(success: !work.isCancelled)
    }

    private func runAggressiveFlushLoopInternal(
        maxSeconds: TimeInterval,
        interval: TimeInterval = 0.35,
        operation: () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(maxSeconds)
        while Date() < deadline {
            if await operation() { return }
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    private func beginBackgroundTask() -> UIBackgroundTaskIdentifier {
        let token = BackgroundTaskToken()
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "queue-flush-loop") {
            Task { @MainActor in
                token.end()
            }
        }
        token.taskID = taskID
        return taskID
    }

    private func endBackgroundTask(_ taskID: UIBackgroundTaskIdentifier) {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
    }
}

@MainActor
private final class BackgroundTaskToken {
    var taskID: UIBackgroundTaskIdentifier = .invalid

    func end() {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
        taskID = .invalid
    }
}
