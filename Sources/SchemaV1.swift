
import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {

    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Client.self,
            WorkTask.self,
            TimeEntry.self
        ]
    }

    @Model
    final class Client {
        var name: String
        var hourlyRate: Double
        var createdAt: Date

        @Relationship(
            deleteRule: .cascade,
            inverse: \SchemaV1.WorkTask.client
        )
        var tasks: [WorkTask] = []

        init(name: String, hourlyRate: Double = 0) {
            self.name = name
            self.hourlyRate = hourlyRate
            self.createdAt = Date()
        }
    }

    @Model
    final class WorkTask {
        var name: String
        var hourlyRate: Double
        var createdAt: Date
        var client: Client?
        var isPaid: Bool = false
        var paidAt: Date?

        @Relationship(
            deleteRule: .cascade,
            inverse: \SchemaV1.TimeEntry.task
        )
        var entries: [TimeEntry] = []

        init(
            name: String,
            client: Client? = nil,
            hourlyRate: Double = 0
        ) {
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
            self.startDate = startDate
            self.endDate = endDate
            self.taskName = taskName
            self.clientName = clientName
            self.hourlyRate = hourlyRate
            self.note = note
        }
    }
}
