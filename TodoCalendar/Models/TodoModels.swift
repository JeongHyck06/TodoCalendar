import Foundation

enum CategoryColor: String, Codable, CaseIterable, Identifiable {
    case school, band, personal, green, pink
    var id: String { rawValue }
    var title: String {
        switch self {
        case .school: "파랑"
        case .band: "보라"
        case .personal: "주황"
        case .green: "초록"
        case .pink: "분홍"
        }
    }
}

struct TodoCategory: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var color: CategoryColor
}

enum Reminder: Int, Codable, CaseIterable, Identifiable {
    case none = -1, atTime = 0, fiveMinutes = 5, thirtyMinutes = 30, oneHour = 60, oneDay = 1440
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .none: "없음"
        case .atTime: "정시"
        case .fiveMinutes: "5분 전"
        case .thirtyMinutes: "30분 전"
        case .oneHour: "1시간 전"
        case .oneDay: "1일 전"
        }
    }
}

enum TodoRepeat: String, Codable, CaseIterable, Identifiable {
    case never, weekly
    var id: Self { self }
    var title: String { self == .weekly ? "매주" : "안 함" }
}

struct TodoItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var notes: String = ""
    var categoryID: UUID
    var start: Date
    var end: Date
    var isAllDay: Bool = false
    var isCompleted: Bool = false
    var reminder: Reminder = .none
    // Optional fields preserve documents created before recurrence was introduced.
    var repeatRule: TodoRepeat? = nil
    var completedOccurrences: [Date]? = nil
    var occurrenceStart: Date? = nil

    var repeatsWeekly: Bool { repeatRule == .weekly }
    var occurrenceID: String { id.uuidString + ":" + String((occurrenceStart ?? start).timeIntervalSinceReferenceDate) }

    func occurrences(in interval: DateInterval, calendar: Calendar = .current) -> [TodoItem] {
        guard repeatsWeekly else { return start < interval.end && end > interval.start ? [self] : [] }
        let duration = end.timeIntervalSince(start)
        let lookback = interval.start.addingTimeInterval(-duration - 86400)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                          to: calendar.startOfDay(for: lookback)).day ?? 0
        var week = max(0, days / 7)
        var result: [TodoItem] = []
        while let date = calendar.date(byAdding: .day, value: week * 7, to: start), date < interval.end {
            var copy = self
            copy.start = date
            copy.end = isAllDay ? calendar.date(byAdding: .day, value: 1, to: date)! : date.addingTimeInterval(duration)
            copy.occurrenceStart = date
            copy.isCompleted = completedOccurrences?.contains(date) ?? false
            if copy.end > interval.start { result.append(copy) }
            week += 1
        }
        return result
    }

    var reminderDate: Date? {
        guard reminder != .none, !isCompleted else { return nil }
        return start.addingTimeInterval(-Double(reminder.rawValue) * 60)
    }
}

struct TodoDocument: Codable, Equatable {
    var version = 1
    var categories: [TodoCategory]
    var items: [TodoItem]

    static func sample(relativeTo date: Date, calendar: Calendar = .current) -> TodoDocument {
        let school = TodoCategory(name: "학교 시험", color: .school)
        let band = TodoCategory(name: "밴드부", color: .band)
        let personal = TodoCategory(name: "개인", color: .personal)
        let month = CalendarMath.monthStart(date, calendar: calendar)
        func item(_ title: String, _ category: TodoCategory, _ day: Int, _ hour: Int,
                  _ duration: Double = 1, completed: Bool = false, notes: String = "") -> TodoItem {
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0,
                of: calendar.date(byAdding: .day, value: min(day, calendar.range(of: .day, in: .month, for: month)!.count) - 1, to: month)!)!
            return TodoItem(title: title, notes: notes, categoryID: category.id, start: start,
                end: start.addingTimeInterval(duration * 3600), isCompleted: completed)
        }
        return TodoDocument(categories: [school, band, personal], items: [
            item("중간고사 · 수학", school, 2, 9, 1.5, notes: "2장부터 4장까지 복습"),
            item("정기 합주", band, 2, 16, 2, notes: "음악실 · 공연 곡 연습"),
            item("도서관 책 반납", personal, 2, 19, completed: true),
            item("중간고사 · 영어", school, 5, 9),
            item("공연 곡 선정", band, 7, 16),
            item("정기 합주", band, 9, 16, 2),
            item("과학 수행평가", school, 12, 10),
            item("치과 예약", personal, 14, 15),
            item("정기 합주", band, 16, 16, 2),
            item("국어 발표", school, 19, 10),
            item("축제 리허설", band, 23, 15, 2),
            item("가을 축제 공연", band, 24, 17, 2),
            item("친구 생일", personal, 27, 18),
            item("정기 합주", band, 30, 16, 2)
        ])
    }
}

enum CalendarMath {
    static func monthStart(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)!.start
    }

    static func monthDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let start = monthStart(date, calendar: calendar)
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: start)!.count
        let total = ((offset + count + 6) / 7) * 7
        let first = calendar.date(byAdding: .day, value: -offset, to: start)!
        return (0..<total).map { calendar.date(byAdding: .day, value: $0, to: first)! }
    }

    static func weekDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)!.start
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    static func occurs(_ item: TodoItem, on date: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return item.start < end && item.end > start
    }
}
