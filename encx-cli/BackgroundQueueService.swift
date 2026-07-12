import BackgroundTasks
import UIKit

@MainActor
final class BackgroundQueueService {
    static let shared = BackgroundQueueService()
    static let taskIdentifier = "com.svk-team.encx-cli.queue-flush"

    var flushHandler: (() async -> Bool)?
    private var aggressiveFlushTask: Task<Void, Never>?

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
        guard aggressiveFlushTask == nil else { return }

        let taskID = UIApplication.shared.beginBackgroundTask(withName: "queue-flush-loop") { [weak self] in
            Task { @MainActor in
                self?.aggressiveFlushTask?.cancel()
            }
        }
        guard taskID != .invalid else { return }

        aggressiveFlushTask = Task { @MainActor [weak self] in
            defer {
                UIApplication.shared.endBackgroundTask(taskID)
                self?.aggressiveFlushTask = nil
                self?.scheduleProcessing()
            }

            while !Task.isCancelled {
                let done = await operation()
                if done { break }
                try? await Task.sleep(for: .seconds(interval))
            }
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

}
