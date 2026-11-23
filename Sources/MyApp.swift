import SwiftUI
import SwiftData
import AppKit

@main
struct MyApp: App {

@StateObject private var timerService: TimerService
private let hotKeyService: HotKeyService

init() {
    let timer = TimerService()

    _timerService = StateObject(
        wrappedValue: timer
    )

    hotKeyService = HotKeyService(
        timerService: timer
    )
}

var body: some Scene {

    WindowGroup {
        ContentView(
            timerService: timerService
        )
        .frame(
            minWidth: 900,
            minHeight: 600
        )
        .task {
            hotKeyService.start()
        }
    }
    .modelContainer(
        AppContainer.shared
    )

    MenuBarExtra {

        MenuBarView(
            timerService: timerService
        )
        .modelContainer(
            AppContainer.shared
        )

    } label: {

        MenuBarTimerLabel(
            timerService: timerService
        )
    }
    .menuBarExtraStyle(.menu)
}

}

// MARK: - Menu Bar Timer Label

struct MenuBarTimerLabel: View {

@ObservedObject var timerService: TimerService

@ObservedObject
private var settings = AppSettings.shared

var body: some View {

    HStack(spacing: 4) {

        Image(
            systemName:
                timerService.isRunning
                ? "timer"
                : timerService.startDate != nil
                ? "pause.circle"
                : "clock"
        )

        if settings.showMenuBarTimer {
            Text(
                formattedTime(
                    timerService.elapsedTime
                )
            )
            .monospacedDigit()
        }
    }
}

private func formattedTime(
    _ time: TimeInterval
) -> String {

    let totalSeconds = Int(time)

    let hours =
        totalSeconds / 3600

    let minutes =
        (totalSeconds % 3600) / 60

    let seconds =
        totalSeconds % 60

    return String(
        format: "%02d:%02d:%02d",
        hours,
        minutes,
        seconds
    )
}

}

// MARK: - Menu Bar View

