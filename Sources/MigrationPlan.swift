
import Foundation
import SwiftData

enum SecuTrackerMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [
            SchemaV1.self,
            SchemaV2.self,
            SchemaV3.self
        ]
    }

    static var stages: [MigrationStage] {
        [
            MigrationStage.custom(
                fromVersion: SchemaV1.self,
                toVersion: SchemaV2.self,
                willMigrate: nil,
                didMigrate: { context in

                    let clients = try context.fetch(
                        FetchDescriptor<SchemaV2.Client>()
                    )

                    for client in clients {
                        if client.id == nil {
                            client.id = UUID()
                        }

                        if client.updatedAt == nil {
                            client.updatedAt = Date()
                        }
                    }

                    let tasks = try context.fetch(
                        FetchDescriptor<SchemaV2.WorkTask>()
                    )

                    for task in tasks {
                        if task.id == nil {
                            task.id = UUID()
                        }

                        if task.updatedAt == nil {
                            task.updatedAt = Date()
                        }
                    }

                    let entries = try context.fetch(
                        FetchDescriptor<SchemaV2.TimeEntry>()
                    )

                    for entry in entries {
                        if entry.id == nil {
                            entry.id = UUID()
                        }

                        if entry.updatedAt == nil {
                            entry.updatedAt = Date()
                        }
                    }

                    try context.save()
                }
            ),

            MigrationStage.custom(
                fromVersion: SchemaV2.self,
                toVersion: SchemaV3.self,
                willMigrate: nil,
                didMigrate: { context in

                    let clients = try context.fetch(
                        FetchDescriptor<SchemaV3.Client>()
                    )

                    let defaults = UserDefaults.standard

                    for client in clients {

                        let key = "client.color.\(client.createdAt.timeIntervalSince1970)"

                        if let hex = defaults.string(forKey: key) {
                            client.colorHex = hex
                            client.colorUpdatedAt = Date()
                        }
                    }

                    try context.save()
                }
            )
        ]
    }
}
