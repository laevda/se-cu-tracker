import SwiftUI
import AppKit

struct SettingsView: View {

@ObservedObject
private var settings = AppSettings.shared

var body: some View {

    Form {

        Section("Общие") {

            Toggle(
                "Показывать таймер в меню",
                isOn: $settings.showMenuBarTimer
            )

            Toggle(
                "Запускать приложение при входе в систему",
                isOn: $settings.launchAtLogin
            )
        }

        Section("Ставка") {

            HStack {

                Text("Ставка по умолчанию")

                Spacer()

                TextField(
                    "0",
                    value: $settings.defaultHourlyRate,
                    format: .number
                )
                .multilineTextAlignment(.trailing)
                .frame(width: 100)

                Text("₽/ч")
                    .foregroundStyle(.secondary)
            }
        }

        Section("Горячая клавиша") {

            HStack {

                Text("Старт / пауза")

                Spacer()

                Text("Space")
                    .font(
                        .system(
                            size: 13,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(.secondary)
            }

            Text(
                "Работает глобально, даже когда приложение находится в фоне."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("О приложении") {

            VStack(
                alignment: .leading,
                spacing: 8
            ) {

                Text("se:cu tracker")
                    .font(.headline)

                Text(
                    "Локальный трекер рабочего времени без сервера и подписок."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button {
                    openBoosty()
                } label: {
                    Label(
                        "Поддержать автора",
                        systemImage: "heart"
                    )
                }
                .buttonStyle(.bordered)
            }
        }
    }
    .formStyle(.grouped)
    .padding()
    .frame(
        minWidth: 500,
        minHeight: 420
    )
}

private func openBoosty() {

    guard
        let url = URL(
            string: "https://boosty.to/laevda"
        )
    else {
        return
    }

    NSWorkspace.shared.open(url)
}

}
