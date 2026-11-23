
import SwiftUI
import SwiftData
import AppKit
import PDFKit
import UniformTypeIdentifiers
import CoreGraphics

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TimeEntry.startDate, order: .reverse)
    private var entries: [TimeEntry]

    @Query(sort: \Client.name)
    private var clients: [Client]

    @Query(sort: \WorkTask.name)
    private var tasks: [WorkTask]

    @State private var period: HistoryPeriod = .today
    @State private var customStartDate = Calendar.current.startOfDay(for: Date())
    @State private var customEndDate = Date()
    @State private var selectedClient: Client?
    @State private var selectedTask: WorkTask?
    @State private var showingNewEntry = false
    @State private var editingEntry: TimeEntry?
    @State private var entryToDelete: TimeEntry?
    @State private var showingDeleteConfirmation = false
    @State private var selectedEntryIDs: Set<PersistentIdentifier> = []
    @State private var showingBulkDeleteConfirmation = false
    @State private var exportError = ""
    @State private var showingExportError = false
    @State private var csvDocument: CSVFileDocument?
    @State private var pdfDocument: PDFFileDocument?
    @State private var showingCSVExporter = false
    @State private var showingPDFExporter = false

    private let russianLocale = Locale(identifier: "ru_RU")

    private var filteredEntries: [TimeEntry] {
        entries.filter { entry in
            guard entry.startDate >= periodStart,
                  entry.startDate < periodEnd else {
                return false
            }

            if let selectedClient {
                guard entry.clientName == selectedClient.name else {
                    return false
                }
            }

            if let selectedTask {
                guard entry.taskName == selectedTask.name else {
                    return false
                }
            }

            return true
        }
    }

    private var groupedEntries: [(Date, [TimeEntry])] {
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            Calendar.current.startOfDay(for: entry.startDate)
        }

        return grouped.sorted { $0.key > $1.key }
    }

    private var totalDuration: TimeInterval {
        filteredEntries.reduce(0) { $0 + $1.duration }
    }

    private var totalCost: Double {
        filteredEntries.reduce(0) { $0 + $1.cost }
    }

    private var selectedEntries: [TimeEntry] {
        entries.filter {
            selectedEntryIDs.contains($0.persistentModelID)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filters
            Divider()
            summary
            Divider()
            content
        }
        .frame(minWidth: 850, minHeight: 600)
        .environment(\.locale, russianLocale)
        .sheet(isPresented: $showingNewEntry) {
            EditTimeEntryView(
                entry: nil,
                clients: clients,
                tasks: tasks
            )
        }
        .sheet(item: $editingEntry) { entry in
            EditTimeEntryView(
                entry: entry,
                clients: clients,
                tasks: tasks
            )
        }
        .confirmationDialog(
            "Удалить запись?",
            isPresented: $showingDeleteConfirmation,
            presenting: entryToDelete
        ) { entry in
            Button("Удалить", role: .destructive) {
                deleteEntry(entry)
            }

            Button("Отмена", role: .cancel) {}
        } message: { entry in
            Text("Запись «\(entry.taskName)» будет удалена.")
        }
        .confirmationDialog(
            "Удалить выбранные записи?",
            isPresented: $showingBulkDeleteConfirmation
        ) {
            Button(
                "Удалить \(selectedEntryIDs.count) записей",
                role: .destructive
            ) {
                deleteSelectedEntries()
            }

            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будет удалено записей: \(selectedEntryIDs.count).")
        }
        .alert("Ошибка экспорта", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError)
        }
        .fileExporter(
            isPresented: $showingCSVExporter,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "time-tracker.csv"
        ) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                showExportError(error)
            }
        }
        .fileExporter(
            isPresented: $showingPDFExporter,
            document: pdfDocument,
            contentType: .pdf,
            defaultFilename: "time-tracker.pdf"
        ) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                showExportError(error)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("История")
                    .font(.title2.weight(.semibold))

                Text("Учёт рабочего времени")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !selectedEntryIDs.isEmpty {
                Button {
                    showingBulkDeleteConfirmation = true
                } label: {
                    Label(
                        "Удалить (\(selectedEntryIDs.count))",
                        systemImage: "trash"
                    )
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            Menu {
                Button {
                    exportCSV()
                } label: {
                    Label("Экспорт CSV", systemImage: "tablecells")
                }

                Button {
                    exportPDF()
                } label: {
                    Label("Экспорт PDF", systemImage: "doc.richtext")
                }
            } label: {
                Label("Экспорт", systemImage: "square.and.arrow.up")
            }

            Button {
                showingNewEntry = true
            } label: {
                Label("Добавить", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
    }

    // MARK: - Filters

    private var filters: some View {
        HStack(spacing: 12) {
            Picker("Период", selection: $period) {
                ForEach(HistoryPeriod.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .frame(width: 150)

            if period == .custom {
                DatePicker(
                    "С",
                    selection: $customStartDate,
                    displayedComponents: .date
                )
                .labelsHidden()

                DatePicker(
                    "До",
                    selection: $customEndDate,
                    displayedComponents: .date
                )
                .labelsHidden()
            }

            Picker("Клиент", selection: $selectedClient) {
                Text("Все клиенты").tag(nil as Client?)

                ForEach(clients) { client in
                    Text(client.name).tag(Optional(client))
                }
            }
            .frame(width: 180)

            Picker("Задача", selection: $selectedTask) {
                Text("Все задачи").tag(nil as WorkTask?)

                ForEach(tasks) { task in
                    Text(task.name).tag(Optional(task))
                }
            }
            .frame(width: 220)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(spacing: 12) {
            SummaryCard(
                title: "Записей",
                value: "\(filteredEntries.count)",
                icon: "list.bullet"
            )

            SummaryCard(
                title: "Время",
                value: formattedDuration(totalDuration),
                icon: "clock"
            )

            SummaryCard(
                title: "Стоимость",
                value: totalCost.formatted(.currency(code: "RUB")),
                icon: "rublesign.circle"
            )

            Spacer()
        }
        .padding(16)
    }

    // MARK: - Content

    private var content: some View {
        Group {
            if filteredEntries.isEmpty {
                VStack(spacing: 12) {
                    Spacer()

                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)

                    Text("Записей нет")
                        .font(.headline)

                    Text("За выбранный период ничего не найдено.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Добавить время") {
                        showingNewEntry = true
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selectedEntryIDs) {
                    ForEach(groupedEntries, id: \.0) { day, dayEntries in
                        Section {
                            ForEach(dayEntries) { entry in
                                TimeEntryRow(
                                    entry: entry,
                                    client: client(for: entry),
                                    onEdit: {
                                        editingEntry = entry
                                    },
                                    onDelete: {
                                        entryToDelete = entry
                                        showingDeleteConfirmation = true
                                    }
                                )
                                .tag(entry.persistentModelID)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    editingEntry = entry
                                }
                            }
                        } header: {
                            HStack {
                                Text(formattedDay(day))

                                Spacer()

                                Text(
                                    formattedDuration(
                                        dayEntries.reduce(0) {
                                            $0 + $1.duration
                                        }
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Client

    private func client(for entry: TimeEntry) -> Client? {
        if let client = entry.task?.client {
            return client
        }

        guard !entry.clientName.isEmpty else {
            return nil
        }

        return clients.first {
            $0.name == entry.clientName
        }
    }

    // MARK: - Delete

    private func deleteEntry(_ entry: TimeEntry) {
        let persistentID = entry.persistentModelID

        let entryID = entry.id ?? UUID()
        entry.id = entryID

        modelContext.delete(entry)

        do {
            try modelContext.save()

            // Регистрируем удаление только после успешного
            // сохранения локальной базы.

            SyncService.recordEntryDeletion(entryID)

        } catch {
            print("Ошибка удаления записи: \(error)")
        }

        selectedEntryIDs.remove(persistentID)
    }

    private func deleteSelectedEntries() {
        let entriesToDelete = selectedEntries

        // Сохраняем UUID до удаления объектов из контекста.

        let deletedIDs: [UUID] = entriesToDelete.map { entry in
            let id = entry.id ?? UUID()
            entry.id = id
            return id
        }

        for entry in entriesToDelete {
            modelContext.delete(entry)
        }

        do {
            try modelContext.save()

            // Добавляем все UUID в очередь только после
            // успешного сохранения массового удаления.

            for id in deletedIDs {
                SyncService.recordEntryDeletion(id)
            }

        } catch {
            print("Ошибка удаления выбранных записей: \(error)")
        }

        selectedEntryIDs.removeAll()
    }

    // MARK: - Period

    private var periodStart: Date {
        let calendar = Calendar.current

        switch period {
        case .all:
            return Date.distantPast

        case .today:
            return calendar.startOfDay(for: Date())

        case .week:
            return calendar.date(
                byAdding: .day,
                value: -6,
                to: calendar.startOfDay(for: Date())
            ) ?? Date.distantPast

        case .month:
            return calendar.date(
                from: calendar.dateComponents([.year, .month], from: Date())
            ) ?? Date.distantPast

        case .custom:
            return calendar.startOfDay(for: customStartDate)
        }
    }

    private var periodEnd: Date {
        let calendar = Calendar.current

        switch period {
        case .all:
            return Date.distantFuture

        case .today:
            return calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: Date())
            ) ?? Date.distantFuture

        case .week:
            return calendar.date(
                byAdding: .day,
                value: 1,
                to: Date()
            ) ?? Date.distantFuture

        case .month:
            let startOfMonth = calendar.date(
                from: calendar.dateComponents([.year, .month], from: Date())
            ) ?? Date()

            return calendar.date(
                byAdding: .month,
                value: 1,
                to: startOfMonth
            ) ?? Date.distantFuture

        case .custom:
            return calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: customEndDate)
            ) ?? Date.distantFuture
        }
    }

    // MARK: - CSV Export

    private func exportCSV() {
        let header =
            "Дата;Начало;Конец;Задача;Клиент;Ставка;Длительность;Стоимость;Комментарий\n"

        let rows = filteredEntries.map { entry in
            let date = csvDate(entry.startDate)
            let start = csvTime(entry.startDate)
            let end = csvTime(entry.endDate)
            let task = csvEscape(entry.taskName)
            let client = csvEscape(entry.clientName)
            let rate = String(format: "%.2f", entry.hourlyRate)
            let duration = entry.formattedDuration
            let cost = String(format: "%.2f", entry.cost)
            let note = csvEscape(entry.note)

            return "\(date);\(start);\(end);\(task);\(client);\(rate);\(duration);\(cost);\(note)"
        }
        .joined(separator: "\n")

        let csv = header + rows

        guard let data = csv.data(using: .utf8) else {
            showExportError(
                NSError(
                    domain: "TimeTracker",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Не удалось подготовить CSV-файл."
                    ]
                )
            )
            return
        }

        csvDocument = CSVFileDocument(data: data)
        showingCSVExporter = true
    }

    // MARK: - PDF Export

    private func exportPDF() {
        let pageWidth: CGFloat = 595
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 40

        let mutableData = NSMutableData()

        guard let consumer = CGDataConsumer(data: mutableData) else {
            showExportError(
                NSError(
                    domain: "TimeTracker",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Не удалось создать PDF-контекст."
                    ]
                )
            )
            return
        }

        var mediaBox = CGRect(
            x: 0,
            y: 0,
            width: pageWidth,
            height: pageHeight
        )

        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &mediaBox,
            nil
        ) else {
            showExportError(
                NSError(
                    domain: "TimeTracker",
                    code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Не удалось создать PDF-контекст."
                    ]
                )
            )
            return
        }

        let contentWidth = pageWidth - margin * 2
        var currentY = pageHeight - margin
        var hasContentOnPage = false

        func beginPDFPage() {
            context.beginPDFPage(
                [
                    kCGPDFContextMediaBox as String:
                        CGRect(
                            x: 0,
                            y: 0,
                            width: pageWidth,
                            height: pageHeight
                        )
                ] as CFDictionary
            )

            context.saveGState()
            context.translateBy(x: 0, y: pageHeight)
            context.scaleBy(x: 1, y: -1)

            currentY = margin
            hasContentOnPage = false
        }

        func endPDFPage() {
            context.restoreGState()
            context.endPDFPage()
            hasContentOnPage = false
        }

        func startNewPage() {
            beginPDFPage()
        }

        func drawText(
            _ text: String,
            x: CGFloat,
            y: CGFloat,
            font: NSFont,
            color: NSColor = .black
        ) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]

            let attributed = NSAttributedString(
                string: text,
                attributes: attributes
            )

            let graphicsContext = NSGraphicsContext(
                cgContext: context,
                flipped: true
            )

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext

            attributed.draw(at: NSPoint(x: x, y: y))

            NSGraphicsContext.restoreGraphicsState()
            hasContentOnPage = true
        }

        func drawTitle(x: CGFloat, y: CGFloat) {
            let title = NSMutableAttributedString(
                string: "se:cu tracker",
                attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 22),
                    .foregroundColor: NSColor.black
                ]
            )

            title.addAttribute(
                .foregroundColor,
                value: NSColor(
                    red: 1.0,
                    green: 0.0,
                    blue: 0.0,
                    alpha: 1.0
                ),
                range: NSRange(location: 2, length: 1)
            )

            let graphicsContext = NSGraphicsContext(
                cgContext: context,
                flipped: true
            )

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext

            title.draw(at: NSPoint(x: x, y: y))

            NSGraphicsContext.restoreGraphicsState()
            hasContentOnPage = true
        }

        func ensureSpace(_ height: CGFloat) {
            if currentY + height > pageHeight - margin {
                endPDFPage()
                startNewPage()
            }
        }

        beginPDFPage()

        drawTitle(x: margin, y: currentY)
        currentY += 34

        drawText(
            "История рабочего времени",
            x: margin,
            y: currentY,
            font: NSFont.systemFont(ofSize: 13),
            color: .darkGray
        )

        currentY += 24

        drawText(
            "Период: \(periodTitleForPDF())",
            x: margin,
            y: currentY,
            font: NSFont.systemFont(ofSize: 11),
            color: .darkGray
        )

        currentY += 30

        drawText(
            "Всего: \(formattedDuration(totalDuration))",
            x: margin,
            y: currentY,
            font: NSFont.boldSystemFont(ofSize: 12)
        )

        drawText(
            "Стоимость: \(totalCost.formatted(.currency(code: "RUB")))",
            x: margin + contentWidth * 0.55,
            y: currentY,
            font: NSFont.boldSystemFont(ofSize: 12)
        )

        currentY += 34

        for (day, dayEntries) in groupedEntries {
            ensureSpace(60)

            drawText(
                formattedDay(day),
                x: margin,
                y: currentY,
                font: NSFont.boldSystemFont(ofSize: 13)
            )

            currentY += 22

            for entry in dayEntries {
                ensureSpace(62)

                drawText(
                    entry.taskName,
                    x: margin,
                    y: currentY,
                    font: NSFont.boldSystemFont(ofSize: 10)
                )

                drawText(
                    entry.formattedDuration,
                    x: margin + contentWidth * 0.55,
                    y: currentY,
                    font: NSFont.monospacedSystemFont(
                        ofSize: 10,
                        weight: .regular
                    )
                )

                drawText(
                    entry.formattedCost,
                    x: margin + contentWidth * 0.78,
                    y: currentY,
                    font: NSFont.systemFont(ofSize: 10)
                )

                currentY += 16

                let clientText = entry.clientName.isEmpty
                    ? ""
                    : "\(entry.clientName) • "

                var clientTextX = margin

                if !entry.clientName.isEmpty,
                   let client = client(for: entry) {
                    let nsColor = NSColor(
                        ClientColorStore.shared.color(for: client)
                    )

                    if let rgbColor = nsColor.usingColorSpace(.deviceRGB) {
                        context.setFillColor(rgbColor.cgColor)
                        context.fillEllipse(
                            in: CGRect(
                                x: margin,
                                y: currentY + 3,
                                width: 6,
                                height: 6
                            )
                        )

                        clientTextX = margin + 12
                    }
                }

                drawText(
                    "\(clientText)\(formattedTime(entry.startDate)) – \(formattedTime(entry.endDate))",
                    x: clientTextX,
                    y: currentY,
                    font: NSFont.systemFont(ofSize: 8),
                    color: .darkGray
                )

                currentY += 14

                if !entry.note.isEmpty {
                    ensureSpace(20)

                    drawText(
                        "Комментарий: \(entry.note)",
                        x: margin,
                        y: currentY,
                        font: NSFont.systemFont(ofSize: 8),
                        color: .darkGray
                    )

                    currentY += 14
                }

                currentY += 8
            }

            currentY += 8
        }

        if !hasContentOnPage {
            drawText(
                "Нет записей за выбранный период.",
                x: margin,
                y: currentY,
                font: NSFont.systemFont(ofSize: 11)
            )
        }

        endPDFPage()
        context.closePDF()

        let data = mutableData as Data

        guard !data.isEmpty else {
            showExportError(
                NSError(
                    domain: "TimeTracker",
                    code: 4,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "PDF-файл получился пустым."
                    ]
                )
            )
            return
        }

        guard let pdf = PDFDocument(data: data),
              pdf.pageCount > 0 else {
            showExportError(
                NSError(
                    domain: "TimeTracker",
                    code: 5,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Не удалось проверить созданный PDF-файл."
                    ]
                )
            )
            return
        }

        pdfDocument = PDFFileDocument(data: data)
        showingPDFExporter = true
    }

    // MARK: - PDF Helpers

    private func periodTitleForPDF() -> String {
        switch period {
        case .all:
            return "Всё время"
        case .today:
            return "Сегодня"
        case .week:
            return "Последние 7 дней"
        case .month:
            return "Текущий месяц"
        case .custom:
            return "\(formattedDate(customStartDate)) – \(formattedDate(customEndDate))"
        }
    }

    private func formattedDay(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(russianLocale)
                .weekday(.wide)
                .day()
                .month(.wide)
                .year()
        )
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(russianLocale)
                .day()
                .month()
                .year()
        )
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(russianLocale)
                .hour()
                .minute()
                .second()
        )
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        return String(
            format: "%02d:%02d:%02d",
            hours,
            minutes,
            seconds
        )
    }

    private func csvDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = russianLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "dd.MM.yyyy"

        return formatter.string(from: date)
    }

    private func csvTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = russianLocale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"

        return formatter.string(from: date)
    }

    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(
            of: "\"",
            with: "\"\""
        )

        return "\"\(escaped)\""
    }

    private func showExportError(_ error: Error) {
        exportError = error.localizedDescription
        showingExportError = true
    }
}

