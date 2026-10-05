import XCTest
@testable import TodoCalendar

final class CalendarMathTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 1
        return calendar
    }
    func testLeapFebruaryAndSixWeekMonth() {
        let february = calendar.date(from: DateComponents(year: 2028, month: 2, day: 1))!
        let days = CalendarMath.monthDays(containing: february, calendar: calendar)
        XCTAssertEqual(days.count, 35)
        XCTAssertEqual(days.filter { calendar.component(.month, from: $0) == 2 }.count, 29)
        let august = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        XCTAssertEqual(CalendarMath.monthDays(containing: august, calendar: calendar).count, 42)
        var monday = calendar
        monday.firstWeekday = 2
        XCTAssertEqual(monday.component(.weekday, from: CalendarMath.monthDays(containing: august, calendar: monday)[0]), 2)
    }

    func testOvernightEventAndExclusiveMidnightEnd() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 23))!
        var item = TodoItem(title: "밤 합주", categoryID: UUID(), start: start, end: start.addingTimeInterval(7200))
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start)!
        XCTAssertTrue(CalendarMath.occurs(item, on: start, calendar: calendar))
        XCTAssertTrue(CalendarMath.occurs(item, on: nextDay, calendar: calendar))
        item.end = calendar.startOfDay(for: nextDay)
        XCTAssertFalse(CalendarMath.occurs(item, on: nextDay, calendar: calendar))
    }
}

@MainActor final class TodoStoreTests: XCTestCase {
    func testPersistenceCRUDAndCategoryMove() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "todos.json")
        let store = TodoStore(fileURL: url)
        let category = TodoCategory(name: "프로젝트", color: .green)
        try store.saveCategory(category)
        var item = TodoItem(title: "  발표 준비  ", notes: "자료 조사", categoryID: category.id,
                            start: .now, end: Date.now.addingTimeInterval(3600), reminder: .thirtyMinutes)
        try store.save(item)
        let reloaded = TodoStore(fileURL: url)
        XCTAssertEqual(reloaded.items.first { $0.id == item.id }?.title, "발표 준비")
        XCTAssertEqual(reloaded.filtered(categoryIDs: [category.id], search: "자료").count, 1)
        reloaded.toggle(item)
        XCTAssertEqual(reloaded.filtered(categoryIDs: [category.id], search: "", showCompleted: false).count, 0)
        item.title = "발표 수정"
        try reloaded.save(item)
        XCTAssertEqual(reloaded.items.filter { $0.id == item.id }.count, 1)
        let target = reloaded.categories[0].id
        try reloaded.deleteCategory(category.id, movingTo: target)
        let moved = TodoStore(fileURL: url)
        XCTAssertEqual(moved.items.first { $0.id == item.id }?.categoryID, target)
        XCTAssertFalse(moved.categories.contains { $0.id == category.id })
        try moved.delete(item)
        XCTAssertNil(TodoStore(fileURL: url).items.first { $0.id == item.id })
    }

    func testValidationAndEmptyFilter() throws {
        let store = TodoStore(fileURL: nil)
        let count = store.items.count
        var invalid = store.items[0]
        invalid.title = "  "
        XCTAssertThrowsError(try store.save(invalid))
        invalid.title = "시험"
        invalid.end = invalid.start
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(store.items.count, count)
        XCTAssertTrue(store.filtered(categoryIDs: [], search: "").isEmpty)
        XCTAssertEqual(store.filtered(categoryIDs: nil, search: "정기 합주").count, 4)
        XCTAssertThrowsError(try store.saveCategory(TodoCategory(name: "학교 시험", color: .pink)))
    }

    func testCorruptFileIsPreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "todos.json")
        let original = Data("invalid document".utf8)
        try original.write(to: url)
        let store = TodoStore(fileURL: url)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertThrowsError(try store.saveCategory(TodoCategory(name: "복구", color: .school)))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testCompletedItemsDoNotScheduleReminders() {
        var item = TodoItem(title: "시험", categoryID: UUID(), start: .now, end: .now.addingTimeInterval(3600), reminder: .thirtyMinutes)
        XCTAssertEqual(item.reminderDate, item.start.addingTimeInterval(-1800))
        item.isCompleted = true
        XCTAssertNil(item.reminderDate)
    }
}