struct MenuBarView: View {

@ObservedObject var timerService: TimerService

@Environment(\.modelContext)
private var modelContext

@Query(sort: \WorkTask.name)
private var tasks: [WorkTask]

@AppStorage("selectedTaskID")
private var selectedTaskIDString = ""

private var selectedTask: WorkTask? {

    guard !selectedTaskIDString.isEmpty else {
        return nil
    }

    return tasks.first {
        String(
            describing: $0.persistentModelID
        ) == selectedTaskIDString
    }
}

private var activeTask: WorkTask? {

    guard !timerService.activeTaskID.isEmpty else {
        return nil
    }

    return tasks.first {
        String(
            describing: $0.persistentModelID
        ) == timerService.activeTaskID
    }
}

private var currentTask: WorkTask? {
    activeTask ?? selectedTask
}

private var currentCost: Double {

    guard let task = currentTask else {
        return 0
    }

    return timerService.elapsedTime
        / 3600
        * task.hourlyRate
}

var body: some View {

    VStack(
        alignment: .leading,
        spacing: 10
    ) {

        statusView

        timerView

        if let task = currentTask {
            taskView(
                task: task
            )
        }

        Divider()

        taskPicker

        Divider()

        controls

        Divider()

        footer
    }
    .padding(10)
    .frame(width: 300)
}

// MARK: Status

private var statusView: some View {

    HStack {

        Circle()
            .fill(
                timerService.isRunning
                ? Color.green
                : timerService.startDate != nil
                ? Color.orange
                : Color.secondary
            )
            .frame(
                width: 8,
                height: 8
            )

        Text(statusText)
            .font(.headline)

        Spacer()
    }
}

private var statusText: String {

    if timerService.isRunning {
        return "Таймер запущен"
    }

    if timerService.startDate != nil {
        return "Пауза"
    }

    return "Таймер остановлен"
}

// MARK: Timer

private var timerView: some View {

    Text(
        formattedTime(
            timerService.elapsedTime
        )
    )
    .font(
        .system(
            size: 32,
            weight: .medium,
            design: .monospaced
        )
    )
    .frame(
        maxWidth: .infinity,
        alignment: .leading
    )
}

// MARK: Current Task

private func taskView(
    task: WorkTask
) -> some View {

    VStack(
        alignment: .leading,
        spacing: 3
    ) {

        Text(task.name)
            .font(
                .body.weight(.medium)
            )
            .lineLimit(2)

        if let client = task.client {

            Text(client.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        HStack {

            Text(
                task.hourlyRate.formatted(
                    .currency(
                        code: "RUB"
                    )
                )
            )

            Text("•")

            Text(
                currentCost.formatted(
                    .currency(
                        code: "RUB"
                    )
                )
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: Task Picker

private var taskPicker: some View {

    Menu {

        if tasks.isEmpty {

            Text("Нет задач")

        } else {

            ForEach(tasks) { task in

                Button {

                    selectTask(task)

                } label: {

                    HStack {

                        Text(task.name)

                        if isSelected(task) {

                            Image(
                                systemName:
                                    "checkmark"
                            )
                        }
                    }
                }
                .disabled(
                    timerService.startDate != nil
                )
            }
        }

    } label: {

        Label(
            selectedTask?.name
                ?? "Выбрать задачу",
            systemImage: "checklist"
        )
        .lineLimit(1)
    }
}

private func selectTask(
    _ task: WorkTask
) {

    guard timerService.startDate == nil else {
        return
    }

    selectedTaskIDString =
        String(
            describing:
                task.persistentModelID
        )
}

private func isSelected(
    _ task: WorkTask
) -> Bool {

    String(
        describing:
            task.persistentModelID
    ) == selectedTaskIDString
}

// MARK: Controls

private var controls: some View {

    VStack(spacing: 6) {

        Button {

            toggleTimer()

        } label: {

            Label(
                timerService.isRunning
                ? "Пауза"
                : timerService.startDate != nil
                ? "Продолжить"
                : "Старт",
                systemImage:
                    timerService.isRunning
                    ? "pause.fill"
                    : "play.fill"
            )
            .frame(
                maxWidth: .infinity
            )
        }
        .buttonStyle(
            .borderedProminent
        )
        .disabled(
            currentTask == nil
        )

        if timerService.startDate != nil {

            Button {

                stopAndSave()

            } label: {

                Label(
                    "Стоп и сохранить",
                    systemImage:
                        "stop.fill"
                )
                .frame(
                    maxWidth: .infinity
                )
            }

            Button {

                timerService.cancelSession()

            } label: {

                Label(
                    "Отменить",
                    systemImage:
                        "xmark.circle"
                )
                .frame(
                    maxWidth: .infinity
                )
            }
        }
    }
}

private func toggleTimer() {

    if timerService.isRunning {

        timerService.pause()
        return
    }

    if timerService.startDate != nil {

        guard
            !timerService.activeTaskID.isEmpty
        else {
            return
        }

        timerService.start(
            taskID:
                timerService.activeTaskID
        )

        return
    }

    guard let task = selectedTask else {

        NSSound.beep()
        return
    }

    timerService.start(
        taskID:
            String(
                describing:
                    task.persistentModelID
            )
    )
}

// MARK: Save

private func stopAndSave() {

    guard let result = timerService.stop()
    else {
        return
    }

    guard let task = tasks.first(
        where: {
            String(
                describing:
                    $0.persistentModelID
            ) == result.taskID
        }
    ) else {
        return
    }

    let entry = TimeEntry(
        startDate: result.startDate,
        endDate: result.endDate,
        taskName: task.name,
        clientName:
            task.client?.name ?? "",
        hourlyRate:
            task.hourlyRate
    )

    entry.task = task

    modelContext.insert(entry)

    do {

        try modelContext.save()

    } catch {

        print(
            "Ошибка сохранения TimeEntry: \(error)"
        )
    }

    selectedTaskIDString =
        result.taskID
}

// MARK: Footer

private var footer: some View {

    VStack(
        alignment: .leading,
        spacing: 6
    ) {

        Text(
            "Space  Старт / пауза"
        )
        .font(.caption2)
        .foregroundStyle(.secondary)

        Button {

            openMainWindow()

        } label: {

            Label(
                "Открыть Time Tracker",
                systemImage:
                    "macwindow"
            )
        }

        Button {

            NSApp.terminate(nil)

        } label: {

            Label(
                "Выйти",
                systemImage:
                    "power"
            )
        }
    }
}

private func openMainWindow() {

    NSApp.activate(
        ignoringOtherApps: true
    )

    if let window =
        NSApp.windows.first
    {

        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: Formatting

private func formattedTime(
    _ time: TimeInterval
) -> String {

    let totalSeconds =
        Int(time)

    let hours =
        totalSeconds / 3600

    let minutes =
        (totalSeconds % 3600) / 60

    let seconds =
        totalSeconds % 60

    return String(
        format:
            "%02d:%02d:%02d",
        hours,
        minutes,
        seconds
    )
}

}
