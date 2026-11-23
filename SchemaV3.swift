
import Foundation
import SwiftData

enum SchemaV3: VersionedSchema {

    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Client.self,
            WorkTask.self,
            TimeEntry.self
        ]
    }

    @Model
    final class Client {

        var id: UUID?
        var updatedAt: Date?

        var name: String
        var hourlyRate: Double
        var createdAt: Date

        var colorHex: String?
        var colorUpdatedAt: Date?

        @Relationship(
            deleteRule: .cascade,
            inverse: \SchemaV3.WorkTask.client
        )
        var tasks: [WorkTask] = []

        init(name: String, hourlyRate: Double = 0) {
            self.id = UUID()
            self.updatedAt = Date()
            self.name = name
            self.hourlyRate = hourlyRate
            self.createdAt = Date()
            self.colorHex = nil
            self.colorUpdatedAt = nil
        }
    }

    @Model
    final class WorkTask {

        var id: UUID?
        var updatedAt: Date?

        var name: String
        var hourlyRate: Double
        var createdAt: Date
        var client: Client?

        var isPaid: Bool = false
        var paidAt: Date?

        @Relationship(
            deleteRule: .cascade,
            inverse: \SchemaV3.TimeEntry.task
        )
        var entries: [TimeEntry] = []

        init(
            name: String,
            client: Client? = nil,
            hourlyRate: Double = 0
        ) {
            self.id = UUID()
            self.updatedAt = Date()
            self.name = name
            self.client = client
            self.hourlyRate = hourlyRate
            self.createdAt = Date()
            self.isPaid = false
            self.paidAt = nil
        }
    }

    @Model
    final class TimeEntry {

        var id: UUID?
        var updatedAt: Date?

        var startDate: Date
        var endDate: Date
        var taskName: String
        var clientName: String
        var hourlyRate: Double
        var note: String
        var task: WorkTask?

        init(
            startDate: Date,
            endDate: Date,
            taskName: String,
            clientName: String,
            hourlyRate: Double,
            note: String = ""
        ) {
            self.id = UUID()
            self.updatedAt = Date()
            self.startDate = startDate
            self.endDate = endDate
            self.taskName = taskName
            self.clientName = clientName
            self.hourlyRate = hourlyRate
            self.note = note
        }

        // MARK: - Расчёты

        var duration: TimeInterval {
            max(0, endDate.timeIntervalSince(startDate))
        }

        var cost: Double {
            duration / 3600 * hourlyRate
        }

        var durationHours: Double {
            duration / 3600
        }

        // MARK: - Форматирование

        var formattedDuration: String {
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

        var formattedCost: String {
            cost.formatted(
                .currency(code: "RUB")
            )
        }
    }
}
