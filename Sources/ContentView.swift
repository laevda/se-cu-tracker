
import SwiftUI
import SwiftData
import AppKit
import PDFKit
import UniformTypeIdentifiers
import CoreText

struct ContentView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WorkTask.name)
    private var tasks: [WorkTask]

    @Query(sort: \TimeEntry.startDate, order: .reverse)
    private var entries: [TimeEntry]

    @ObservedObject var timerService: TimerService

    @StateObject private var syncFolderManager = SyncFolderManager()

    @State private var isSyncing = false
    @State private var syncMessage = ""

    @State private var selectedTaskID: PersistentIdentifier?
    @State private var showingNewTask = false
    @State private var editingTask: WorkTask?
    @State private var showingHistory = false
    @State private var showingClients = false
    @State private var showingSettings = false
    @State private var taskToDelete: WorkTask?
    @State private var taskToPay: WorkTask?
    @State private var taskToRestore: WorkTask?
    @State private var showingDeleteConfirmation = false
    @State private var showingPayConfirmation = false
    @State private var showingCancelConfirmation = false
    @State private var showingActiveSessionWarning = false
    @State private var reportDocument = DashboardReportFileDocument(data: Data())
    @State private var showingReportExporter = false

    private var activeTasks: [WorkTask] {
        tasks.filter { !$0.isPaid }
    }

    private var archivedTasks: [WorkTask] {
        tasks.filter { $0.isPaid }
    }

    var body: some View {

        NavigationSplitView {

            sidebar

        } detail: {

            dashboard

        }

        .sheet(isPresented: $showingNewTask) {

            NewTaskView()

        }

        .sheet(item: $editingTask) { task in

            EditTaskView(task: task)

        }

        .sheet(isPresented: $showingHistory) {

            HistoryView()

        }

        .sheet(isPresented: $showingClients) {

            ClientsView()

        }

        .sheet(isPresented: $showingSettings) {

            SettingsView()

        }

        .fileExporter(
            isPresented: $showingReportExporter,
            document: reportDocument,
            contentType: .pdf,
            defaultFilename: reportFilename
        ) { _ in }

        .confirmationDialog(
            "Удалить задачу?",
            isPresented: $showingDeleteConfirmation,
            presenting: taskToDelete
        ) { task in

            Button("Удалить", role: .destructive) {

                deleteTask(task)

            }

            Button("Отмена", role: .cancel) {}

        } message: { task in

            Text(
                "Задача «\(task.name)» и связанные записи будут удалены."
            )

        }

        .confirmationDialog(
            "Отметить проект оплаченным?",
            isPresented: $showingPayConfirmation,
            presenting: taskToPay
        ) { task in

            Button("Отметить оплаченным") {

                markTaskAsPaid(task)

            }

            Button("Отмена", role: .cancel) {}

        } message: { task in

            Text(
                "Проект «\(task.name)» переместится в архив. Все рабочие записи сохранятся."
            )

        }

        .confirmationDialog(
            "Отменить текущую сессию?",
            isPresented: $showingCancelConfirmation
        ) {

            Button("Отменить сессию", role: .destructive) {

                timerService.cancelSession()

            }

            Button("Продолжить", role: .cancel) {}

        }

        .alert(
            "Нельзя архивировать проект",
            isPresented: $showingActiveSessionWarning
        ) {

            Button("Понятно", role: .cancel) {}

        } message: {

            Text(
                "На этом проекте ещё идёт рабочая сессия или стоит пауза. Сначала заверши её, чтобы сохранить время."
            )

        }

        .onAppear {

            restoreSelectedTask()

        }

        .onChange(of: selectedTaskID) {

            saveSelectedTask()

        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {

        VStack(spacing: 0) {

            HStack {

                VStack(
                    alignment: .leading,
                    spacing: 2
                ) {

                    Text("Time Tracker")
                        .font(.headline)

                    Text("Рабочее время")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)

                }

                Spacer()

                Button {

                    showingNewTask = true

                } label: {

                    Image(systemName: "plus")

                }
                .buttonStyle(.borderless)
                .help("Новая задача")
            }
            .padding(16)

            Divider()

            List {

                Section("Задачи") {

                    if activeTasks.isEmpty {

                        Text("Нет активных задач")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                            .listRowBackground(Color.clear)

                    } else {

                        ForEach(activeTasks) { task in

                            sidebarTaskRow(
                                task,
                                isArchived: false
                            )
                        }
                    }
                }

                Section {

                    if archivedTasks.isEmpty {

                        Text("Архив пуст")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                            .listRowBackground(Color.clear)

                    } else {

                        ForEach(archivedTasks) { task in

                            sidebarTaskRow(
                                task,
                                isArchived: true
                            )
                        }
                    }

                } header: {

                    Text("Архив")

                }
            }
            .listStyle(.sidebar)

            Divider()

            syncFolderControl
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            VStack(spacing: 2) {

                sidebarButton(
                    title: "История",
                    icon: "clock.arrow.circlepath"
                ) {

                    showingHistory = true

                }

                sidebarButton(
                    title: "Клиенты",
                    icon: "person.2"
                ) {

                    showingClients = true

                }

                sidebarButton(
                    title: "Настройки",
                    icon: "gearshape"
                ) {

                    showingSettings = true

                }
            }
            .padding(8)
        }
        .frame(minWidth: 230)
    }

    // MARK: - Sidebar Task Row

    private func sidebarTaskRow(
        _ task: WorkTask,
        isArchived: Bool
    ) -> some View {

        Button {

            selectedTaskID = task.persistentModelID

        } label: {

            taskRow(task)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
                .background {

                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            selectedTaskID == task.persistentModelID
                            ? Color.accentColor.opacity(0.16)
                            : Color.clear
                        )
                }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {

                    selectedTaskID = task.persistentModelID
                    editingTask = task

                }
        )
        .contextMenu {

            Button {

                selectedTaskID = task.persistentModelID
                editingTask = task

            } label: {

                Label(
                    "Изменить",
                    systemImage: "pencil"
                )

            }

            if isArchived {

                Button {

                    restoreTask(task)

                } label: {

                    Label(
                        "Вернуть из архива",
                        systemImage: "arrow.uturn.backward"
                    )

                }

            } else {

                Button {

                    requestPayment(task)

                } label: {

                    Label(
                        "Отметить оплаченным",
                        systemImage: "checkmark.circle"
                    )

                }
            }

            Button(role: .destructive) {

                taskToDelete = task
                showingDeleteConfirmation = true

            } label: {

                Label(
                    "Удалить",
                    systemImage: "trash"
                )

            }
        }
    }

    // MARK: - Sync Folder

    private var syncFolderControl: some View {

        VStack(alignment: .leading, spacing: 9) {

            HStack(spacing: 7) {

                Image(systemName: "icloud")
                    .foregroundStyle(
                        syncFolderManager.folderURL == nil
                        ? Color.secondary
                        : Color.green
                    )

                Text("Синхронизация")
                    .font(.caption.weight(.semibold))

                Spacer()
            }

            Text(
                syncMessage.isEmpty
                ? syncFolderManager.status
                : syncMessage
            )
            .font(.caption2)
            .foregroundStyle(Color.secondary)
            .lineLimit(3)

            Button {

                syncMessage = ""
                syncFolderManager.chooseFolder()

            } label: {

                Label(
                    syncFolderManager.folderURL == nil
                    ? "Подключить папку"
                    : "Изменить папку",
                    systemImage: "folder"
                )
                .font(.caption)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {

                synchronizeData()

            } label: {

                if isSyncing {

                    Label(
                        "Синхронизация…",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption)
                    .frame(maxWidth: .infinity)

                } else {

                    Label(
                        "Синхронизировать",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption)
                    .frame(maxWidth: .infinity)

                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(
                syncFolderManager.folderURL == nil || isSyncing
            )
        }
        .padding(10)
        .background(
            Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private func synchronizeData() {

        guard
            let folderURL = syncFolderManager.folderURL,
            !isSyncing
        else {
            return
        }

        isSyncing = true
        syncMessage = "Выполняется синхронизация…"

        do {

            let result = try SyncService().synchronize(
                context: modelContext,
                folderURL: folderURL
            )

            syncMessage =
                "Готово: \(result.clientsCount) клиентов, " +
                "\(result.tasksCount) проектов, " +
                "\(result.entriesCount) записей"

        } catch {

            syncMessage =
                "Ошибка синхронизации: \(error.localizedDescription)"
        }

        isSyncing = false
    }

    private func taskRow(
        _ task: WorkTask
    ) -> some View {

        HStack(spacing: 8) {

            Circle()
                .fill(
                    task.client.map {
                        ClientColorStore.shared.color(for: $0)
                    }
                    ?? Color.secondary.opacity(0.35)
                )
                .frame(
                    width: 8,
                    height: 8
                )

            Image(
                systemName:
                    timerService.activeTaskID
                    == String(describing: task.persistentModelID)
                    ? "timer"
                    : task.isPaid
                    ? "checkmark.seal.fill"
                    : "checkmark.circle"
            )
            .foregroundStyle(
                task.isPaid
                ? Color.green
                : timerService.activeTaskID
                == String(describing: task.persistentModelID)
                ? Color.accentColor
                : Color.secondary
            )

            VStack(
                alignment: .leading,
                spacing: 2
            ) {

                Text(task.name)
                    .lineLimit(1)
                    .foregroundStyle(
                        task.isPaid
                        ? Color.secondary
                        : Color.primary
                    )

                if let client = task.client {

                    Text(client.name)
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)

                }
            }

            Spacer()

            if task.isPaid {

                Text("Оплачено")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Color.green.opacity(0.10),
                        in: Capsule()
                    )
            }
        }
        .padding(.vertical, 2)
    }

    private func sidebarButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {

            Label(
                title,
                systemImage: icon
            )
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
        .padding(6)
    }

    // MARK: - Payment and Archive

    private func requestPayment(_ task: WorkTask) {

        let taskID = String(
            describing: task.persistentModelID
        )

        if timerService.startDate != nil &&
            timerService.activeTaskID == taskID {

            showingActiveSessionWarning = true
            return
        }

        taskToPay = task
        showingPayConfirmation = true
    }

    private func markTaskAsPaid(_ task: WorkTask) {

        let taskID = String(
            describing: task.persistentModelID
        )

        if timerService.startDate != nil &&
            timerService.activeTaskID == taskID {

            showingActiveSessionWarning = true
            return
        }

        task.isPaid = true
        task.paidAt = Date()
        task.updatedAt = Date()

        try? modelContext.save()
    }

    private func restoreTask(_ task: WorkTask) {

        task.isPaid = false
        task.paidAt = nil
        task.updatedAt = Date()

        try? modelContext.save()

        selectedTaskID = task.persistentModelID
    }

    // MARK: - Dashboard

    private var dashboard: some View {

        ScrollView {

            VStack(
                alignment: .leading,
                spacing: 20
            ) {

                if selectedTask != nil || activeTask != nil {

                    activeTimerCard

                }

                selectedProjectCard
                todaySummary
                recentEntries
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(
            Color(nsColor: .windowBackgroundColor)
        )
    }

    // MARK: - Active Timer

    private var activeTimerCard: some View {

        let displayedTask = activeTask ?? selectedTask

        return HStack(
            alignment: .top,
            spacing: 18
        ) {

            RoundedRectangle(cornerRadius: 4)
                .fill(
                    displayedTask?.client.map {
                        ClientColorStore.shared.color(for: $0)
                    }
                    ?? Color.secondary.opacity(0.3)
                )
                .frame(width: 5)
                .frame(minHeight: 150)

            VStack(
                alignment: .leading,
                spacing: 20
            ) {

                HStack(
                    alignment: .top
                ) {

                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {

                        Text(
                            timerService.startDate != nil
                            ? "Таймер запущен на проекте:"
                            : "Готов к работе"
                        )
                        .font(.headline)

                        Text(
                            displayedTask?.name
                            ?? "Задача не выбрана"
                        )
                        .font(.title3)
                        .lineLimit(2)
                    }

                    Spacer()

                    statusBadge
                }

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {

                    Text(
                        formattedDuration(
                            timerService.elapsedTime
                        )
                    )
                    .font(
                        .system(
                            size: 58,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .minimumScaleFactor(0.6)

                    Text(
                        displayedTask?.client?.name
                        ?? "Без клиента"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        Color.secondary
                    )

                    if let task = displayedTask {

                        Text(
                            currentCost(for: task)
                                .formatted(
                                    .currency(code: "RUB")
                                )
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            Color.secondary
                        )
                    }
                }

                controls
            }
        }
        .padding(28)
        .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(
                cornerRadius: 18
            )
        )
    }

    private var statusBadge: some View {

        HStack(spacing: 6) {

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

            Text(
                timerService.isRunning
                ? "Работает"
                : timerService.startDate != nil
                ? "Пауза"
                : "Остановлен"
            )
            .font(
                .caption.weight(.medium)
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Color.secondary.opacity(0.1),
            in: Capsule()
        )
    }

    private var controls: some View {

        HStack(spacing: 10) {

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
                .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                timerService.startDate == nil
                && (selectedTask == nil || selectedTask?.isPaid == true)
            )

            if timerService.startDate != nil {

                Button {

                    stopAndSave()

                } label: {

                    Label(
                        "Стоп",
                        systemImage: "stop.fill"
                    )
                }
                .buttonStyle(.bordered)

                Button {

                    showingCancelConfirmation = true

                } label: {

                    Image(systemName: "xmark")

                }
                .buttonStyle(.bordered)
                .help("Отменить текущую сессию")
            }
        }
    }

  
    // MARK: - Selected Project

    private var selectedProjectCard: some View {

        VStack(
            alignment: .leading,
            spacing: 16
        ) {

            HStack(
                alignment: .center,
                spacing: 14
            ) {

                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        selectedTask?.client.map {
                            ClientColorStore.shared.color(for: $0)
                        }
                        ?? Color.secondary.opacity(0.25)
                    )
                    .frame(width: 5)
                    .frame(maxHeight: .infinity)

                VStack(
                    alignment: .leading,
                    spacing: 7
                ) {

                    Text(
                        selectedTask?.name
                        ?? "Привет!"
                    )
                    .font(
                        .title2.weight(.semibold)
                    )

                    if let task = selectedTask {

                        HStack(spacing: 7) {

                            if let client = task.client {

                                Text(client.name)

                                Text("•")
                                    .foregroundStyle(Color.secondary)
                            }

                            Text(
                                "\(task.hourlyRate.formatted(.currency(code: "RUB")))/ч"
                            )
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.secondary)

                    } else {

                        Text(
                            "Выбери или добавь задачу в списке слева"
                        )
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                    }
                }
                .frame(
                    maxHeight: .infinity,
                    alignment: .center
                )

                Spacer(minLength: 12)

                if let task = selectedTask {

                    VStack(
                        alignment: .trailing,
                        spacing: 8
                    ) {

                        if task.isPaid {

                            Label(
                                "Оплачено",
                                systemImage: "checkmark.seal.fill"
                            )
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.green)

                            Button {

                                restoreTask(task)

                            } label: {

                                Label(
                                    "Вернуть в задачи",
                                    systemImage: "arrow.uturn.backward"
                                )
                            }
                            .buttonStyle(.bordered)

                        } else {

                            Button {

                                requestPayment(task)

                            } label: {

                                Label(
                                    "Отметить оплаченным",
                                    systemImage: "checkmark.circle"
                                )
                            }
                            .buttonStyle(.bordered)
                        }

                        Button {

                            exportSelectedTaskReport()

                        } label: {

                            Label(
                                "Экспорт отчёта",
                                systemImage: "arrow.down.doc"
                            )
                        }
                        .buttonStyle(.bordered)
                        .help(
                            "Экспортировать PDF-отчёт по выбранной задаче"
                        )
                    }
                }
            }
        }
        .padding(22)
        .background(
            Color.secondary.opacity(0.05),
            in: RoundedRectangle(
                cornerRadius: 16
            )
        )
    }


    // MARK: - Summary

    private var todaySummary: some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            HStack {

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {

                    Text(
                        selectedTask == nil
                        ? "Общая сводка"
                        : "За всё время • \(selectedTask!.name)"
                    )
                    .font(
                        .title3.weight(.semibold)
                    )

                    Text(
                        selectedTask == nil
                        ? "Все проекты"
                        : "Итоги по выбранному проекту"
                    )
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {

                DashboardStat(
                    title: "Время",
                    value: totalDurationFormatted,
                    icon: "clock"
                )

                DashboardStat(
                    title: "Заработано",
                    value: totalCost.formatted(
                        .currency(code: "RUB")
                    ),
                    icon: "rublesign.circle"
                )

                DashboardStat(
                    title: "Записей",
                    value: "\(dashboardEntries.count)",
                    icon: "list.bullet"
                )
            }
        }
    }

    private var recentEntries: some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            HStack {

                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {

                    Text(
                        selectedTask == nil
                        ? "Последние записи"
                        : "Последние записи • \(selectedTask!.name)"
                    )
                    .font(
                        .title3.weight(.semibold)
                    )

                    if selectedTask != nil {

                        Text(
                            "Показываются только записи выбранной задачи"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            Color.secondary
                        )
                    }
                }

                Spacer()

                Button("Все") {

                    showingHistory = true

                }
            }

            if recentEntriesList.isEmpty {

                Text(
                    selectedTask == nil
                    ? "Здесь появятся сохранённые рабочие сессии."
                    : "У выбранной задачи пока нет сохранённых сессий."
                )
                .font(.subheadline)
                .foregroundStyle(
                    Color.secondary
                )
                .padding(.vertical, 12)

            } else {

                VStack(spacing: 0) {

                    ForEach(recentEntriesList) { entry in

                        recentEntryRow(entry)

                        if entry.id != recentEntriesList.last?.id {

                            Divider()

                        }
                    }
                }
                .padding(14)
                .background(
                    Color.secondary.opacity(0.06),
                    in: RoundedRectangle(
                        cornerRadius: 14
                    )
                )
            }
        }
    }

    private func recentEntryRow(
        _ entry: TimeEntry
    ) -> some View {

        HStack(spacing: 12) {

            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                HStack(spacing: 6) {

                    Text(entry.taskName)
                        .font(
                            .body.weight(.medium)
                        )

                    if entry.task?.isPaid == true {

                        Text("Оплачено")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Color.green.opacity(0.10),
                                in: Capsule()
                            )
                    }
                }

                Text(
                    entry.clientName.isEmpty
                    ? formattedDateTime(entry.startDate)
                    : "\(entry.clientName) • \(formattedDateTime(entry.startDate))"
                )
                .font(.caption)
                .foregroundStyle(
                    Color.secondary
                )
            }

            Spacer()

            VStack(
                alignment: .trailing,
                spacing: 3
            ) {

                Text(entry.formattedDuration)
                    .font(
                        .system(
                            .body,
                            design: .monospaced
                        )
                    )

                Text(entry.formattedCost)
                    .font(.caption)
                    .foregroundStyle(
                        Color.secondary
                    )
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Selection

    private var selectedTask: WorkTask? {

        guard let selectedTaskID else {

            return nil

        }

        return tasks.first {

            $0.persistentModelID == selectedTaskID

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

    private func entriesForTask(
        _ task: WorkTask
    ) -> [TimeEntry] {

        entries.filter { entry in

            if let linkedTask = entry.task {

                return (
                    linkedTask.persistentModelID
                    == task.persistentModelID
                )

            }

            let clientMatches =
                entry.clientName
                == (task.client?.name ?? "")

            let taskMatches =
                entry.taskName
                == task.name

            return taskMatches && clientMatches
        }
    }

    private var dashboardEntries: [TimeEntry] {

        guard let task = selectedTask else {

            return entries

        }

        return entriesForTask(task)
    }

    private var todayEntries: [TimeEntry] {

        dashboardEntries.filter {

            Calendar.current.isDateInToday(
                $0.startDate
            )

        }
    }

    private var recentEntriesList: [TimeEntry] {

        Array(
            dashboardEntries.prefix(5)
        )
    }

    private var totalDuration: TimeInterval {

        dashboardEntries.reduce(0) {

            $0 + $1.duration

        }
    }

    private var totalCost: Double {

        dashboardEntries.reduce(0) {

            $0 + $1.cost

        }
    }

    private var totalDurationFormatted: String {

        let seconds = Int(totalDuration)

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        return "\(hours) ч \(minutes) мин"
    }

    private var todayDuration: TimeInterval {

        todayEntries.reduce(0) {

            $0 + $1.duration

        }
    }

    private var todayCost: Double {

        todayEntries.reduce(0) {

            $0 + $1.cost

        }
    }

    private var todayDurationFormatted: String {

        let seconds = Int(todayDuration)

        let hours =
            seconds / 3600

        let minutes =
            (seconds % 3600) / 60

        return "\(hours) ч \(minutes) мин"
    }

    // MARK: - Timer

    private func toggleTimer() {

        if timerService.isRunning {

            timerService.pause()

            return
        }

        if timerService.startDate != nil {

            guard !timerService.activeTaskID.isEmpty else {

                return

            }

            timerService.start(
                taskID: timerService.activeTaskID
            )

            return
        }

        guard let selectedTask else {

            NSSound.beep()

            return
        }

        guard !selectedTask.isPaid else {

            NSSound.beep()

            return
        }

        timerService.start(
            taskID:
                String(
                    describing:
                        selectedTask.persistentModelID
                )
        )
    }

    private func stopAndSave() {

        guard
            let result = timerService.stop()
        else {

            return

        }

        guard
            let task = tasks.first(
                where: {

                    String(
                        describing:
                            $0.persistentModelID
                    ) == result.taskID

                }
            )
        else {

            return

        }

        let entry = TimeEntry(
            startDate: result.startDate,
            endDate: result.endDate,
            taskName: task.name,
            clientName: task.client?.name ?? "",
            hourlyRate: task.hourlyRate
        )

        entry.task = task

        modelContext.insert(entry)

        try? modelContext.save()

        selectedTaskID =
            task.persistentModelID
    }

    // MARK: - Selection Persistence

    private func restoreSelectedTask() {

        guard selectedTaskID == nil else {

            return

        }

        let stored =
            UserDefaults.standard.string(
                forKey: "selectedTaskID"
            )

        guard let stored else {

            return

        }

        guard
            let task = tasks.first(
                where: {

                    String(
                        describing:
                            $0.persistentModelID
                    ) == stored

                }
            )
        else {

            UserDefaults.standard.removeObject(
                forKey: "selectedTaskID"
            )

            return
        }

        selectedTaskID =
            task.persistentModelID
    }

    private func saveSelectedTask() {

        guard let selectedTaskID else {

            UserDefaults.standard.removeObject(
                forKey: "selectedTaskID"
            )

            return
        }

        guard
            tasks.contains(
                where: {

                    $0.persistentModelID
                    == selectedTaskID

                }
            )
        else {

            UserDefaults.standard.removeObject(
                forKey: "selectedTaskID"
            )

            return
        }

        UserDefaults.standard.set(
            String(
                describing:
                    selectedTaskID
            ),
            forKey: "selectedTaskID"
        )
    }

    private func deleteTask(
        _ task: WorkTask
    ) {

        let taskID =
            String(
                describing:
                    task.persistentModelID
            )

        // Гарантируем постоянный UUID проекта до удаления.
        if task.id == nil {
            task.id = UUID()
        }

        // Запоминаем удаление, чтобы синхронизация
        // не восстановила проект из старого JSON.
        if let id = task.id {
            SyncService.recordTaskDeletion(id)
        }

        if timerService.activeTaskID == taskID {

            timerService.cancelSession()

        }

        if selectedTaskID ==
            task.persistentModelID {

            selectedTaskID = nil
        }

        modelContext.delete(task)

        try? modelContext.save()

        if selectedTaskID == nil {

            UserDefaults.standard.removeObject(
                forKey: "selectedTaskID"
            )
        }
    }

    // MARK: - Report

    private var reportFilename: String {

        guard let task = selectedTask else {

            return "Time-Tracker-Report.pdf"

        }

        let safeName =
            task.name
                .replacingOccurrences(
                    of: "/",
                    with: "-"
                )
                .replacingOccurrences(
                    of: ":",
                    with: "-"
                )

        return "\(safeName)-report.pdf"
    }

    private func exportSelectedTaskReport() {

        guard let task = selectedTask else {

            return

        }

        let taskEntries =
            entriesForTask(task)

        let data =
            DashboardReportRenderer.makePDF(
                task: task,
                entries: taskEntries
            )

        reportDocument =
            DashboardReportFileDocument(
                data: data
            )

        showingReportExporter = true
    }

    private func currentCost(
        for task: WorkTask
    ) -> Double {

        timerService.elapsedTime
        / 3600
        * task.hourlyRate
    }

    // MARK: - Formatting

    private func formattedDuration(
        _ duration: TimeInterval
    ) -> String {

        let seconds = Int(duration)

        let hours =
            seconds / 3600

        let minutes =
            (seconds % 3600) / 60

        let remainingSeconds =
            seconds % 60

        return String(
            format:
                "%02d:%02d:%02d",
            hours,
            minutes,
            remainingSeconds
        )
    }

    private func formattedDateTime(
        _ date: Date
    ) -> String {

        date.formatted(
            .dateTime
                .day()
                .month()
                .hour()
                .minute()
        )
    }
}

// MARK: - Dashboard Stat

struct DashboardStat: View {

    let title: String
    let value: String
    let icon: String

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 7
        ) {

            Image(systemName: icon)
                .foregroundStyle(
                    Color.secondary
                )

            Text(title)
                .font(.caption)
                .foregroundStyle(
                    Color.secondary
                )

            Text(value)
                .font(
                    .title3.weight(.medium)
                )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(16)
        .background(
            Color.secondary.opacity(0.07),
            in: RoundedRectangle(
                cornerRadius: 14
            )
        )
    }
}

// MARK: - New Task

struct NewTaskView: View {

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.modelContext)
    private var modelContext

    @Query(sort: \Client.name)
    private var clients: [Client]

    @State private var name = ""
    @State private var selectedClient: Client?
    @State private var rateText = ""
    @State private var showingNewClient = false

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            editorHeader(
                title: "Новая задача",
                subtitle:
                    "Создайте рабочую задачу и укажите её ставку."
            )

            Divider()

            VStack(
                alignment: .leading,
                spacing: 18
            ) {

                editorField(
                    title: "Название",
                    icon: "textformat"
                ) {

                    TextField(
                        "Например, презентация для клиента",
                        text: $name
                    )
                    .textFieldStyle(.roundedBorder)
                }

                editorField(
                    title: "Клиент",
                    icon: "person"
                ) {

                    HStack(
                        alignment: .center,
                        spacing: 7
                    ) {

                        Menu {

                            Button("Без клиента") {

                                selectedClient = nil

                            }

                            if !clients.isEmpty {

                                Divider()

                                ForEach(clients) { client in

                                    Button {

                                        selectedClient = client

                                    } label: {

                                        HStack {

                                            Text(client.name)

                                            if selectedClient?
                                                .persistentModelID
                                                == client.persistentModelID {

                                                Spacer()

                                                Image(
                                                    systemName:
                                                        "checkmark"
                                                )
                                            }
                                        }
                                    }
                                }
                            }

                        } label: {

                            HStack(spacing: 8) {

                                Text(
                                    selectedClient?.name
                                    ?? "Без клиента"
                                )
                                .lineLimit(1)
                                .truncationMode(.tail)

                                Spacer(minLength: 4)

                                Image(
                                    systemName:
                                        "chevron.up.chevron.down"
                                )
                                .font(
                                    .system(
                                        size: 10,
                                        weight: .medium
                                    )
                                )
                                .foregroundStyle(
                                    Color.secondary
                                )
                            }
                            .padding(.horizontal, 9)
                            .frame(
                                width: 300,
                                height: 28
                            )
                            .contentShape(Rectangle())
                        }
                        .menuStyle(
                            .borderlessButton
                        )
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                        .frame(
                            width: 300,
                            height: 28
                        )
                        .background(
                            RoundedRectangle(
                                cornerRadius: 7
                            )
                            .fill(
                                Color.secondary
                                    .opacity(0.06)
                            )
                        )
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 7
                            )
                            .stroke(
                                Color.secondary.opacity(0.22),
                                lineWidth: 1
                            )
                        )

                        Button {

                            showingNewClient = true

                        } label: {

                            Image(systemName: "plus")
                                .font(
                                    .system(
                                        size: 11,
                                        weight: .semibold
                                    )
                                )
                                .frame(
                                    width: 28,
                                    height: 28
                                )
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(
                                cornerRadius: 7
                            )
                            .fill(
                                Color.secondary
                                    .opacity(0.06)
                            )
                        )
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: 7
                            )
                            .stroke(
                                Color.secondary.opacity(0.22),
                                lineWidth: 1
                            )
                        )
                        .frame(
                            width: 28,
                            height: 28
                        )
                        .contentShape(Rectangle())
                        .help("Добавить нового клиента")
                    }
                    .frame(
                        width: 335,
                        height: 28,
                        alignment: .leading
                    )
                }

                editorField(
                    title: "Ставка",
                    icon: "rublesign.circle"
                ) {

                    HStack {

                        TextField(
                            "0",
                            text: $rateText
                        )
                        .textFieldStyle(.roundedBorder)

                        Text("₽ / час")
                            .foregroundStyle(
                                Color.secondary
                            )
                    }
                }

                Spacer()
            }
            .padding(22)

            Divider()

            editorButtons(
                cancelTitle: "Отмена",
                confirmTitle: "Создать",
                confirmDisabled:
                    name
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .isEmpty
            ) {

                dismiss()

            } confirmAction: {

                createTask()

            }
        }
        .frame(
            width: 520,
            height: 390
        )
        .onAppear {

            if rateText.isEmpty {

                rateText =
                    AppSettings.shared
                        .defaultHourlyRate
                        .formatted(.number)
            }
        }
        .onChange(
            of: selectedClient?.persistentModelID
        ) {

            updateRateFromSelectedClient()

        }
        .sheet(
            isPresented: $showingNewClient
        ) {

            ClientEditorView(
                title: "Новый клиент"
            ) { client in

                selectedClient = client

            }
        }
    }

    private func updateRateFromSelectedClient() {

        if let client = selectedClient {

            rateText =
                String(
                    format: "%.2f",
                    client.hourlyRate
                )

        } else {

            rateText =
                String(
                    format: "%.2f",
                    AppSettings.shared
                        .defaultHourlyRate
                )
        }
    }

    private func createTask() {

        let normalized =
            normalizeRateText(rateText)

        let rate =
            Double(normalized)
            ?? AppSettings.shared.defaultHourlyRate

        let task = WorkTask(
            name:
                name.trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                ),
            client: selectedClient,
            hourlyRate: max(0, rate)
        )

        modelContext.insert(task)

        try? modelContext.save()

        dismiss()
    }

    private func normalizeRateText(
        _ value: String
    ) -> String {

        value
            .replacingOccurrences(
                of: "\u{00A0}",
                with: ""
            )
            .replacingOccurrences(
                of: "\u{202F}",
                with: ""
            )
            .replacingOccurrences(
                of: " ",
                with: ""
            )
            .replacingOccurrences(
                of: ",",
                with: "."
            )
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
    }
}

