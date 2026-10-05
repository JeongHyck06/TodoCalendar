import SwiftUI

extension CategoryColor {
    var color: Color { Color(rawValue) }
}

enum Theme {
    static let calendarAccent = Color("CalendarAccent")
    static var background: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
    static var separator: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color(uiColor: .separator)
        #endif
    }
}

extension Date {
    func korean(_ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = pattern
        return formatter.string(from: self)
    }
}

struct CategoryDot: View {
    let color: CategoryColor
    var body: some View {
        Circle().fill(color.color).frame(width: 5, height: 5).accessibilityHidden(true)
    }
}
