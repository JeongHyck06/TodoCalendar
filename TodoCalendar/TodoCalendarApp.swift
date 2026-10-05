import SwiftUI

@main
struct TodoCalendarApp: App {
    @State private var store: TodoStore

    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let date = testing ? Date(timeIntervalSince1970: 1790902800) : Date.now
        _store = State(initialValue: TodoStore(fileURL: testing ? nil : TodoStore.defaultURL, now: date))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.locale, Locale(identifier: "ko_KR"))
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--ui-testing") ? .light : nil)
                #if os(macOS)
                .frame(minWidth: 1000, minHeight: 650)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1360, height: 834)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("새로운 투두") { NotificationCenter.default.post(name: .newTodo, object: nil) }
                    .keyboardShortcut("n")
            }
        }
        #endif
    }
}

extension Notification.Name {
    static let newTodo = Notification.Name("TodoCalendar.newTodo")
}