// MARK: - Edit Task

struct EditTaskView: View {

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.modelContext)
    private var modelContext

    @Query(sort: \Client.name)
    private var clients: [Client]

    let task: WorkTask

    @State private var name: String
    @State private var selectedClient: Client?
    @State private var rateText: String

    init(task: WorkTask) {

        self.task = task

        _name = State(
            initialValue: task.name
        )

        _selectedClient = State(
            initialValue: task.client
        )

        _rateText = State(
            initialValue:
                String(
                    format: "%.2f",
                    task.hourlyRate
                )
        )
    }

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            editorHeader(
                title: "Изменить задачу",
                subtitle:
                    "Измените название, клиента или ставку."
            )

            Divider()

            VStack(
                alignment: .leading,
                spacing: 18
            ) {

                editorField(
                    title: "Название",
                    icon: "textformat"
                ) {

                    TextField(
                        "Название задачи",
                        text: $name
                    )
                    .textFieldStyle(.roundedBorder)
                }

                editorField(
                    title: "Клиент",
                    icon: "person"
                ) {

                    Picker(
                        "",
                        selection: $selectedClient
                    ) {

                        Text("Без клиента")
                            .tag(nil as Client?)

                        ForEach(clients) { client in

                            Text(client.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .tag(Optional(client))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(
                        height: 28,
                        alignment: .leading
                    )
                    .frame(maxWidth: .infinity)
                }

                editorField(
                    title: "Ставка",
                    icon: "rublesign.circle"
                ) {

                    HStack {

                        TextField(
                            "0",
                            text: $rateText
                        )
                        .textFieldStyle(.roundedBorder)

                        Text("₽ / час")
                            .foregroundStyle(
                                Color.secondary
                            )
                    }
                }

                Spacer()
            }
            .padding(22)

            Divider()

            editorButtons(
                cancelTitle: "Отмена",
                confirmTitle: "Сохранить",
                confirmDisabled:
                    name
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .isEmpty
            ) {

                dismiss()

            } confirmAction: {

                save()

            }
        }
        .frame(
            width: 520,
            height: 390
        )
        .onChange(
            of: selectedClient?.persistentModelID
        ) {

            updateRateFromSelectedClient()

        }
    }

    private func updateRateFromSelectedClient() {

        if let client = selectedClient {

            rateText =
                String(
                    format: "%.2f",
                    client.hourlyRate
                )

        } else {

            rateText =
                String(
                    format: "%.2f",
                    AppSettings.shared
                        .defaultHourlyRate
                )
        }
    }

    private func save() {

        let normalized =
            normalizeRateText(rateText)

        task.name =
            name.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        task.client = selectedClient

        task.hourlyRate =
            max(
                0,
                Double(normalized) ?? 0
            )

        task.updatedAt = Date()

        try? modelContext.save()

        dismiss()
    }

    private func normalizeRateText(
        _ value: String
    ) -> String {

        value
            .replacingOccurrences(
                of: "\u{00A0}",
                with: ""
            )
            .replacingOccurrences(
                of: "\u{202F}",
                with: ""
            )
            .replacingOccurrences(
                of: " ",
                with: ""
            )
            .replacingOccurrences(
                of: ",",
                with: "."
            )
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
    }
}

