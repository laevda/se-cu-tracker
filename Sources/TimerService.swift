import Foundation
import Combine

@MainActor
final class TimerService: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var startDate: Date?
    @Published private(set) var activeTaskID = ""

    private var timerTask: Task<Void, Never>?

    private var segmentStartDate: Date?

    private var accumulatedTime: TimeInterval = 0

    private let startDateKey =
        "timer.startDate"

    private let segmentStartDateKey =
        "timer.segmentStartDate"

    private let accumulatedTimeKey =
        "timer.accumulatedTime"

    private let isRunningKey =
        "timer.isRunning"

    private let activeTaskIDKey =
        "timer.activeTaskID"

    struct StopResult {

        let startDate: Date
        let endDate: Date
        let duration: TimeInterval
        let taskID: String
    }

    init() {

        restoreState()
    }

    deinit {

        timerTask?.cancel()
    }

    func start(
        taskID: String
    ) {

        guard
            !taskID.isEmpty
        else {
            return
        }

        guard
            !isRunning
        else {
            return
        }

        activeTaskID =
            taskID

        if startDate == nil {

            let now =
                Date()

            startDate =
                now

            accumulatedTime =
                0
        }

        segmentStartDate =
            Date()

        elapsedTime =
            accumulatedTime

        isRunning =
            true

        saveState()

        startTimerLoop()
    }

    func pause() {

        guard
            isRunning
        else {
            return
        }

        accumulateCurrentSegment()

        isRunning =
            false

        segmentStartDate =
            nil

        timerTask?.cancel()

        timerTask =
            nil

        saveState()
    }

    @discardableResult
    func stop()
        -> StopResult? {

        guard
            startDate != nil,
            !activeTaskID.isEmpty
        else {
            return nil
        }

        if isRunning {

            accumulateCurrentSegment()
        }

        let duration =
            max(
                0,
                accumulatedTime
            )

        let endDate =
            Date()

        let logicalStartDate =
            endDate.addingTimeInterval(
                -duration
            )

        let result =
            StopResult(
                startDate:
                    logicalStartDate,

                endDate:
                    endDate,

                duration:
                    duration,

                taskID:
                    activeTaskID
            )

        timerTask?.cancel()

        timerTask =
            nil

        clearState()

        isRunning =
            false

        startDate =
            nil

        segmentStartDate =
            nil

        accumulatedTime =
            0

        elapsedTime =
            0

        activeTaskID =
            ""

        return result
    }

    func cancelSession() {

        timerTask?.cancel()

        timerTask =
            nil

        clearState()

        isRunning =
            false

        startDate =
            nil

        segmentStartDate =
            nil

        accumulatedTime =
            0

        elapsedTime =
            0

        activeTaskID =
            ""
    }

    func reset() {

        cancelSession()
    }

    private func startTimerLoop() {

        timerTask?.cancel()

        timerTask =
            Task { [weak self] in

                while
                    !Task.isCancelled {

                    try? await Task.sleep(
                        nanoseconds:
                            1_000_000_000
                    )

                    guard
                        !Task.isCancelled
                    else {
                        break
                    }

                    guard
                        let self
                    else {
                        break
                    }

                    self.updateElapsedTime()

                    self.saveState()
                }
            }
    }

    private func accumulateCurrentSegment() {

        guard
            let segmentStartDate
        else {
            return
        }

        let segmentDuration =
            max(
                0,
                Date().timeIntervalSince(
                    segmentStartDate
                )
            )

        accumulatedTime +=
            segmentDuration

        elapsedTime =
            accumulatedTime
    }

    private func updateElapsedTime() {

        guard
            isRunning,
            let segmentStartDate
        else {
            elapsedTime =
                accumulatedTime

            return
        }

        let currentSegment =
            max(
                0,
                Date().timeIntervalSince(
                    segmentStartDate
                )
            )

        elapsedTime =
            accumulatedTime +
            currentSegment
    }

    private func saveState() {

        let defaults =
            UserDefaults.standard

        if let startDate {

            defaults.set(
                startDate,
                forKey:
                    startDateKey
            )

        } else {

            defaults.removeObject(
                forKey:
                    startDateKey
            )
        }

        if let segmentStartDate {

            defaults.set(
                segmentStartDate,
                forKey:
                    segmentStartDateKey
            )

        } else {

            defaults.removeObject(
                forKey:
                    segmentStartDateKey
            )
        }

        defaults.set(
            accumulatedTime,
            forKey:
                accumulatedTimeKey
        )

        defaults.set(
            isRunning,
            forKey:
                isRunningKey
        )

        defaults.set(
            activeTaskID,
            forKey:
                activeTaskIDKey
        )
    }

    private func restoreState() {

        let defaults =
            UserDefaults.standard

        let savedAccumulated =
            defaults.double(
                forKey:
                    accumulatedTimeKey
            )

        let savedRunning =
            defaults.bool(
                forKey:
                    isRunningKey
            )

        let savedStartDate =
            defaults.object(
                forKey:
                    startDateKey
            ) as? Date

        let savedSegmentStartDate =
            defaults.object(
                forKey:
                    segmentStartDateKey
            ) as? Date

        let savedTaskID =
            defaults.string(
                forKey:
                    activeTaskIDKey
            ) ?? ""

        accumulatedTime =
            max(
                0,
                savedAccumulated
            )

        elapsedTime =
            accumulatedTime

        startDate =
            savedStartDate

        segmentStartDate =
            savedSegmentStartDate

        activeTaskID =
            savedTaskID

        isRunning =
            savedRunning &&
            savedStartDate != nil &&
            savedSegmentStartDate != nil &&
            !savedTaskID.isEmpty

        if isRunning {

            updateElapsedTime()

            startTimerLoop()
        }
    }

    private func clearState() {

        let defaults =
            UserDefaults.standard

        defaults.removeObject(
            forKey:
                startDateKey
        )

        defaults.removeObject(
            forKey:
                segmentStartDateKey
        )

        defaults.removeObject(
            forKey:
                accumulatedTimeKey
        )

        defaults.removeObject(
            forKey:
                isRunningKey
        )

        defaults.removeObject(
            forKey:
                activeTaskIDKey
        )
    }
}
