import Foundation
import Observation

@MainActor @Observable
final class TodoStore {
    private(set) var document: TodoDocument
    private(set) var revision = 0
    var errorMessage: String?
    private let fileURL: URL?
    private var readFailed = false

    var categories: [TodoCategory] { document.categories }
    var items: [TodoItem] { document.items }

    init(fileURL: URL? = TodoStore.defaultURL, now: Date = .now) {
        self.fileURL = fileURL
        document = .sample(relativeTo: now)
        guard let fileURL else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let loaded = try JSONDecoder().decode(TodoDocument.self, from: Data(contentsOf: fileURL))
                guard loaded.version == 1 else { throw StoreError.unsupportedVersion }
                document = loaded
            } catch {
                readFailed = true
                document = TodoDocument(categories: [], items: [])
                errorMessage = "저장된 데이터를 열지 못했습니다. 원본 파일은 보존했습니다. \(error.localizedDescription)"
            }
        } else {
            do { try write(document) }
            catch { errorMessage = "초기 데이터를 저장하지 못했습니다. \(error.localizedDescription)" }
        }
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "TodoCalendar", directoryHint: .isDirectory)
            .appending(path: "todos.json")
    }

    func category(for item: TodoItem) -> TodoCategory? { categories.first { $0.id == item.categoryID } }

    func filtered(categoryIDs: Set<UUID>?, search: String, showCompleted: Bool = true) -> [TodoItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            (categoryIDs == nil || categoryIDs!.contains(item.categoryID)) &&
            (showCompleted || !item.isCompleted) &&
            (query.isEmpty || item.title.localizedStandardContains(query) ||
             item.notes.localizedStandardContains(query) ||
             (category(for: item)?.name.localizedStandardContains(query) ?? false))
        }.sorted { $0.start == $1.start ? $0.title < $1.title : $0.start < $1.start }
    }

    func save(_ item: TodoItem) throws {
        var item = item
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.title.isEmpty, item.end > item.start,
              categories.contains(where: { $0.id == item.categoryID }) else { throw StoreError.invalidItem }
        var next = document
        if let index = next.items.firstIndex(where: { $0.id == item.id }) { next.items[index] = item }
        else { next.items.append(item) }
        try commit(next)
    }

    func toggle(_ item: TodoItem) {
        guard var latest = items.first(where: { $0.id == item.id }) else { return }
        latest.isCompleted.toggle()
        perform { try save(latest) }
    }

    func delete(_ item: TodoItem) throws {
        var next = document
        next.items.removeAll { $0.id == item.id }
        try commit(next)
    }

    func saveCategory(_ category: TodoCategory) throws {
        var category = category
        category.name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.name.isEmpty else { throw StoreError.invalidCategory }
        guard !categories.contains(where: { $0.id != category.id && $0.name == category.name })
        else { throw StoreError.duplicateCategory }
        var next = document
        if let index = next.categories.firstIndex(where: { $0.id == category.id }) { next.categories[index] = category }
        else { next.categories.append(category) }
        try commit(next)
    }

    func deleteCategory(_ id: UUID, movingTo target: UUID) throws {
        guard id != target, categories.contains(where: { $0.id == target }) else { throw StoreError.invalidCategory }
        var next = document
        next.categories.removeAll { $0.id == id }
        for index in next.items.indices where next.items[index].categoryID == id { next.items[index].categoryID = target }
        try commit(next)
    }

    func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }

    private func commit(_ next: TodoDocument) throws {
        guard !readFailed else { throw StoreError.loadFailed }
        try write(next)
        document = next
        revision += 1
    }

    private func write(_ next: TodoDocument) throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: fileURL, options: .atomic)
    }
}

enum StoreError: LocalizedError {
    case invalidItem, invalidCategory, duplicateCategory, unsupportedVersion, loadFailed
    var errorDescription: String? {
        switch self {
        case .invalidItem: "제목, 종류, 시작·종료 시간을 확인해 주세요."
        case .invalidCategory: "종류 이름과 이동할 종류를 확인해 주세요."
        case .duplicateCategory: "같은 이름의 종류가 이미 있습니다."
        case .unsupportedVersion: "이 앱에서 지원하지 않는 데이터 버전입니다."
        case .loadFailed: "데이터를 다시 정상적으로 불러오기 전에는 기존 파일을 변경할 수 없습니다."
        }
    }
}