// MARK: - Editor Components

private func editorHeader(
    title: String,
    subtitle: String
) -> some View {

    HStack(spacing: 12) {

        ZStack {

            RoundedRectangle(
                cornerRadius: 10
            )
            .fill(
                Color.accentColor.opacity(0.12)
            )

            Image(
                systemName: "checklist"
            )
            .foregroundStyle(
                Color.accentColor
            )
        }
        .frame(
            width: 38,
            height: 38
        )

        VStack(
            alignment: .leading,
            spacing: 3
        ) {

            Text(title)
                .font(
                    .title3.weight(.semibold)
                )

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(
                    Color.secondary
                )
        }

        Spacer()
    }
    .padding(20)
}

@ViewBuilder
private func editorField<Content: View>(
    title: String,
    icon: String,
    @ViewBuilder content: () -> Content
) -> some View {

    VStack(
        alignment: .leading,
        spacing: 8
    ) {

        Label(
            title,
            systemImage: icon
        )
        .font(
            .caption.weight(.medium)
        )
        .foregroundStyle(
            Color.secondary
        )

        content()
    }
}

private func editorButtons(
    cancelTitle: String,
    confirmTitle: String,
    confirmDisabled: Bool,
    cancelAction: @escaping () -> Void,
    confirmAction: @escaping () -> Void
) -> some View {

    HStack {

        Button(cancelTitle) {

            cancelAction()

        }
        .keyboardShortcut(.cancelAction)

        Spacer()

        Button(confirmTitle) {

            confirmAction()

        }
        .buttonStyle(.borderedProminent)
        .disabled(confirmDisabled)
        .keyboardShortcut(.defaultAction)
    }
    .padding(16)
}

