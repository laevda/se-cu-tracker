
import Foundation
import SwiftData

struct SyncResult {
    let clientsCount: Int
    let tasksCount: Int
    let entriesCount: Int
    let fileURL: URL
}

@MainActor
final class SyncService {

    private let fileName = "sync-data.json"

    // MARK: - Удалённые проекты

    private static let pendingTaskDeletionsKey =
        "SecuTracker.PendingTaskDeletions"

    static func recordTaskDeletion(_ id: UUID) {
        var ids = pendingTaskDeletionIDs()
        ids.insert(id)

        UserDefaults.standard.set(
            ids.map { $0.uuidString },
            forKey: pendingTaskDeletionsKey
        )
    }

    private static func pendingTaskDeletionIDs() -> Set<UUID> {
        let stored = UserDefaults.standard.stringArray(
            forKey: pendingTaskDeletionsKey
        ) ?? []

        return Set(stored.compactMap { UUID(uuidString: $0) })
    }

    private static func clearPendingTaskDeletions(
        _ ids: Set<UUID>
    ) {
        var pending = pendingTaskDeletionIDs()
        pending.subtract(ids)

        UserDefaults.standard.set(
            pending.map { $0.uuidString },
            forKey: pendingTaskDeletionsKey
        )
    }

    // MARK: - Удалённые записи времени

    private static let pendingEntryDeletionsKey =
        "SecuTracker.PendingEntryDeletions"

    static func recordEntryDeletion(_ id: UUID) {
        var ids = pendingEntryDeletionIDs()
        ids.insert(id)

        UserDefaults.standard.set(
            ids.map { $0.uuidString },
            forKey: pendingEntryDeletionsKey
        )
    }

    private static func pendingEntryDeletionIDs() -> Set<UUID> {
        let stored = UserDefaults.standard.stringArray(
            forKey: pendingEntryDeletionsKey
        ) ?? []

        return Set(stored.compactMap { UUID(uuidString: $0) })
    }

    private static func clearPendingEntryDeletions(
        _ ids: Set<UUID>
    ) {
        var pending = pendingEntryDeletionIDs()
        pending.subtract(ids)

        UserDefaults.standard.set(
            pending.map { $0.uuidString },
            forKey: pendingEntryDeletionsKey
        )
    }

    // MARK: - Основная синхронизация

