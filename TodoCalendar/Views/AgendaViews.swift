import SwiftUI

struct TodoRow: View {
    let item: TodoItem
    @Environment(TodoStore.self) private var store
    @Environment(Workspace.self) private var workspace
    @State private var confirmSeriesDelete = false
    var body: some View {
        let category = store.category(for: item)
        HStack(spacing: 12) {
            Button { store.toggle(item) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(item.isCompleted ? (category?.color.color ?? .accentColor) : .secondary)
                    .frame(minWidth: 32, minHeight: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel(item.title + (item.isCompleted ? " 완료 취소" : " 완료"))
                .accessibilityIdentifier("complete-\(item.title)")
            Button { workspace.editor = item } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.headline).foregroundStyle(item.isCompleted ? .secondary : .primary)
                        .strikethrough(item.isCompleted)
                    HStack(spacing: 4) {
                        if item.repeatsWeekly { Image(systemName: "repeat").accessibilityLabel("매주 반복") }
                        CategoryDot(color: category?.color ?? .school)
                        Text("\(category?.name ?? "종류 없음") · \(item.isAllDay ? "하루 종일" : item.start.korean("HH:mm") + "–" + item.end.korean("HH:mm"))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("todo-\(item.title)")
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
        .contextMenu {
            Button("편집", systemImage: "pencil") { workspace.editor = item }
            Button(item.isCompleted ? "완료 취소" : "완료", systemImage: "checkmark.circle") { store.toggle(item) }
            Button(item.repeatsWeekly ? "반복 전체 삭제" : "삭제", systemImage: "trash", role: .destructive) { delete() }
        }
        .swipeActions(edge: .trailing) {
            Button(item.repeatsWeekly ? "반복 전체 삭제" : "삭제", role: .destructive) { delete() }
            Button("편집") { workspace.editor = item }.tint(.blue)
        }
        .confirmationDialog("매주 반복되는 모든 일정을 삭제할까요?", isPresented: $confirmSeriesDelete, titleVisibility: .visible) {
            Button("반복 전체 삭제", role: .destructive) { store.perform { try store.delete(item) } }
        }
    }
    private func delete() {
        if item.repeatsWeekly { confirmSeriesDelete = true }
        else { store.perform { try store.delete(item) } }
    }
}

struct AgendaSection: View {
    let date: Date
    let items: [TodoItem]
    private var daily: [TodoItem] { items.filter { CalendarMath.occurs($0, on: date) } }
    var body: some View {
        Section {
            if daily.isEmpty {
                ContentUnavailableView("등록된 투두가 없어요", systemImage: "checkmark.circle", description: Text("다른 날짜나 종류를 선택하거나\n새로운 투두를 추가해 보세요."))
                    .listRowSeparator(.hidden)
            } else {
                ForEach(daily, id: \.occurrenceID) { TodoRow(item: $0) }
            }
        } header: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(date.korean("M월 d일 EEEE")).font(.headline).foregroundStyle(Color.primary)
                    Spacer()
                    if Calendar.current.isDateInToday(date) { Text("오늘").font(.caption).foregroundStyle(Theme.calendarAccent) }
                }
                Text("투두 \(daily.count)개 · \(daily.filter(\.isCompleted).count)개 완료").font(.caption).foregroundStyle(.secondary)
            }.textCase(nil).padding(.vertical, 8)
        }
    }
}

struct DayAgenda: View {
    let date: Date
    var showUpcoming = true
    @Environment(TodoStore.self) private var store
    @Environment(Workspace.self) private var workspace
    @AppStorage("showCompleted") private var showCompleted = true
    var body: some View {
        let start = min(Calendar.current.startOfDay(for: date), Calendar.current.startOfDay(for: .now))
        let end = Calendar.current.date(byAdding: .year, value: 1, to: max(date, .now))!
        let items = store.filtered(categoryIDs: workspace.filterIDs, search: workspace.search, showCompleted: showCompleted,
                                   interval: DateInterval(start: start, end: end))
        List {
            AgendaSection(date: date, items: items)
            if showUpcoming { Section { UpcomingCard(items: items).padding(.vertical) }.listRowSeparator(.hidden) }
        }.listStyle(.plain)
    }
}

struct UpcomingCard: View {
    let items: [TodoItem]
    @Environment(TodoStore.self) private var store
    @Environment(Workspace.self) private var workspace
    private var upcoming: TodoItem? { items.first { !$0.isCompleted && $0.start > .now } }
    var body: some View {
        if let item = upcoming {
            let category = store.category(for: item)
            VStack(alignment: .leading, spacing: 12) {
                Label { Text("다음 일정") } icon: { Image("FigmaMusicNote2").renderingMode(.template) }
                    .font(.caption).foregroundStyle(category?.color.color ?? .secondary)
                Text(item.title).font(.title3.bold())
                Text(item.start.korean("M월 d일 EEEE · a h:mm")).font(.footnote).foregroundStyle(.secondary)
                if !item.notes.isEmpty { Text(item.notes).font(.footnote).foregroundStyle(.secondary) }
                Button("일정 보기") { workspace.select(item.start); workspace.editor = item }
                    .tint(category?.color.color)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TodoListScreen: View {
    @Environment(TodoStore.self) private var store
    @Environment(Workspace.self) private var workspace
    private var search: String { workspace.search }
    private var items: [TodoItem] { store.allItems(search: search) }
    private var regular: [TodoItem] { items.filter { !$0.repeatsWeekly } }
    private var repeating: [TodoItem] { items.filter(\.repeatsWeekly) }
    private var dates: [Date] { Array(Set(regular.map { Calendar.current.startOfDay(for: $0.start) })).sorted() }

    var body: some View {
        @Bindable var workspace = workspace
        List {
            Section {
                HStack {
                    Label("전체 일정", systemImage: "tray.full")
                    Spacer()
                    Text("\(items.count)개").foregroundStyle(.secondary).monospacedDigit()
                }
                Text("날짜와 종류에 관계없이 완료한 일정까지 모두 표시합니다. 매주 반복 일정은 한 항목으로 모아 보여 줍니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if items.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView("등록된 일정이 없어요", systemImage: "calendar.badge.plus",
                                           description: Text("새로운 투두를 추가해 보세요."))
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
            if !repeating.isEmpty {
                Section("매주 반복") {
                    ForEach(repeating) { item in
                        Button { workspace.editor = item } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "repeat").font(.title3)
                                    .foregroundStyle(store.category(for: item)?.color.color ?? .accentColor)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).font(.headline).foregroundStyle(.primary)
                                    Text("\(store.category(for: item)?.name ?? "종류 없음") · 매주 \(item.start.korean("EEEE")) · \(item.isAllDay ? "하루 종일" : item.start.korean("a h:mm"))")
                                        .font(.footnote).foregroundStyle(.secondary)
                                    Text("\(item.start.korean("yyyy년 M월 d일"))부터 · 완료 \(item.completedOccurrences?.count ?? 0)회")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("series-\(item.title)")
                    }
                }
            }
            ForEach(dates, id: \.self) { date in
                Section(date.korean("yyyy년 M월 d일 EEEE")) {
                    ForEach(regular.filter { Calendar.current.isDate($0.start, inSameDayAs: date) }) { item in
                        TodoRow(item: item)
                    }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("전체 보기")
        #if os(iOS)
        .searchable(text: $workspace.search, prompt: "전체 일정 검색")
        #endif
        .toolbar {
            ToolbarItem(id: "allTodosDelete", placement: .primaryAction) {
                DeleteAllTodosButton()
            }
            ToolbarItem(id: "allTodosAdd", placement: .primaryAction) {
                Button("새로운 투두", systemImage: "plus") { workspace.newTodo(categories: store.categories) }
                    .accessibilityIdentifier("addTodoFromAll")
            }
        }
    }
}