// MARK: - PDF

struct DashboardReportFileDocument: FileDocument {

    static var readableContentTypes: [UTType] {

        [.pdf]

    }

    var data: Data

    init(data: Data) {

        self.data = data

    }

    init(
        configuration: ReadConfiguration
    ) throws {

        self.data =
            configuration.file.regularFileContents
            ?? Data()
    }

    func fileWrapper(
        configuration: WriteConfiguration
    ) throws -> FileWrapper {

        FileWrapper(
            regularFileWithContents: data
        )
    }
}

enum DashboardReportRenderer {

    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 40
    private static let bottomMargin: CGFloat = 55

    private static let locale = Locale(identifier: "ru_RU")

    // MARK: - Text

    private static func drawText(
        _ text: String,
        at point: CGPoint,
        attributes: [NSAttributedString.Key: Any],
        in context: CGContext
    ) {

        let attributedString = NSAttributedString(
            string: text,
            attributes: attributes
        )

        let line = CTLineCreateWithAttributedString(
            attributedString
        )

        context.saveGState()

        context.textMatrix = .identity
        context.textPosition = point

        CTLineDraw(line, context)

        context.restoreGState()
    }

    // MARK: - Graphics

    private static func drawRoundedRect(
        _ rect: CGRect,
        radius: CGFloat,
        color: NSColor,
        in context: CGContext
    ) {

        let path = CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    private static func drawLine(
        from start: CGPoint,
        to end: CGPoint,
        color: NSColor,
        width: CGFloat = 1,
        in context: CGContext
    ) {

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)

        context.move(to: start)
        context.addLine(to: end)

        context.strokePath()
    }

