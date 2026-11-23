import Foundation
import AppKit

@MainActor
final class HotKeyService {

private weak var timerService: TimerService?

private var globalMonitor: Any?
private var localMonitor: Any?

init(timerService: TimerService) {
    self.timerService = timerService
}

func start() {
    guard
        globalMonitor == nil,
        localMonitor == nil
    else {
        return
    }

    globalMonitor =
        NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in

            guard
                event.keyCode == 49,
                event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .isEmpty
            else {
                return
            }

            Task { @MainActor [weak self] in
                self?.toggleTimer()
            }
        }

    localMonitor =
        NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in

            guard
                event.keyCode == 49,
                event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .isEmpty
            else {
                return event
            }

            if Self.isTextInputFocused() {
                return event
            }

            Task { @MainActor [weak self] in
                self?.toggleTimer()
            }

            return nil
        }
}

func stop() {
    if let globalMonitor {
        NSEvent.removeMonitor(globalMonitor)
    }

    if let localMonitor {
        NSEvent.removeMonitor(localMonitor)
    }

    globalMonitor = nil
    localMonitor = nil
}

private func toggleTimer() {
    guard let timerService else {
        return
    }

    let selectedTaskID =
        UserDefaults.standard.string(
            forKey: "selectedTaskID"
        ) ?? ""

    // Никакой выбранной задачи нет.
    // Старый ID из UserDefaults тоже не должен
    // внезапно оживать и запускать таймер.
    guard !selectedTaskID.isEmpty else {
        NSSound.beep()
        return
    }

    // Таймер запущен.
    // Пауза разрешена только для выбранной задачи.
    if timerService.isRunning {
        guard timerService.activeTaskID == selectedTaskID else {
            NSSound.beep()
            return
        }

        timerService.pause()
        return
    }

    // Таймер находится на паузе.
    // Продолжаем только ту задачу, которая сейчас выбрана.
    if timerService.startDate != nil {
        guard timerService.activeTaskID == selectedTaskID else {
            NSSound.beep()
            return
        }

        timerService.start(
            taskID: selectedTaskID
        )

        return
    }

    // Таймер полностью остановлен.
    // Запускаем текущую выбранную задачу.
    timerService.start(
        taskID: selectedTaskID
    )
}

private static func isTextInputFocused() -> Bool {
    guard
        let firstResponder =
            NSApp.keyWindow?.firstResponder
    else {
        return false
    }

    return firstResponder is NSTextView
        || firstResponder is NSTextField
        || firstResponder is NSSearchField
}

}
