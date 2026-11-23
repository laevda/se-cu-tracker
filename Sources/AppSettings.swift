import Foundation
import Combine
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {

static let shared = AppSettings()

@Published var launchAtLogin: Bool {
    didSet {
        UserDefaults.standard.set(
            launchAtLogin,
            forKey: "launchAtLogin"
        )
        updateLaunchAtLogin()
    }
}

@Published var showMenuBarTimer: Bool {
    didSet {
        UserDefaults.standard.set(
            showMenuBarTimer,
            forKey: "showMenuBarTimer"
        )
    }
}

@Published var defaultHourlyRate: Double {
    didSet {
        UserDefaults.standard.set(
            defaultHourlyRate,
            forKey: "defaultHourlyRate"
        )
    }
}

private init() {

    let defaults = UserDefaults.standard

    launchAtLogin =
        defaults.bool(
            forKey: "launchAtLogin"
        )

    showMenuBarTimer =
        defaults.object(
            forKey: "showMenuBarTimer"
        ) as? Bool ?? true

    defaultHourlyRate =
        defaults.double(
            forKey: "defaultHourlyRate"
        )
}

private func updateLaunchAtLogin() {

    let service = SMAppService.mainApp

    do {

        if launchAtLogin {
            try service.register()
        } else {
            try service.unregister()
        }

    } catch {

        print(
            "Ошибка настройки запуска при входе: \(error)"
        )
    }
}

}
