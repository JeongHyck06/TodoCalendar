import SwiftUI

enum AppTab: String { case calendar, todos, categories }
enum CalendarMode: String, CaseIterable, Identifiable {
    case month = "월", week = "주", day = "일"
    var id: Self { self }
}

@MainActor @Observable
final class Workspace {
    var selectedDate: Date
    var month: Date
    var filterIDs: Set<UUID>?
    var search = ""
    var tab: AppTab = .calendar
    var mode: CalendarMode = .month
    var editor: TodoItem?
    var categoryEditor: TodoCategory?
    var showSettings = false
    var showDatePicker = false
    var isSearching = false
    var sidebarToday = false

    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let date = testing ? Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 2))! : Date.now
        selectedDate = date
        month = CalendarMath.monthStart(date)
    }

    func select(_ date: Date) { selectedDate = date; month = CalendarMath.monthStart(date) }
    func move(_ delta: Int) {
        let component: Calendar.Component = mode == .month ? .month : .day
        let value = mode == .week ? delta * 7 : delta
        select(Calendar.current.date(byAdding: component, value: value, to: selectedDate)!)
    }
    func toggleCategory(_ id: UUID, all: [TodoCategory]) {
        var next = filterIDs ?? Set(all.map(\.id))
        if next.contains(id) { next.remove(id) } else { next.insert(id) }
        filterIDs = next.count == all.count ? nil : next
    }
    func newTodo(categories: [TodoCategory]) {
        guard let category = categories.first(where: { filterIDs?.contains($0.id) ?? true }) ?? categories.first else {
            categoryEditor = TodoCategory(name: "", color: .school)
            return
        }
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate)!
        editor = TodoItem(title: "", categoryID: category.id, start: start, end: start.addingTimeInterval(3600))
    }
}

struct RootView: View {
    @Environment(TodoStore.self) private var store
    @State private var workspace = Workspace()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("showCompleted") private var showCompleted = true
    @AppStorage("mondayFirst") private var mondayFirst = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var compact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        @Bindable var store = store
        Group {
            if compact { phoneTabs }
            else { desktopLayout }
        }
        .environment(workspace)
        .sheet(item: $workspace.editor) { TodoEditor(item: store.series(for: $0)).environment(workspace) }
        .sheet(item: $workspace.categoryEditor) { CategoryEditor(category: $0).environment(workspace) }
        .sheet(isPresented: $workspace.showSettings) { SettingsView() }
        .sheet(isPresented: $workspace.showDatePicker) {
            NavigationStack {
                DatePicker("날짜 이동", selection: Binding(get: { workspace.selectedDate }, set: { workspace.select($0) }), displayedComponents: .date)
                    .datePickerStyle(.graphical).padding()
                    .navigationTitle("날짜 이동")
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("완료", systemImage: "checkmark") { workspace.showDatePicker = false }
                    } }
            }.presentationDetents([.medium]).frame(minWidth: 320, minHeight: 360)
        }
        .alert("알림", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("확인", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: .newTodo)) { _ in workspace.newTodo(categories: store.categories) }
        .task(id: "\(store.revision)-\(scenePhase)") {
            guard scenePhase == .active, !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
            do { try await ReminderService.shared.synchronize(store.items) }
            catch { if !Task.isCancelled { store.errorMessage = "알림을 예약하지 못했습니다. \(error.localizedDescription)" } }
        }
    }

    private var phoneTabs: some View {
        TabView(selection: $workspace.tab) {
            Tab("캘린더", systemImage: "calendar", value: AppTab.calendar) {
                NavigationStack { CalendarScreen(compact: true) }
            }
            Tab("전체 보기", systemImage: "list.bullet", value: AppTab.todos) {
                NavigationStack { TodoListScreen() }
            }
            Tab("종류", systemImage: "square.grid.2x2", value: AppTab.categories) {
                NavigationStack { CategoriesScreen() }
            }
        }
    }

    private var desktopLayout: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            if workspace.tab == .todos {
                TodoListScreen()
            } else {
                CalendarScreen(compact: false)
                #if os(macOS)
                .inspector(isPresented: .constant(true)) {
                    DayAgenda(date: workspace.selectedDate)
                        .inspectorColumnWidth(min: 270, ideal: 320, max: 380)
                }
                #endif
            }
        }
    }
}

struct SidebarView: View {
    @Environment(TodoStore.self) private var store
    @Environment(Workspace.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        List {
            Button {
                workspace.filterIDs = nil; workspace.search = ""; workspace.tab = .calendar; workspace.sidebarToday = false; workspace.mode = .month
            } label: {
                Label { HStack { Text("전체 일정"); Spacer(); Text("\(store.items.count)").foregroundStyle(.secondary) } }
                    icon: { Image(systemName: "calendar").foregroundStyle(.blue) }
            }
            .listRowBackground(workspace.tab == .calendar && !workspace.sidebarToday ? Color.accentColor.opacity(0.10) : .clear)
            .accessibilityIdentifier("allCategories")
            Button {
                workspace.search = ""
                workspace.tab = .todos
            } label: {
                Label("전체 보기", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .listRowBackground(workspace.tab == .todos ? Color.accentColor.opacity(0.10) : .clear)
            .accessibilityIdentifier("showAllTodos")
            Button {
                workspace.tab = .calendar
                workspace.select(.now); workspace.mode = .day; workspace.sidebarToday = true
            } label: { Label("오늘의 투두", systemImage: "checkmark.circle") }
            Section {
                ForEach(store.categories) { category in
                    Button { workspace.tab = .calendar; workspace.toggleCategory(category.id, all: store.categories) } label: {
                        HStack {
                            Image(systemName: workspace.filterIDs?.contains(category.id) ?? true ? "checkmark.square.fill" : "square")
                                .foregroundStyle(category.color.color)
                            Text(category.name)
                            Spacer()
                            Text("\(store.items.filter { $0.categoryID == category.id }.count)").foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("filter-\(category.name)")
                    .contextMenu { Button("종류 편집") { workspace.categoryEditor = category } }
                }
                Button { workspace.categoryEditor = TodoCategory(name: "", color: .school) } label: {
                    Label { Text("새로운 종류") } icon: { Image("FigmaPlus12").renderingMode(.template) }
                }.foregroundStyle(Theme.calendarAccent)
            } header: { Text("내 투두 종류") }
        }
        .buttonStyle(.plain)
        .listStyle(.sidebar)
        .navigationTitle("Todo")
        .searchable(text: $workspace.search, prompt: "검색")
        .safeAreaInset(edge: .bottom, alignment: .leading) {
            Button { workspace.showSettings = true } label: {
                Label { Text("설정") } icon: { Image("FigmaGearshape2").renderingMode(.template) }
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding()
        }
    }
}
