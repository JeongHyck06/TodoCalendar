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

@MainActor final class WeeklyRecurrenceTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testWeeklyRecurrenceAcrossDSTAndFarFuture() {
        let start = date(2026, 3, 1)
        let item = TodoItem(title: "Weekly", categoryID: UUID(), start: start,
                            end: start.addingTimeInterval(3600), repeatRule: .weekly)
        let events = item.occurrences(in: DateInterval(start: start, end: date(2026, 3, 23)), calendar: calendar)
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.map { calendar.component(.hour, from: $0.start) }, [9, 9, 9, 9])
        XCTAssertEqual(Set(events.map(\.occurrenceID)).count, 4)
        XCTAssertTrue(item.occurrences(in: DateInterval(start: date(2026, 2, 1), end: start), calendar: calendar).isEmpty)
        let future = item.occurrences(in: DateInterval(start: date(2036, 3, 1), end: date(2036, 4, 1)), calendar: calendar)
        XCTAssertFalse(future.isEmpty)
        XCTAssertTrue(future.allSatisfy { calendar.component(.weekday, from: $0.start) == 1 })
    }

    func testLegacyDocumentAndOccurrenceCompletionPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "todos.json")
        let category = TodoCategory(name: "Weekly", color: .band)
        let start = date(2026, 3, 1)
        var item = TodoItem(title: "Practice", categoryID: category.id, start: start, end: start.addingTimeInterval(3600))
        let document = TodoDocument(categories: [category], items: [item])
        let legacy = try JSONEncoder().encode(document)
        XCTAssertFalse(String(decoding: legacy, as: UTF8.self).contains("repeatRule"))
        try legacy.write(to: url)
        let store = TodoStore(fileURL: url)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.items[0].repeatsWeekly)
        item.repeatRule = .weekly
        item.reminder = .thirtyMinutes
        try store.save(item)
        let interval = DateInterval(start: start, end: date(2026, 3, 16))
        let occurrences = store.filtered(categoryIDs: [category.id], search: "Practice", interval: interval, calendar: calendar)
        XCTAssertEqual(occurrences.count, 3)
        store.toggle(occurrences[1])
        let reloaded = TodoStore(fileURL: url)
        let completed = reloaded.filtered(categoryIDs: nil, search: "", interval: interval, calendar: calendar)
        XCTAssertEqual(completed.map(\.isCompleted), [false, true, false])
        XCTAssertNil(completed[1].reminderDate)
        XCTAssertNotNil(completed[2].reminderDate)
        XCTAssertEqual(reloaded.filtered(categoryIDs: nil, search: "", showCompleted: false, interval: interval, calendar: calendar).count, 2)
        XCTAssertThrowsError(try reloaded.save(completed[1]))
        var series = reloaded.series(for: completed[1])
        series.title = "Edited"
        try reloaded.save(series)
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.filtered(categoryIDs: nil, search: "Edited", interval: interval, calendar: calendar).count, 3)
        try reloaded.delete(completed[2])
        XCTAssertTrue(TodoStore(fileURL: url).items.isEmpty)
    }

    func testAllDayAndOvernightRecurringBoundaries() {
        let start = calendar.startOfDay(for: date(2026, 3, 1))
        let item = TodoItem(title: "Day", categoryID: UUID(), start: start,
                            end: calendar.date(byAdding: .day, value: 1, to: start)!, isAllDay: true, repeatRule: .weekly)
        let events = item.occurrences(in: DateInterval(start: start, end: date(2026, 3, 10)), calendar: calendar)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[1].end.timeIntervalSince(events[1].start), 23 * 3600)
        XCTAssertFalse(CalendarMath.occurs(events[1], on: events[1].end, calendar: calendar))
        let night = date(2026, 3, 6, 23)
        let overnight = TodoItem(title: "Night", categoryID: UUID(), start: night,
                                 end: night.addingTimeInterval(7200), repeatRule: .weekly)
        let nextDay = calendar.dateInterval(of: .day, for: date(2026, 3, 14))!
        XCTAssertEqual(overnight.occurrences(in: nextDay, calendar: calendar).count, 1)
    }
}
