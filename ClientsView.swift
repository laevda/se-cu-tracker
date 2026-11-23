
import SwiftUI
import SwiftData
import AppKit

struct ClientsView: View {

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.modelContext)
    private var modelContext

    @Query(sort: \Client.name)
    private var clients: [Client]

    @State private var showingNewClient = false
    @State private var editingClient: Client?
    @State private var clientToDelete: Client?
    @State private var showingDeleteConfirmation = false

    var body: some View {

        VStack(spacing: 0) {

            header

            Divider()

            if clients.isEmpty {
                emptyState
            } else {
                clientList
            }
        }
        .frame(
            minWidth: 650,
            minHeight: 500
        )
        .sheet(isPresented: $showingNewClient) {

            ClientEditorView(
                title: "Новый клиент"
            )
        }
        .sheet(item: $editingClient) { client in

            ClientEditorView(
                title: "Редактировать клиента",
                client: client
            )
        }
        .confirmationDialog(
            "Удалить клиента?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {

            Button(
                "Удалить",
                role: .destructive
            ) {

                if let client = clientToDelete {
                    deleteClient(client)
                }
            }

            Button("Отмена", role: .cancel) {}

        } message: {

            if let client = clientToDelete {

                Text(
                    "Клиент «\(client.name)» и его задачи будут удалены."
                )

            } else {

                Text(
                    "Клиент и связанные задачи будут удалены."
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {

        HStack {

            VStack(alignment: .leading, spacing: 4) {

                Text("Клиенты")
                    .font(.title2)
                    .bold()

                Text("\(clients.count) клиентов")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showingNewClient = true
            } label: {

                Label(
                    "Новый клиент",
                    systemImage: "plus"
                )
            }
            .buttonStyle(.borderedProminent)

            Button("Готово") {
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
        .padding(20)
    }

    // MARK: - List

    private var clientList: some View {

        ScrollView {

            LazyVStack(spacing: 10) {

                ForEach(clients) { client in
                    clientRow(client)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Client Row

    private func clientRow(
        _ client: Client
    ) -> some View {

        let clientColor = ClientColorStore.shared.color(
            for: client
        )

        return HStack(spacing: 16) {

            ZStack {

                RoundedRectangle(cornerRadius: 10)
                    .fill(clientColor.opacity(0.14))
                    .frame(
                        width: 46,
                        height: 46
                    )

                Image(systemName: "person")
                    .foregroundStyle(clientColor)
            }

            VStack(alignment: .leading, spacing: 5) {

                HStack(spacing: 8) {

                    Circle()
                        .fill(clientColor)
                        .frame(
                            width: 8,
                            height: 8
                        )

                    Text(client.name)
                        .font(.headline)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {

                    Text("\(client.tasks.count) задач")

                    Text("•")

                    Text(
                        client.hourlyRate.formatted(
                            .currency(code: "RUB")
                        ) + " / час"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {

                Text("СТАВКА")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(
                    client.hourlyRate.formatted(
                        .currency(code: "RUB")
                    )
                )
                .font(.headline)
            }

            Menu {

                Button {
                    editingClient = client
                } label: {

                    Label(
                        "Редактировать",
                        systemImage: "pencil"
                    )
                }

                Divider()

                Button(role: .destructive) {

                    clientToDelete = client
                    showingDeleteConfirmation = true

                } label: {

                    Label(
                        "Удалить",
                        systemImage: "trash"
                    )
                }

            } label: {

                Image(systemName: "ellipsis")
                    .frame(
                        width: 30,
                        height: 30
                    )
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    Color.secondary.opacity(0.06)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editingClient = client
        }
    }

    // MARK: - Empty

    private var emptyState: some View {

        VStack(spacing: 14) {

            Image(systemName: "person.2")
                .font(.system(size: 46))
                .foregroundStyle(.secondary)

            Text("Клиентов пока нет")
                .font(.title3)
                .bold()

            Text(
                "Добавьте клиента, чтобы привязать к нему задачи и ставку."
            )
            .foregroundStyle(.secondary)

            Button {
                showingNewClient = true
            } label: {

                Label(
                    "Добавить клиента",
                    systemImage: "plus"
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    // MARK: - Delete

    private func deleteClient(
        _ client: Client
    ) {

        modelContext.delete(client)

        try? modelContext.save()

        clientToDelete = nil
    }
}

// MARK: - Client Color Store

final class ClientColorStore {

    static let shared = ClientColorStore()

    private init() {}

    func color(for client: Client) -> Color {

        guard
            let hex = client.colorHex,
            let color = Color(hex: hex)
        else {
            return .blue
        }

        return color
    }

    func save(
        _ color: Color,
        for client: Client
    ) {

        guard let hex = color.toHex() else {
            return
        }

        client.colorHex = hex
        client.colorUpdatedAt = Date()
    }

    func remove(for client: Client) {

        client.colorHex = nil
        client.colorUpdatedAt = Date()
    }
}

// MARK: - Client Editor

struct ClientEditorView: View {

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.modelContext)
    private var modelContext

    let title: String
    let client: Client?

    let onCreated: ((Client) -> Void)?

    @State private var name: String
    @State private var rate: String
    @State private var clientColor: Color
    @State private var showingColorPalette = false

    init(
        title: String,
        client: Client? = nil,
        onCreated: ((Client) -> Void)? = nil
    ) {

        self.title = title
        self.client = client
        self.onCreated = onCreated

        let initialName = client?.name ?? ""

        let initialRate: String

        if let client, client.hourlyRate != 0 {

            initialRate = String(
                format: "%.2f",
                client.hourlyRate
            )

        } else {

            initialRate = ""
        }

        let initialColor = client.map {
            ClientColorStore.shared.color(for: $0)
        } ?? Color.blue

        _name = State(initialValue: initialName)
        _rate = State(initialValue: initialRate)
        _clientColor = State(initialValue: initialColor)
    }

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            Text(title)
                .font(.title2)
                .bold()
                .padding(.bottom, 24)

            // MARK: Name

            VStack(
                alignment: .leading,
                spacing: 7
            ) {

                Text("Название")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    "Название клиента",
                    text: $name
                )
                .textFieldStyle(.roundedBorder)
            }
            .padding(.bottom, 18)

            // MARK: Rate

            VStack(
                alignment: .leading,
                spacing: 7
            ) {

                Text("Ставка по умолчанию")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {

                    TextField(
                        "0",
                        text: $rate
                    )
                    .textFieldStyle(.roundedBorder)

                    Text("₽ / час")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 18)

            // MARK: Color

            VStack(
                alignment: .leading,
                spacing: 8
            ) {

                Text("Цвет клиента")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {

                    Button {

                        showingColorPalette.toggle()

                    } label: {

                        RoundedRectangle(cornerRadius: 9)
                            .fill(clientColor)
                            .frame(
                                width: 42,
                                height: 32
                            )
                            .overlay {

                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(
                                        Color.primary.opacity(0.12),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .popover(
                        isPresented: $showingColorPalette,
                        arrowEdge: .bottom
                    ) {

                        ClientColorPalette(
                            selectedColor: $clientColor
                        )
                    }

                    Text("Нажмите, чтобы выбрать цвет")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }

            // MARK: Tasks

            if let client {

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {

                    Text("Задачи")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(client.tasks.count)")
                        .font(.headline)
                }
                .padding(.top, 18)
            }

            Spacer()

            Divider()
                .padding(.bottom, 14)

            // MARK: Buttons

            HStack {

                Button("Отмена") {
                    dismiss()
                }

                Spacer()

                Button(
                    client == nil ? "Создать" : "Сохранить"
                ) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(
                    name.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
        }
        .padding(24)
        .frame(
            width: 460,
            height: 350
        )
    }

    // MARK: - Save

    private func save() {

        let cleanName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanName.isEmpty else {
            return
        }

        let parsedRate = Double(
            rate
                .replacingOccurrences(
                    of: ",",
                    with: "."
                )
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        ) ?? 0

        let finalRate = max(0, parsedRate)

        if let client {

            client.name = cleanName
            client.hourlyRate = finalRate

            ClientColorStore.shared.save(
                clientColor,
                for: client
            )

            client.updatedAt = Date()

        } else {

            let newClient = Client(
                name: cleanName,
                hourlyRate: finalRate
            )

            modelContext.insert(newClient)

            ClientColorStore.shared.save(
                clientColor,
                for: newClient
            )

            onCreated?(newClient)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Ошибка сохранения клиента: \(error)")
        }
    }
}

// MARK: - Client Color Palette

struct ClientColorPalette: View {

    @Binding var selectedColor: Color

    @Environment(\.dismiss)
    private var dismiss

    @State private var customColor: Color

    private let colors: [Color] = [

        Color(red: 0.95, green: 0.25, blue: 0.25),
        Color(red: 0.95, green: 0.48, blue: 0.20),
        Color(red: 0.95, green: 0.70, blue: 0.15),
        Color(red: 0.45, green: 0.75, blue: 0.25),
        Color(red: 0.20, green: 0.72, blue: 0.42),
        Color(red: 0.15, green: 0.70, blue: 0.72),
        Color(red: 0.20, green: 0.55, blue: 0.95),
        Color(red: 0.35, green: 0.38, blue: 0.95),
        Color(red: 0.62, green: 0.35, blue: 0.92),
        Color(red: 0.82, green: 0.30, blue: 0.70),
        Color(red: 0.95, green: 0.35, blue: 0.55),
        Color(red: 0.45, green: 0.48, blue: 0.52),
        Color(red: 0.15, green: 0.18, blue: 0.22),
        Color(red: 0.95, green: 0.95, blue: 0.95)
    ]

    init(selectedColor: Binding<Color>) {

        self._selectedColor = selectedColor

        _customColor = State(
            initialValue: selectedColor.wrappedValue
        )
    }

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 14
        ) {

            Text("Цвет")
                .font(.headline)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(
                        .fixed(30),
                        spacing: 10
                    ),
                    count: 7
                ),
                spacing: 10
            ) {

                ForEach(
                    Array(colors.enumerated()),
                    id: \.offset
                ) { _, color in

                    Button {

                        selectedColor = color
                        customColor = color
                        dismiss()

                    } label: {

                        Circle()
                            .fill(color)
                            .frame(
                                width: 30,
                                height: 30
                            )
                            .overlay {

                                Circle()
                                    .stroke(
                                        selectedColor.toHex() == color.toHex()
                                        ? Color.primary
                                        : Color.clear,
                                        lineWidth: 2
                                    )
                            }
                            .overlay {

                                Circle()
                                    .stroke(
                                        Color.primary.opacity(0.12),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .padding(.vertical, 2)

            ColorPicker(
                "Свой цвет",
                selection: $customColor,
                supportsOpacity: false
            )
            .onChange(of: customColor) {
                selectedColor = customColor
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

// MARK: - Color Hex Helpers

extension Color {

    init?(hex: String) {

        var hexString = hex.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        hexString = hexString.replacingOccurrences(
            of: "#",
            with: ""
        )

        guard
            hexString.count == 6,
            let value = UInt64(hexString, radix: 16)
        else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0

        self.init(
            red: red,
            green: green,
            blue: blue
        )
    }

    func toHex() -> String? {

        let nsColor = NSColor(self)

        guard let converted = nsColor.usingColorSpace(.deviceRGB) else {
            return nil
        }

        let red = Int(round(converted.redComponent * 255))
        let green = Int(round(converted.greenComponent * 255))
        let blue = Int(round(converted.blueComponent * 255))

        return String(
            format: "#%02X%02X%02X",
            red,
            green,
            blue
        )
    }
}
