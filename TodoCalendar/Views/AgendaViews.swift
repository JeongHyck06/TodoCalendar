import SwiftUI

struct TodoRow: View {
    let item: TodoItem
    @Environment(TodoStore.self) private var store
    @Environment(Workspace.self) private var workspace
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
            Button("삭제", systemImage: "trash", role: .destructive) { store.perform { try store.delete(item) } }
        }
        .swipeActions(edge: .trailing) {
            Button("삭제", role: .destructive) { store.perform { try store.delete(item) } }
            Button("편집") { workspace.editor = item }.tint(.blue)
        }
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
                ForEach(daily) { TodoRow(item: $0) }
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
        let items = store.filtered(categoryIDs: workspace.filterIDs, search: workspace.search, showCompleted: showCompleted)
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
    @AppStorage("showCompleted") private var showCompleted = true
    private var filtered: [TodoItem] { store.filtered(categoryIDs: workspace.filterIDs, search: workspace.search, showCompleted: showCompleted) }
    private var dates: [Date] { Array(Set(filtered.map { Calendar.current.startOfDay(for: $0.start) })).sorted() }
    var body: some View {
        @Bindable var workspace = workspace
        List {
            CategoryFilter().listRowSeparator(.hidden)
            if filtered.isEmpty { ContentUnavailableView.search(text: workspace.search) }
            ForEach(dates, id: \.self) { date in AgendaSection(date: date, items: filtered) }
        }
        .listStyle(.plain)
        .navigationTitle("투두")
        .searchable(text: $workspace.search, prompt: "검색")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("새로운 투두", systemImage: "plus") { workspace.newTodo(categories: store.categories) }
            }
        }
    }
}