    func synchronize(
        context: ModelContext,
        folderURL: URL
    ) throws -> SyncResult {

        try context.save()

        let fileURL = folderURL.appendingPathComponent(fileName)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let emptyDocument = SyncDocument()
            let data = try makeEncoder().encode(emptyDocument)
            try data.write(to: fileURL, options: .atomic)
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        var result: SyncResult?

        coordinator.coordinate(
            writingItemAt: fileURL,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedURL in

            do {
                let data = try Data(contentsOf: coordinatedURL)

                let remoteDocument = try makeDecoder().decode(
                    SyncDocument.self,
                    from: data
                )

                let pendingTaskDeletions =
                    Self.pendingTaskDeletionIDs()

                let deletedTaskIDs = Set(
                    remoteDocument.deletedTaskIDs
                ).union(pendingTaskDeletions)

                let pendingEntryDeletions =
                    Self.pendingEntryDeletionIDs()

                let deletedEntryIDs = Set(
                    remoteDocument.deletedEntryIDs
                ).union(pendingEntryDeletions)

                try merge(
                    remoteDocument,
                    deletedTaskIDs: deletedTaskIDs,
                    deletedEntryIDs: deletedEntryIDs,
                    into: context
                )

                let clientsBefore = try context.fetch(
                    FetchDescriptor<Client>()
                ).count

                let tasksBefore = try context.fetch(
                    FetchDescriptor<WorkTask>()
                ).count

                let entriesBefore = try context.fetch(
                    FetchDescriptor<TimeEntry>()
                ).count

                print("")
                print("========== SYNC DIAGNOSTICS ==========")
                print("До очистки:")
                print("Клиентов: \(clientsBefore)")
                print("Проектов: \(tasksBefore)")
                print("Записей: \(entriesBefore)")

                try removeDuplicates(in: context)
                try context.save()

                let clientsAfter = try context.fetch(
                    FetchDescriptor<Client>()
                ).count

                let tasksAfter = try context.fetch(
                    FetchDescriptor<WorkTask>()
                ).count

                let entriesAfter = try context.fetch(
                    FetchDescriptor<TimeEntry>()
                ).count

                print("")
                print("После очистки и сохранения:")
                print("Клиентов: \(clientsAfter)")
                print("Проектов: \(tasksAfter)")
                print("Записей: \(entriesAfter)")

                print("")
                print("Удалено:")
                print("Клиентов: \(clientsBefore - clientsAfter)")
                print("Проектов: \(tasksBefore - tasksAfter)")
                print("Записей: \(entriesBefore - entriesAfter)")
                print("======================================")
                print("")

                // Дедупликация могла добавить новые UUID
                // в очередь удалений. Забираем её после очистки.

                let allPendingEntryDeletions =
                    Self.pendingEntryDeletionIDs()

                let allDeletedEntryIDs = deletedEntryIDs.union(
                    allPendingEntryDeletions
                )

                let mergedDocument = try makeDocument(
                    from: context,
                    deletedTaskIDs: deletedTaskIDs,
                    deletedEntryIDs: allDeletedEntryIDs
                )

                let mergedData = try makeEncoder().encode(
                    mergedDocument
                )

                try mergedData.write(
                    to: coordinatedURL,
                    options: .atomic
                )

                // Локальные очереди очищаются только после
                // успешной записи общего файла.
                // Tombstone остаётся в JSON постоянно.

                Self.clearPendingTaskDeletions(
                    pendingTaskDeletions
                )

                Self.clearPendingEntryDeletions(
                    allPendingEntryDeletions
                )

                result = SyncResult(
                    clientsCount: mergedDocument.clients.count,
                    tasksCount: mergedDocument.tasks.count,
                    entriesCount: mergedDocument.entries.count,
                    fileURL: coordinatedURL
                )

            } catch {
                operationError = error
            }
        }

        if let coordinationError {
            throw SyncServiceError.coordination(
                coordinationError.localizedDescription
            )
        }

        if let operationError {
            throw operationError
        }

        guard let result else {
            throw SyncServiceError.unknown
        }

        return result
    }

    // MARK: - Объединение данных

