
import Foundation
import SwiftData

enum AppContainer {

    static let shared: ModelContainer = {

        do {

            let schema = Schema(
                versionedSchema: SchemaV3.self
            )

            return try ModelContainer(
                for: schema,
                migrationPlan: SecuTrackerMigrationPlan.self
            )

        } catch {

            fatalError(
                "Не удалось создать SwiftData контейнер: \(error)"
            )
        }
    }()
}
