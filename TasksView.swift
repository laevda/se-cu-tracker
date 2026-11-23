import SwiftUI
import SwiftData

struct TasksView: View {

    @Environment(\.modelContext) private var modelContext

    @Query(
        sort: \WorkTask.name,
        order: .forward
    )
    private var tasks: [WorkTask]

    var body: some View {

        List {

            ForEach(tasks) { task in

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {

                    Text(task.name)
                        .font(.headline)

                    HStack {

                        if let client = task.client {
                            Text(client.name)
                        }

                        Spacer()

                        Text(
                            task.hourlyRate,
                            format: .currency(
                                code: "RUB"
                            )
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .onDelete(
                perform: deleteTasks
            )
        }
        .navigationTitle("Задачи")
        .frame(
            minWidth: 500,
            minHeight: 400
        )
    }

    private func deleteTasks(
        at offsets: IndexSet
    ) {

        for index in offsets {

            modelContext.delete(
                tasks[index]
            )
        }

        try? modelContext.save()
    }
}