    private func merge(
        _ document: SyncDocument,
        deletedTaskIDs: Set<UUID>,
        deletedEntryIDs: Set<UUID>,
        into context: ModelContext
    ) throws {

        let localClients = try context.fetch(
            FetchDescriptor<Client>()
        )

        let localTasks = try context.fetch(
            FetchDescriptor<WorkTask>()
        )

        let localEntries = try context.fetch(
            FetchDescriptor<TimeEntry>()
        )

        var clientsByID: [UUID: Client] = [:]
        var tasksByID: [UUID: WorkTask] = [:]
        var entriesByID: [UUID: TimeEntry] = [:]

        for client in localClients {
            if client.id == nil {
                client.id = UUID()
            }

            if client.updatedAt == nil {
                client.updatedAt = client.createdAt
            }

            if let id = client.id {
                clientsByID[id] = client
            }
        }

        for task in localTasks {
            if task.id == nil {
                task.id = UUID()
            }

            if task.updatedAt == nil {
                task.updatedAt = task.createdAt
            }

            if let id = task.id {
                tasksByID[id] = task
            }
        }

        for entry in localEntries {
            if entry.id == nil {
                entry.id = UUID()
            }

            if entry.updatedAt == nil {
                entry.updatedAt = entry.endDate
            }

            if let id = entry.id {
                entriesByID[id] = entry
            }
        }

        // 1. Удаляем проекты, отмеченные как удалённые.

        for task in localTasks {
            if let id = task.id,
               deletedTaskIDs.contains(id) {
                context.delete(task)
            }
        }

        // Удаляем связанные с ними записи времени.

        for entry in localEntries {
            if let taskID = entry.task?.id,
               deletedTaskIDs.contains(taskID) {
                context.delete(entry)
            }
        }

        // 2. Удаляем записи времени, отмеченные как удалённые.

        for entry in localEntries {
            if let id = entry.id,
               deletedEntryIDs.contains(id) {
                context.delete(entry)
            }
        }

        // 3. Клиенты.

        for remote in document.clients {
            if let local = clientsByID[remote.id] {

                let localDate = local.updatedAt ?? local.createdAt

                if remote.updatedAt > localDate {
                    local.name = remote.name
                    local.hourlyRate = remote.hourlyRate
                    local.createdAt = remote.createdAt
                    local.updatedAt = remote.updatedAt
                }

                if let remoteColor = remote.colorHex {
                    let localColorDate = local.colorUpdatedAt
                        ?? .distantPast

                    let remoteColorDate = remote.colorUpdatedAt
                        ?? remote.updatedAt

                    if local.colorHex == nil ||
                        remoteColorDate > localColorDate {

                        local.colorHex = remoteColor
                        local.colorUpdatedAt = remoteColorDate
                    }
                }

            } else {

                let client = Client(
                    name: remote.name,
                    hourlyRate: remote.hourlyRate
                )

                client.id = remote.id
                client.createdAt = remote.createdAt
                client.updatedAt = remote.updatedAt
                client.colorHex = remote.colorHex
                client.colorUpdatedAt = remote.colorUpdatedAt

                context.insert(client)
                clientsByID[remote.id] = client
            }
        }

        // 4. Проекты.

        for remote in document.tasks
        where !deletedTaskIDs.contains(remote.id) {

            let remoteClient = remote.clientID.flatMap {
                clientsByID[$0]
            }

            if let local = tasksByID[remote.id] {

                local.client = remoteClient

                let localDate = local.updatedAt ?? local.createdAt

                guard remote.updatedAt > localDate else {
                    continue
                }

                local.name = remote.name
                local.hourlyRate = remote.hourlyRate
                local.createdAt = remote.createdAt
                local.updatedAt = remote.updatedAt
                local.isPaid = remote.isPaid
                local.paidAt = remote.paidAt

            } else {

                let task = WorkTask(
                    name: remote.name,
                    client: remoteClient,
                    hourlyRate: remote.hourlyRate
                )

                task.id = remote.id
                task.createdAt = remote.createdAt
                task.updatedAt = remote.updatedAt
                task.isPaid = remote.isPaid
                task.paidAt = remote.paidAt

                context.insert(task)
                tasksByID[remote.id] = task
            }
        }

        // 5. Записи времени.

        for remote in document.entries
        where !deletedEntryIDs.contains(remote.id)
        && (remote.taskID.map {
            !deletedTaskIDs.contains($0)
        } ?? true) {

            let remoteTask = remote.taskID.flatMap {
                tasksByID[$0]
            }

            if let local = entriesByID[remote.id] {

                local.task = remoteTask

                let localDate = local.updatedAt ?? local.endDate

                guard remote.updatedAt > localDate else {
                    continue
                }

                local.startDate = remote.startDate
                local.endDate = remote.endDate
                local.taskName = remote.taskName
                local.clientName = remote.clientName
                local.hourlyRate = remote.hourlyRate
                local.note = remote.note
                local.updatedAt = remote.updatedAt

            } else {

                let entry = TimeEntry(
                    startDate: remote.startDate,
                    endDate: remote.endDate,
                    taskName: remote.taskName,
                    clientName: remote.clientName,
                    hourlyRate: remote.hourlyRate,
                    note: remote.note
                )

                entry.id = remote.id
                entry.updatedAt = remote.updatedAt
                entry.task = remoteTask

                context.insert(entry)
                entriesByID[remote.id] = entry
            }
        }
    }

    // MARK: - Очистка дубликатов