// MARK: - History Period

enum HistoryPeriod: String, CaseIterable, Identifiable {
    case all
    case today
    case week
    case month
    case custom

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all:
            return "Всё время"
        case .today:
            return "Сегодня"
        case .week:
            return "Неделя"
        case .month:
            return "Месяц"
        case .custom:
            return "Свой период"
        }
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
        }
        .frame(minWidth: 150, alignment: .leading)
        .padding(12)
        .background(
            Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}

// MARK: - Time Entry Row

struct TimeEntryRow: View {
    let entry: TimeEntry
    let client: Client?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let client {
                        Circle()
                            .fill(
                                ClientColorStore.shared.color(for: client)
                            )
                            .frame(width: 8, height: 8)
                    }

                    Text(entry.taskName)
                        .font(.body.weight(.medium))
                }

                HStack(spacing: 6) {
                    if !entry.clientName.isEmpty {
                        Text(entry.clientName)
                        Text("•")
                    }

                    Text(
                        "\(formattedTime(entry.startDate)) – \(formattedTime(entry.endDate))"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.formattedDuration)
                    .font(.system(.body, design: .monospaced))

                Text(entry.formattedCost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("Изменить", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 5)
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(Locale(identifier: "ru_RU"))
                .hour()
                .minute()
                .second()
        )
    }
}