    private static func drawDot(
        color: NSColor,
        at point: CGPoint,
        size: CGFloat,
        in context: CGContext
    ) {

        let rect = CGRect(
            x: point.x,
            y: point.y,
            width: size,
            height: size
        )

        context.setFillColor(color.cgColor)
        context.fillEllipse(in: rect)
    }

    // MARK: - Formatting

    private static func currency(
        _ value: Double
    ) -> String {

        value.formatted(
            .currency(code: "RUB")
                .locale(locale)
        )
    }

    private static func makeDateFormatter() -> DateFormatter {

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .current
        formatter.dateFormat = "dd.MM.yyyy"

        return formatter
    }

    private static func makeTimeFormatter() -> DateFormatter {

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"

        return formatter
    }

    private static func formattedGeneratedDate() -> String {

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = .current
        formatter.dateFormat = "d MMMM yyyy, HH:mm"

        return formatter.string(from: Date())
    }

    // MARK: - Entry Layout

    private struct EntryLayout {
        let entry: TimeEntry
        let index: Int
        let commentLines: [CTLine]
        let height: CGFloat
    }

    private static func makeCommentLines(
        _ comment: String
    ) -> [CTLine] {

        let trimmedComment = comment.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedComment.isEmpty else {
            return []
        }

        let font = NSFont.systemFont(ofSize: 8)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(
                calibratedWhite: 0.43,
                alpha: 1
            )
        ]