    private func removeDuplicates(
        in context: ModelContext
    ) throws {

        let clients = try context.fetch(
            FetchDescriptor<Client>()
        )

        let tasks = try context.fetch(
            FetchDescriptor<WorkTask>()
        )

        let entries = try context.fetch(
            FetchDescriptor<TimeEntry>()
        )

        func normalized(_ value: String) -> String {
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        func dateKey(_ date: Date) -> Int64 {
            Int64(date.timeIntervalSince1970.rounded(.down))
        }

        func rateKey(_ rate: Double) -> String {
            String(rate.bitPattern, radix: 16)
        }

        // 1. Объединяем клиентов.

        let clientGroups = Dictionary(
            grouping: clients
        ) { client in
            [
                normalized(client.name),
                String(dateKey(client.createdAt)),
                rateKey(client.hourlyRate)
            ].joined(separator: "|")
        }

        for (_, group) in clientGroups {
            let sorted = group.sorted {
                ($0.updatedAt ?? $0.createdAt) >
                ($1.updatedAt ?? $1.createdAt)
            }

            guard let keeper = sorted.first else {
                continue
            }

            for duplicate in sorted.dropFirst() {

                let keeperColorDate = keeper.colorUpdatedAt
                    ?? .distantPast

                let duplicateColorDate = duplicate.colorUpdatedAt
                    ?? .distantPast

                if keeper.colorHex == nil ||
                    (duplicate.colorHex != nil &&
                     duplicateColorDate > keeperColorDate) {

                    keeper.colorHex = duplicate.colorHex
                    keeper.colorUpdatedAt = duplicate.colorUpdatedAt
                }

                for task in tasks where task.client === duplicate {
                    task.client = keeper
                }

                context.delete(duplicate)
            }
        }

        // 2. Объединяем проекты.

        func taskKey(_ task: WorkTask) -> String {
            let clientID = task.client?.id?.uuidString ?? ""
            let clientName = normalized(task.client?.name ?? "")

            return [
                normalized(task.name),
                clientID,
                clientName,
                String(dateKey(task.createdAt))
            ].joined(separator: "|")
        }

        let taskGroups = Dictionary(
            grouping: tasks,
            by: taskKey
        )

        for (_, group) in taskGroups {
            let sorted = group.sorted {
                ($0.updatedAt ?? $0.createdAt) >
                ($1.updatedAt ?? $1.createdAt)
            }

            guard let keeper = sorted.first else {
                continue
            }

            for duplicate in sorted.dropFirst() {
                for entry in entries where entry.task === duplicate {
                    entry.task = keeper
                }

                context.delete(duplicate)
            }
        }

        // 3. Объединяем записи времени.
        // Удаление дубля также регистрируем в tombstones,
        // иначе старая копия может вернуться из другого устройства.

        func entryKey(_ entry: TimeEntry) -> String {
            [
                String(dateKey(entry.startDate)),
                String(dateKey(entry.endDate)),
                normalized(entry.taskName),
                normalized(entry.clientName),
                rateKey(entry.hourlyRate),
                normalized(entry.note)
            ].joined(separator: "|")
        }

        let entryGroups = Dictionary(
            grouping: entries,
            by: entryKey
        )

        for (_, group) in entryGroups {
            let sorted = group.sorted {
                ($0.updatedAt ?? $0.endDate) >
                ($1.updatedAt ?? $1.endDate)
            }

            for duplicate in sorted.dropFirst() {
                if let id = duplicate.id {
                    Self.recordEntryDeletion(id)
                }

                context.delete(duplicate)
            }
        }
    }

    // MARK: - Формирование документа

    private func makeDocument(
        from context: ModelContext,
        deletedTaskIDs: Set<UUID>,
        deletedEntryIDs: Set<UUID>
    ) throws -> SyncDocument {

        let clients = try context.fetch(
            FetchDescriptor<Client>()
        )

        let tasks = try context.fetch(
            FetchDescriptor<WorkTask>()
        )

        let entries = try context.fetch(
            FetchDescriptor<TimeEntry>()
        )

        let activeEntries = entries.filter { entry in
            guard let id = entry.id else {
                return true
            }

            return !deletedEntryIDs.contains(id)
        }

        return SyncDocument(
            clients: clients.map { SyncClient($0) },
            tasks: tasks.map { SyncTask($0) },
            entries: activeEntries.map { SyncEntry($0) },
            deletedTaskIDs: Array(deletedTaskIDs),
            deletedEntryIDs: Array(deletedEntryIDs)
        )
    }

    // MARK: - Кодирование

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]

        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return decoder
    }
}