// MARK: - Edit Time Entry

struct EditTimeEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let entry: TimeEntry?
    let clients: [Client]
    let tasks: [WorkTask]

    @State private var selectedTask: WorkTask?
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var startHour: String
    @State private var startMinute: String
    @State private var startSecond: String
    @State private var endHour: String
    @State private var endMinute: String
    @State private var endSecond: String
    @State private var rateText: String
    @State private var note: String

    @FocusState private var focusedField: TimeField?

    enum TimeField: Hashable {
        case startHour
        case startMinute
        case startSecond
        case endHour
        case endMinute
        case endSecond
        case rate
    }

    init(
        entry: TimeEntry?,
        clients: [Client],
        tasks: [WorkTask]
    ) {
        self.entry = entry
        self.clients = clients
        self.tasks = tasks

        if let entry {
            _startDate = State(initialValue: entry.startDate)
            _endDate = State(initialValue: entry.endDate)

            _startHour = State(
                initialValue: Self.timePart(
                    entry.startDate,
                    component: .hour
                )
            )

            _startMinute = State(
                initialValue: Self.timePart(
                    entry.startDate,
                    component: .minute
                )
            )

            _startSecond = State(
                initialValue: Self.timePart(
                    entry.startDate,
                    component: .second
                )
            )

            _endHour = State(
                initialValue: Self.timePart(
                    entry.endDate,
                    component: .hour
                )
            )

            _endMinute = State(
                initialValue: Self.timePart(
                    entry.endDate,
                    component: .minute
                )
            )

            _endSecond = State(
                initialValue: Self.timePart(
                    entry.endDate,
                    component: .second
                )
            )

            _rateText = State(
                initialValue: String(
                    format: "%.2f",
                    entry.hourlyRate
                )
            )

            _note = State(initialValue: entry.note)
            _selectedTask = State(initialValue: entry.task)
        } else {
            let now = Date()
            let start = now.addingTimeInterval(-3600)

            _startDate = State(initialValue: start)
            _endDate = State(initialValue: now)

            _startHour = State(
                initialValue: Self.timePart(
                    start,
                    component: .hour
                )
            )

            _startMinute = State(
                initialValue: Self.timePart(
                    start,
                    component: .minute
                )
            )

            _startSecond = State(
                initialValue: Self.timePart(
                    start,
                    component: .second
                )
            )

            _endHour = State(
                initialValue: Self.timePart(
                    now,
                    component: .hour
                )
            )

            _endMinute = State(
                initialValue: Self.timePart(
                    now,
                    component: .minute
                )
            )

            _endSecond = State(
                initialValue: Self.timePart(
                    now,
                    component: .second
                )
            )

            _rateText = State(
                initialValue: String(
                    format: "%.2f",
                    AppSettings.shared.defaultHourlyRate
                )
            )

            _note = State(initialValue: "")
            _selectedTask = State(initialValue: tasks.first)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()

            ScrollView {
                editorContent
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
            }

            Divider()
            editorFooter
        }
        .frame(width: 760, height: 800)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .onChange(of: selectedTask?.persistentModelID) {
            guard let selectedTask else {
                return
            }

            if entry == nil {
                rateText = String(
                    format: "%.2f",
                    selectedTask.hourlyRate
                )
            }
        }
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry == nil ? "Добавить время" : "Изменить запись")
                    .font(.title2.weight(.semibold))

                Text(
                    entry == nil
                    ? "Добавьте рабочее время вручную"
                    : "Измените дату, время или ставку записи"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    // MARK: - Content

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            taskCard
            timeCard
            rateCard
            noteCard
            calculationCard
        }
        .padding(24)
    }

    // MARK: - Task

    private var taskCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: 10) {
                editorSectionTitle("Задача", icon: "checklist")

                Picker("", selection: $selectedTask) {
                    Text("Без задачи").tag(nil as WorkTask?)

                    ForEach(tasks) { task in
                        Text(task.name).tag(Optional(task))
                    }
                }
                .labelsHidden()
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                if let client = selectedTask?.client {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(
                                ClientColorStore.shared.color(for: client)
                            )
                            .frame(width: 10, height: 10)

                        Text(client.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .padding(.top, 2)
                } else if let entry,
                          !entry.clientName.isEmpty,
                          let client = clients.first(where: {
                              $0.name == entry.clientName
                          }) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(
                                ClientColorStore.shared.color(for: client)
                            )
                            .frame(width: 10, height: 10)

                        Text(client.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - Time

    private var timeCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: 16) {
                editorSectionTitle("Рабочее время", icon: "clock")

                HStack(alignment: .top, spacing: 16) {
                    timeBlock(
                        title: "Начало",
                        date: $startDate,
                        hour: $startHour,
                        minute: $startMinute,
                        second: $startSecond,
                        hourField: .startHour,
                        minuteField: .startMinute,
                        secondField: .startSecond
                    )

                    timeBlock(
                        title: "Окончание",
                        date: $endDate,
                        hour: $endHour,
                        minute: $endMinute,
                        second: $endSecond,
                        hourField: .endHour,
                        minuteField: .endMinute,
                        secondField: .endSecond
                    )
                }
                .frame(maxWidth: .infinity, alignment: .center)

                if endDate <= startDate {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")

                        Text("Время окончания должно быть позже начала.")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        }
    }

    private func timeBlock(
        title: String,
        date: Binding<Date>,
        hour: Binding<String>,
        minute: Binding<String>,
        second: Binding<String>,
        hourField: TimeField,
        minuteField: TimeField,
        secondField: TimeField
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            DatePicker(
                "",
                selection: date,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .controlSize(.large)
            .frame(width: 260, alignment: .leading)

            HStack(spacing: 6) {
                timeInputColumn(
                    value: hour,
                    label: "часы",
                    placeholder: "HH",
                    field: hourField
                )

                timeSeparator()

                timeInputColumn(
                    value: minute,
                    label: "мин",
                    placeholder: "MM",
                    field: minuteField
                )

                timeSeparator()

                timeInputColumn(
                    value: second,
                    label: "сек",
                    placeholder: "SS",
                    field: secondField
                )
            }
            .frame(width: 260, alignment: .leading)
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .background(
            Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func timeInputColumn(
        value: Binding<String>,
        label: String,
        placeholder: String,
        field: TimeField
    ) -> some View {
        VStack(spacing: 6) {
            largeTimeField(
                value,
                placeholder: placeholder,
                field: field
            )

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 64)
        }
        .frame(width: 64)
    }

    private func timeSeparator() -> some View {
        Text(":")
            .font(.system(size: 22, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 8, height: 48)
            .padding(.bottom, 22)
    }

    private func largeTimeField(
        _ value: Binding<String>,
        placeholder: String,
        field: TimeField
    ) -> some View {
        TextField(placeholder, text: value)
            .textFieldStyle(.plain)
            .font(.system(size: 20, weight: .medium, design: .monospaced))
            .multilineTextAlignment(.center)
            .frame(width: 64, height: 48)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        focusedField == field
                        ? Color.accentColor
                        : Color.secondary.opacity(0.20),
                        lineWidth: focusedField == field ? 2 : 1
                    )
            )
            .focused($focusedField, equals: field)
            .onChange(of: value.wrappedValue) {
                let normalized = normalizeTimeInput(value.wrappedValue)

                if normalized != value.wrappedValue {
                    value.wrappedValue = normalized
                }

                synchronizeDates()
            }
    }

    // MARK: - Rate

    private var rateCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: 10) {
                editorSectionTitle("Ставка", icon: "rublesign.circle")

                HStack(spacing: 12) {
                    TextField("0", text: $rateText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 170, height: 46)
                        .padding(.horizontal, 12)
                        .background(
                            Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    focusedField == .rate
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.20),
                                    lineWidth: focusedField == .rate ? 2 : 1
                                )
                        )
                        .focused($focusedField, equals: .rate)
                        .onChange(of: rateText) {
                            let normalized = normalizeRateText(rateText)

                            if normalized != rateText {
                                rateText = normalized
                            }
                        }

                    Text("₽ / час")
                        .foregroundStyle(.secondary)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Стоимость")

                        Text(
                            calculatedCost.formatted(
                                .currency(code: "RUB")
                            )
                        )
                        .font(.headline)
                    }
                }
            }
        }
    }

    // MARK: - Note

    private var noteCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: 10) {
                editorSectionTitle("Комментарий", icon: "text.alignleft")

                TextField(
                    "Комментарий к записи",
                    text: $note,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(3...5)
                .padding(12)
                .frame(minHeight: 80, alignment: .topLeading)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            Color.secondary.opacity(0.18),
                            lineWidth: 1
                        )
                )
            }
        }
    }

    // MARK: - Calculation

    private var calculationCard: some View {
        HStack(spacing: 12) {
            calculationItem(
                title: "Длительность",
                value: formattedDuration(currentDuration),
                icon: "timer"
            )

            calculationItem(
                title: "Стоимость",
                value: calculatedCost.formatted(.currency(code: "RUB")),
                icon: "rublesign.circle"
            )
        }
    }

    private func calculationItem(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(.body, design: .monospaced))
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    // MARK: - Card Helpers

    private func editorCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.secondary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        Color.secondary.opacity(0.10),
                        lineWidth: 1
                    )
            )
    }

    private func editorSectionTitle(
        _ title: String,
        icon: String
    ) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }

    // MARK: - Footer

    private var editorFooter: some View {
        HStack {
            Button("Отмена") {
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button("Сохранить") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(selectedTask == nil || endDate <= startDate)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    // MARK: - Calculations

    private var currentDuration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }

    private var calculatedCost: Double {
        let rate = Double(normalizeRateText(rateText)) ?? 0
        return currentDuration / 3600 * rate
    }

    // MARK: - Rate Normalization

    private func normalizeRateText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Date / Time

    private func synchronizeDates() {
        if let newStart = dateByReplacingTime(
            startDate,
            hour: startHour,
            minute: startMinute,
            second: startSecond
        ) {
            startDate = newStart
        }

        if let newEnd = dateByReplacingTime(
            endDate,
            hour: endHour,
            minute: endMinute,
            second: endSecond
        ) {
            endDate = newEnd
        }
    }

    private func dateByReplacingTime(
        _ date: Date,
        hour: String,
        minute: String,
        second: String
    ) -> Date? {
        let h = Int(hour.filter { $0.isNumber })
        let m = Int(minute.filter { $0.isNumber })
        let s = Int(second.filter { $0.isNumber })

        guard let h, let m, let s else {
            return nil
        }

        guard (0...23).contains(h),
              (0...59).contains(m),
              (0...59).contains(s) else {
            return nil
        }

        let calendar = Calendar.current

        var components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )

        components.hour = h
        components.minute = m
        components.second = s

        return calendar.date(from: components)
    }

    private func normalizeTimeInput(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }

        if digits.count <= 2 {
            return digits
        }

        return String(digits.prefix(2))
    }

    private static func timePart(
        _ date: Date,
        component: Calendar.Component
    ) -> String {
        let value = Calendar.current.component(component, from: date)
        return String(format: "%02d", value)
    }

    // MARK: - Save

    private func save() {
        guard let selectedTask else {
            return
        }

        synchronizeDates()

        guard endDate > startDate else {
            return
        }

        let normalized = normalizeRateText(rateText)

        let rate = max(
            0,
            Double(normalized) ?? selectedTask.hourlyRate
        )

        let clientName = selectedTask.client?.name ?? ""

        if let entry {
            entry.id = entry.id ?? UUID()
            entry.startDate = startDate
            entry.endDate = endDate
            entry.taskName = selectedTask.name
            entry.clientName = clientName
            entry.hourlyRate = rate
            entry.note = note
            entry.task = selectedTask

            // Важно для сравнения локальной и облачной версий.
            entry.updatedAt = Date()

        } else {
            let newEntry = TimeEntry(
                startDate: startDate,
                endDate: endDate,
                taskName: selectedTask.name,
                clientName: clientName,
                hourlyRate: rate,
                note: note
            )

            newEntry.id = UUID()
            newEntry.updatedAt = Date()
            newEntry.task = selectedTask

            modelContext.insert(newEntry)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Ошибка сохранения записи: \(error)")
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        return String(
            format: "%02d:%02d:%02d",
            hours,
            minutes,
            remainingSeconds
        )
    }
}

// MARK: - CSV

struct CSVFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.commaSeparatedText]
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - PDF

struct PDFFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.pdf]
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