        let attributedString = NSAttributedString(
            string: trimmedComment,
            attributes: attributes
        )

        let typesetter = CTTypesetterCreateWithAttributedString(
            attributedString
        )

        var lines: [CTLine] = []
        var position = 0

        while position < attributedString.length {

            let suggestedLength = CTTypesetterSuggestLineBreak(
                typesetter,
                position,
                495
            )

            let lineLength = max(1, suggestedLength)

            let line = CTTypesetterCreateLine(
                typesetter,
                CFRange(
                    location: position,
                    length: lineLength
                )
            )

            lines.append(line)
            position += lineLength
        }

        return lines
    }

    private static func makeEntryLayout(
        entry: TimeEntry,
        index: Int
    ) -> EntryLayout {

        let commentLines = makeCommentLines(entry.note)

        let commentHeight: CGFloat = commentLines.isEmpty
            ? 0
            : CGFloat(commentLines.count) * 11 + 3

        return EntryLayout(
            entry: entry,
            index: index,
            commentLines: commentLines,
            height: 24 + commentHeight
        )
    }

    // MARK: - Attributes

    private static var titleAttributes: [NSAttributedString.Key: Any] {

        [
            .font: NSFont.systemFont(
                ofSize: 25,
                weight: .bold
            ),
            .foregroundColor: NSColor.white
        ]
    }

    private static var subtitleAttributes: [NSAttributedString.Key: Any] {

        [
            .font: NSFont.systemFont(
                ofSize: 10,
                weight: .medium
            ),
            .foregroundColor: NSColor(
                calibratedWhite: 0.82,
                alpha: 1
            )
        ]
    }

    private static var sectionAttributes: [NSAttributedString.Key: Any] {

        [
            .font: NSFont.systemFont(
                ofSize: 9,
                weight: .semibold
            ),
            .foregroundColor: NSColor(
                calibratedWhite: 0.42,
                alpha: 1
            )
        ]
    }

    private static var bodyAttributes: [NSAttributedString.Key: Any] {

        [
            .font: NSFont.systemFont(
                ofSize: 9,
                weight: .regular
            ),
            .foregroundColor: NSColor(
                calibratedWhite: 0.16,
                alpha: 1
            )
        ]
    }

    private static var footerAttributes: [NSAttributedString.Key: Any] {

        [
            .font: NSFont.systemFont(
                ofSize: 8
            ),
            .foregroundColor: NSColor(
                calibratedWhite: 0.55,
                alpha: 1
            )
        ]
    }

    // MARK: - Client Color

    private static func clientColor(
        for task: WorkTask
    ) -> NSColor {

        guard let client = task.client else {
            return NSColor.systemGray
        }

        let color = NSColor(
            ClientColorStore.shared.color(for: client)
        )

        return color.usingColorSpace(.deviceRGB)
            ?? NSColor.systemBlue
    }

    // MARK: - PDF

    static func makePDF(
        task: WorkTask,
        entries: [TimeEntry]
    ) -> Data {

        let data = NSMutableData()

        guard
            let consumer = CGDataConsumer(data: data),
            let context = CGContext(
                consumer: consumer,
                mediaBox: nil,
                nil
            )
        else {
            return Data()
        }

        let sortedEntries = entries.sorted {
            $0.startDate > $1.startDate
        }

        let totalDuration = sortedEntries.reduce(0.0) {
            $0 + $1.duration
        }

        let totalCost = sortedEntries.reduce(0.0) {
            $0 + $1.cost
        }

        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60

        let durationText = "\(hours) ч \(minutes) мин"

        let firstRowsY = pageHeight - 345
        let nextRowsY = pageHeight - 130

        let firstAvailableHeight =
            firstRowsY - bottomMargin

        let nextAvailableHeight =
            nextRowsY - bottomMargin

        // Prepare entries

        let layouts = sortedEntries.enumerated().map {
            index, entry in

            makeEntryLayout(
                entry: entry,
                index: index
            )
        }

        // Distribute entries across pages

        var pages: [[EntryLayout]] = []
        var currentPage: [EntryLayout] = []

        var currentAvailableHeight = firstAvailableHeight

        for layout in layouts {

            if layout.height > currentAvailableHeight,
               !currentPage.isEmpty {

                pages.append(currentPage)
                currentPage = []

                currentAvailableHeight = nextAvailableHeight
            }

            currentPage.append(layout)
            currentAvailableHeight -= layout.height
        }

        if !currentPage.isEmpty {
            pages.append(currentPage)
        }

        if pages.isEmpty {
            pages.append([])
        }

        let pageCount = pages.count

        var mediaBox = CGRect(
            x: 0,
            y: 0,
            width: pageWidth,
            height: pageHeight
        )

        let accentColor = clientColor(for: task)

        for pageIndex in 0..<pageCount {

            context.beginPage(mediaBox: &mediaBox)

            context.setFillColor(NSColor.white.cgColor)

            context.fill(
                CGRect(
                    x: 0,
                    y: 0,
                    width: pageWidth,
                    height: pageHeight
                )
            )

            if pageIndex == 0 {

                drawFirstPageHeader(
                    task: task,
                    durationText: durationText,
                    entryCount: sortedEntries.count,
                    totalCost: totalCost,
                    accentColor: accentColor,
                    in: context
                )
            }

            let headerY: CGFloat =
                pageIndex == 0
                ? pageHeight - 320
                : pageHeight - 95

            drawTableHeader(
                at: headerY,
                in: context
            )

            var currentY: CGFloat =
                pageIndex == 0
                ? firstRowsY
                : nextRowsY

            let pageEntries = pages[pageIndex]

            if pageEntries.isEmpty {

                drawText(
                    "Записей пока нет",
                    at: CGPoint(
                        x: margin,
                        y: currentY - 4
                    ),
                    attributes: bodyAttributes,
                    in: context
                )

            } else {

                for layout in pageEntries {

                    drawEntryRow(
                        layout.entry,
                        index: layout.index,
                        y: currentY,
                        accentColor: accentColor,
                        commentLines: layout.commentLines,
                        blockHeight: layout.height,
                        in: context
                    )

                    currentY -= layout.height
                }
            }

            drawFooter(
                page: pageIndex + 1,
                totalPages: pageCount,
                in: context
            )

            context.endPDFPage()
        }

        context.closePDF()

        return data as Data
    }

    // MARK: - First Page Header

    private static func drawFirstPageHeader(
        task: WorkTask,
        durationText: String,
        entryCount: Int,
        totalCost: Double,
        accentColor: NSColor,
        in context: CGContext
    ) {

        // Main dark header

        context.setFillColor(
            NSColor(
                calibratedRed: 0.105,
                green: 0.12,
                blue: 0.15,
                alpha: 1
            ).cgColor
        )

        context.fill(
            CGRect(
                x: 0,
                y: pageHeight - 170,
                width: pageWidth,
                height: 170
            )
        )

        // Accent stripe

        context.setFillColor(accentColor.cgColor)

        context.fill(
            CGRect(
                x: 0,
                y: pageHeight - 170,
                width: 6,
                height: 170
            )
        )

        drawText(
            "ПРОЕКТНЫЙ ОТЧЁТ",
            at: CGPoint(
                x: margin,
                y: pageHeight - 48
            ),
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: 8,
                    weight: .bold
                ),
                .foregroundColor: NSColor(
                    calibratedWhite: 0.65,
                    alpha: 1
                )
            ],
            in: context
        )

        let title = String(task.name.prefix(55))

        drawText(
            title,
            at: CGPoint(
                x: margin,
                y: pageHeight - 83
            ),
            attributes: titleAttributes,
            in: context
        )

        drawText(
            "Рабочее время и стоимость выполненных работ",
            at: CGPoint(
                x: margin,
                y: pageHeight - 105
            ),
            attributes: subtitleAttributes,
            in: context
        )

        // Client indicator

        drawDot(
            color: accentColor,
            at: CGPoint(
                x: margin,
                y: pageHeight - 135
            ),
            size: 8,
            in: context
        )

        let clientName =
            task.client?.name ?? "Без клиента"

        drawText(
            clientName,
            at: CGPoint(
                x: margin + 15,
                y: pageHeight - 135
            ),
            attributes: subtitleAttributes,
            in: context
        )

        let rateText =
            "Ставка: \(currency(task.hourlyRate))/ч"

        drawText(
            rateText,
            at: CGPoint(
                x: 300,
                y: pageHeight - 135
            ),
            attributes: subtitleAttributes,
            in: context
        )

        drawText(
            "Сформировано: \(formattedGeneratedDate())",
            at: CGPoint(
                x: margin,
                y: pageHeight - 155
            ),
            attributes: [
                .font: NSFont.systemFont(ofSize: 8),
                .foregroundColor: NSColor(
                    calibratedWhite: 0.62,
                    alpha: 1
                )
            ],
            in: context
        )

        // Summary cards

        let cardY = pageHeight - 260
        let cardHeight: CGFloat = 64
        let cardGap: CGFloat = 12

        let cardWidth =
            (pageWidth - margin * 2 - cardGap * 2) / 3

        drawSummaryCard(
            title: "ОБЩЕЕ ВРЕМЯ",
            value: durationText,
            x: margin,
            y: cardY,
            width: cardWidth,
            height: cardHeight,
            accentColor: accentColor,
            in: context
        )

        drawSummaryCard(
            title: "ЗАПИСЕЙ",
            value: "\(entryCount)",
            x: margin + cardWidth + cardGap,
            y: cardY,
            width: cardWidth,
            height: cardHeight,
            accentColor: accentColor,
            in: context
        )

        drawSummaryCard(
            title: "ИТОГО",
            value: currency(totalCost),
            x: margin + (cardWidth + cardGap) * 2,
            y: cardY,
            width: cardWidth,
            height: cardHeight,
            accentColor: accentColor,
            in: context
        )
    }

    // MARK: - Summary Card

    private static func drawSummaryCard(
        title: String,
        value: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        accentColor: NSColor,
        in context: CGContext
    ) {

        drawRoundedRect(
            CGRect(
                x: x,
                y: y,
                width: width,
                height: height
            ),
            radius: 9,
            color: NSColor(
                calibratedWhite: 0.955,
                alpha: 1
            ),
            in: context
        )

        context.setFillColor(
            accentColor.cgColor
        )

        context.fill(
            CGRect(
                x: x,
                y: y,
                width: 3,
                height: height
            )
        )

        drawText(
            title,
            at: CGPoint(
                x: x + 13,
                y: y + height - 19
            ),
            attributes: sectionAttributes,
            in: context
        )

        drawText(
            value,
            at: CGPoint(
                x: x + 13,
                y: y + 18
            ),
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: 15,
                    weight: .semibold
                ),
                .foregroundColor: NSColor(
                    calibratedWhite: 0.12,
                    alpha: 1
                )
            ],
            in: context
        )
    }

    // MARK: - Table Header

    private static func drawTableHeader(
        at y: CGFloat,
        in context: CGContext
    ) {

        drawText(
            "ДАТА",
            at: CGPoint(
                x: 50,
                y: y
            ),
            attributes: sectionAttributes,
            in: context
        )

        drawText(
            "НАЧАЛО",
            at: CGPoint(
                x: 165,
                y: y
            ),
            attributes: sectionAttributes,
            in: context
        )

        drawText(
            "КОНЕЦ",
            at: CGPoint(
                x: 245,
                y: y
            ),
            attributes: sectionAttributes,
            in: context
        )

        drawText(
            "ВРЕМЯ",
            at: CGPoint(
                x: 330,
                y: y
            ),
            attributes: sectionAttributes,
            in: context
        )

        drawText(
            "СУММА",
            at: CGPoint(
                x: 430,
                y: y
            ),
            attributes: sectionAttributes,
            in: context
        )

        drawLine(
            from: CGPoint(
                x: margin,
                y: y - 12
            ),
            to: CGPoint(
                x: pageWidth - margin,
                y: y - 12
            ),
            color: NSColor(
                calibratedWhite: 0.82,
                alpha: 1
            ),
            width: 0.8,
            in: context
        )
    }

    // MARK: - Entry Row

    private static func drawEntryRow(
        _ entry: TimeEntry,
        index: Int,
        y: CGFloat,
        accentColor: NSColor,
        commentLines: [CTLine],
        blockHeight: CGFloat,
        in context: CGContext
    ) {

        let rowRect = CGRect(
            x: 32,
            y: y + 14 - blockHeight,
            width: pageWidth - 64,
            height: blockHeight - 2
        )

        if index % 2 == 0 {

            drawRoundedRect(
                rowRect,
                radius: 4,
                color: NSColor(
                    calibratedWhite: 0.965,
                    alpha: 1
                ),
                in: context
            )
        }

        // Client color indicator

        drawDot(
            color: accentColor,
            at: CGPoint(
                x: 36,
                y: y - 1
            ),
            size: 6,
            in: context
        )

        let dateFormatter = makeDateFormatter()
        let timeFormatter = makeTimeFormatter()

        // Date

        drawText(
            dateFormatter.string(from: entry.startDate),
            at: CGPoint(
                x: 50,
                y: y
            ),
            attributes: bodyAttributes,
            in: context
        )

        // Start time

        drawText(
            timeFormatter.string(from: entry.startDate),
            at: CGPoint(
                x: 165,
                y: y
            ),
            attributes: bodyAttributes,
            in: context
        )

        // End time

        drawText(
            timeFormatter.string(from: entry.endDate),
            at: CGPoint(
                x: 245,
                y: y
            ),
            attributes: bodyAttributes,
            in: context
        )

        // Duration

        drawText(
            entry.formattedDuration,
            at: CGPoint(
                x: 330,
                y: y
            ),
            attributes: bodyAttributes,
            in: context
        )

        // Cost

        drawText(
            currency(entry.cost),
            at: CGPoint(
                x: 430,
                y: y
            ),
            attributes: bodyAttributes,
            in: context
        )

        // Comment

        for (lineIndex, line) in commentLines.enumerated() {

            context.saveGState()

            context.textMatrix = .identity

            context.textPosition = CGPoint(
                x: 50,
                y: y - 12 - CGFloat(lineIndex) * 11
            )

            CTLineDraw(line, context)

            context.restoreGState()
        }
    }

    // MARK: - Footer

    private static func drawFooter(
        page: Int,
        totalPages: Int,
        in context: CGContext
    ) {

        drawLine(
            from: CGPoint(
                x: margin,
                y: 43
            ),
            to: CGPoint(
                x: pageWidth - margin,
                y: 43
            ),
            color: NSColor(
                calibratedWhite: 0.87,
                alpha: 1
            ),
            width: 0.7,
            in: context
        )

        drawText(
            "se:cu tracker • Проектный отчёт",
            at: CGPoint(
                x: margin,
                y: 27
            ),
            attributes: footerAttributes,
            in: context
        )

        drawText(
            "\(page) / \(totalPages)",
            at: CGPoint(
                x: pageWidth - margin - 30,
                y: 27
            ),
            attributes: footerAttributes,
            in: context
        )
    }
}