// MARK: - Формат файла синхронизации

private struct SyncDocument: Codable {

    var clients: [SyncClient]
    var tasks: [SyncTask]
    var entries: [SyncEntry]
    var deletedTaskIDs: [UUID]
    var deletedEntryIDs: [UUID]

    init(
        clients: [SyncClient] = [],
        tasks: [SyncTask] = [],
        entries: [SyncEntry] = [],
        deletedTaskIDs: [UUID] = [],
        deletedEntryIDs: [UUID] = []
    ) {
        self.clients = clients
        self.tasks = tasks
        self.entries = entries
        self.deletedTaskIDs = deletedTaskIDs
        self.deletedEntryIDs = deletedEntryIDs
    }

    private enum CodingKeys: String, CodingKey {
        case clients
        case tasks
        case entries
        case deletedTaskIDs
        case deletedEntryIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        clients = try container.decodeIfPresent(
            [SyncClient].self,
            forKey: .clients
        ) ?? []

        tasks = try container.decodeIfPresent(
            [SyncTask].self,
            forKey: .tasks
        ) ?? []

        entries = try container.decodeIfPresent(
            [SyncEntry].self,
            forKey: .entries
        ) ?? []

        deletedTaskIDs = try container.decodeIfPresent(
            [UUID].self,
            forKey: .deletedTaskIDs
        ) ?? []

        deletedEntryIDs = try container.decodeIfPresent(
            [UUID].self,
            forKey: .deletedEntryIDs
        ) ?? []
    }
}

// MARK: - Клиенты

private struct SyncClient: Codable {

    let id: UUID
    let name: String
    let hourlyRate: Double
    let createdAt: Date
    let updatedAt: Date
    let colorHex: String?
    let colorUpdatedAt: Date?

    init(_ client: Client) {
        let id = client.id ?? UUID()
        let updatedAt = client.updatedAt ?? client.createdAt

        client.id = id
        client.updatedAt = updatedAt

        self.id = id
        self.name = client.name
        self.hourlyRate = client.hourlyRate
        self.createdAt = client.createdAt
        self.updatedAt = updatedAt
        self.colorHex = client.colorHex
        self.colorUpdatedAt = client.colorUpdatedAt
    }
}

// MARK: - Проекты

private struct SyncTask: Codable {

    let id: UUID
    let name: String
    let hourlyRate: Double
    let createdAt: Date
    let updatedAt: Date
    let clientID: UUID?
    let isPaid: Bool
    let paidAt: Date?

    init(_ task: WorkTask) {
        let id = task.id ?? UUID()
        let updatedAt = task.updatedAt ?? task.createdAt

        task.id = id
        task.updatedAt = updatedAt

        self.id = id
        self.name = task.name
        self.hourlyRate = task.hourlyRate
        self.createdAt = task.createdAt
        self.updatedAt = updatedAt
        self.clientID = task.client?.id
        self.isPaid = task.isPaid
        self.paidAt = task.paidAt
    }
}

// MARK: - Записи времени

private struct SyncEntry: Codable {

    let id: UUID
    let startDate: Date
    let endDate: Date
    let taskName: String
    let clientName: String
    let hourlyRate: Double
    let note: String
    let updatedAt: Date
    let taskID: UUID?

    init(_ entry: TimeEntry) {
        let id = entry.id ?? UUID()
        let updatedAt = entry.updatedAt ?? entry.endDate

        entry.id = id
        entry.updatedAt = updatedAt

        self.id = id
        self.startDate = entry.startDate
        self.endDate = entry.endDate
        self.taskName = entry.taskName
        self.clientName = entry.clientName
        self.hourlyRate = entry.hourlyRate
        self.note = entry.note
        self.updatedAt = updatedAt
        self.taskID = entry.task?.id
    }
}

// MARK: - Ошибки

enum SyncServiceError: LocalizedError {

    case coordination(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .coordination(let message):
            return "Ошибка доступа к файлу синхронизации: \(message)"

        case .unknown:
            return "Не удалось завершить синхронизацию."
        }
    }
}
