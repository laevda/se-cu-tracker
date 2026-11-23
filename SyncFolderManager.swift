
import Foundation
import AppKit
import Combine

final class SyncFolderManager: ObservableObject {

    @Published private(set) var folderURL: URL?
    @Published private(set) var status = "Папка не выбрана"

    private let bookmarkKey = "SecuTrackerSyncFolderBookmark"
    private var hasActiveAccess = false

    init() {
        restoreFolderAccess()
    }

    // MARK: - Выбор папки

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Выберите папку синхронизации Secu Tracker"
        panel.message = "Выберите папку Secu Tracker Sync в iCloud Drive"
        panel.prompt = "Выбрать"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK,
              let selectedURL = panel.url else {
            return
        }

        guard selectedURL.startAccessingSecurityScopedResource() else {
            status = "Не удалось получить доступ к папке"
            return
        }

        do {
            let bookmark = try selectedURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            if hasActiveAccess, let oldURL = folderURL {
                oldURL.stopAccessingSecurityScopedResource()
            }

            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)

            folderURL = selectedURL
            hasActiveAccess = true

            updateStatus(for: selectedURL)

            print("========== SYNC FOLDER ==========")
            print("Selected path: \(selectedURL.path)")
            print("JSON exists: \(syncFileExists(in: selectedURL))")
            print("=================================")

        } catch {
            selectedURL.stopAccessingSecurityScopedResource()
            status = "Ошибка сохранения доступа: \(error.localizedDescription)"
            print("SYNC FOLDER BOOKMARK ERROR: \(error)")
        }
    }

    // MARK: - Восстановление доступа

    private func restoreFolderAccess() {
        guard let bookmark = UserDefaults.standard.data(
            forKey: bookmarkKey
        ) else {
            status = "Папка не выбрана"
            print("SYNC FOLDER: No saved bookmark")
            return
        }

        do {
            var isStale = false

            let restoredURL = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            guard restoredURL.startAccessingSecurityScopedResource() else {
                status = "Не удалось восстановить доступ к папке"
                print("SYNC FOLDER: Failed to access restored folder")
                return
            }

            folderURL = restoredURL
            hasActiveAccess = true

            if isStale {
                let newBookmark = try restoredURL.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )

                UserDefaults.standard.set(
                    newBookmark,
                    forKey: bookmarkKey
                )
            }

            updateStatus(for: restoredURL)

            print("========== SYNC FOLDER ==========")
            print("Restored path: \(restoredURL.path)")
            print("JSON exists: \(syncFileExists(in: restoredURL))")
            print("Bookmark stale: \(isStale)")
            print("=================================")

        } catch {
            status = "Ошибка восстановления доступа: \(error.localizedDescription)"
            print("SYNC FOLDER RESTORE ERROR: \(error)")
        }
    }

    // MARK: - Проверка JSON

    private func syncFileExists(in folder: URL) -> Bool {
        let fileURL = folder.appendingPathComponent("sync-data.json")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    private func updateStatus(for folder: URL) {
        let fileURL = folder.appendingPathComponent("sync-data.json")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            status = "Папка подключена: \(folder.lastPathComponent)"
        } else {
            status = "Папка подключена, sync-data.json не найден"
        }
    }
}
