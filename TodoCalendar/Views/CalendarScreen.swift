import SwiftUI

struct CalendarScreen: View {
    let compact: Bool
    @Environment(TodoStore.self) private var store
    @Environment(Workspace.self) private var workspace
    @AppStorage("showCompleted") private var showCompleted = true
    @AppStorage("mondayFirst") private var mondayFirst = false

    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = mondayFirst ? 2 : 1
        return value
    }
    private var visibleItems: [TodoItem] {
        store.filtered(categoryIDs: workspace.filterIDs, search: workspace.search, showCompleted: showCompleted)
    }
    private var days: [Date] {
        workspace.mode == .week ? CalendarMath.weekDays(containing: workspace.selectedDate, calendar: calendar)
        : CalendarMath.monthDays(containing: workspace.month, calendar: calendar)
    }

    var body: some View {
        @Bindable var workspace = workspace
        Group {
            if compact { compactContent }
            else { expandedContent }
        }
        .navigationTitle(compact ? workspace.month.korean("M월") : workspace.month.korean("yyyy년 M월"))
        .navigationSubtitle(compact ? workspace.month.korean("yyyy년") : "전체 일정 · \(workspace.filterIDs?.count ?? store.categories.count)가지 종류")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("오늘") { workspace.select(.now) }.foregroundStyle(Theme.calendarAccent)
                    .accessibilityIdentifier("today")
                Button("이전", systemImage: "chevron.left") { workspace.move(-1) }
                    .accessibilityIdentifier("previousMonth")
                Button("다음", systemImage: "chevron.right") { workspace.move(1) }
                    .accessibilityIdentifier("nextMonth")
                if !compact {
                    Picker("보기", selection: $workspace.mode) {
                        ForEach(CalendarMode.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).frame(width: 130)
                }
                if compact {
                    Menu {
                        Button("날짜 이동", systemImage: "calendar") { workspace.showDatePicker = true }
                        Button("투두 목록", systemImage: "list.bullet") { workspace.tab = .todos }
                        Button("검색", systemImage: "magnifyingglass") { workspace.isSearching = true }
                    } label: { Image(systemName: "list.bullet") }
                }
                Button("새로운 투두", systemImage: "plus") { workspace.newTodo(categories: store.categories) }
                    .accessibilityIdentifier("addTodo")
            }
        }
        #if os(iOS)
        .searchable(text: $workspace.search, isPresented: $workspace.isSearching, prompt: "제목, 메모, 종류 검색")
        .navigationBarTitleDisplayMode(compact ? .large : .inline)
        #endif
    }

    private var compactContent: some View {
        List {
            Section {
                CategoryFilter()
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 24))
                CalendarGrid(days: days, month: workspace.month, selected: workspace.selectedDate,
                             items: visibleItems, calendar: calendar, compact: true, cellHeight: 46)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 8, trailing: 24))
            }
            AgendaSection(date: workspace.selectedDate, items: visibleItems)
        }
        .listStyle(.plain)
        #if os(iOS)
        .listSectionSpacing(4)
        #endif
    }

    private var expandedContent: some View {
        GeometryReader { proxy in
            let rows = max(days.count / 7, 1)
            #if os(macOS)
            let height = max(76, (proxy.size.height - 95) / CGFloat(rows))
            #else
            let height = max(64, min(100, (proxy.size.height - 330) / CGFloat(rows)))
            #endif
            if workspace.mode == .day {
                DayAgenda(date: workspace.selectedDate)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text(workspace.search.isEmpty ? "오늘, 해야 할 일 \(store.items.filter { CalendarMath.occurs($0, on: .now) && !$0.isCompleted }.count)개" : "‘\(workspace.search)’ 검색 결과")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            CategoryLegend()
                        }
                        CalendarGrid(days: days, month: workspace.month, selected: workspace.selectedDate,
                            items: visibleItems, calendar: calendar, compact: false, cellHeight: height)
                        #if os(iOS)
                        HStack(alignment: .top, spacing: 32) {
                            DayAgenda(date: workspace.selectedDate, showUpcoming: false).frame(minHeight: 270)
                            UpcomingCard(items: visibleItems).frame(maxWidth: 300, alignment: .leading).padding(.top)
                        }
                        #else
                        HStack { CategoryLegend(); Spacer(); Text("\(visibleItems.filter { calendar.isDate($0.start, equalTo: workspace.month, toGranularity: .month) }.count)개의 일정").font(.caption).foregroundStyle(.secondary) }
                        #endif
                    }.padding(24)
                }
            }
        }
    }
}

struct CategoryFilter: View {
    @Environment(TodoStore.self) private var store
    @Environment(Workspace.self) private var workspace
    private var selection: Binding<UUID?> {
        Binding(get: { workspace.filterIDs?.count == 1 ? workspace.filterIDs?.first : nil },
                set: { workspace.filterIDs = $0.map { Set([$0]) } })
    }
    var body: some View {
        if store.categories.count <= 3 {
            Picker("투두 종류", selection: selection) {
                Text("전체").tag(nil as UUID?)
                ForEach(store.categories) { Text($0.name).tag(Optional($0.id)) }
            }.pickerStyle(.segmented).accessibilityIdentifier("categoryFilter")
        } else {
            Picker("투두 종류", selection: selection) {
                Text("전체").tag(nil as UUID?)
                ForEach(store.categories) { Text($0.name).tag(Optional($0.id)) }
            }.pickerStyle(.menu)
        }
    }
}

struct CategoryLegend: View {
    @Environment(TodoStore.self) private var store
    @Environment(Workspace.self) private var workspace
    var body: some View {
        HStack(spacing: 12) {
            ForEach(store.categories.filter { workspace.filterIDs?.contains($0.id) ?? true }.prefix(4)) { category in
                HStack(spacing: 4) { CategoryDot(color: category.color); Text(category.name).lineLimit(1) }
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
}

struct CalendarGrid: View {
    let days: [Date]
    let month: Date
    let selected: Date
    let items: [TodoItem]
    let calendar: Calendar
    let compact: Bool
    let cellHeight: CGFloat
    @Environment(TodoStore.self) private var store
    @Environment(Workspace.self) private var workspace
    @ScaledMetric(relativeTo: .body) private var daySize = 32.0

    var body: some View {
        VStack(spacing: compact ? 4 : 0) {
            HStack(spacing: 0) {
                ForEach(0..<7) { offset in
                    let weekday = (calendar.firstWeekday - 1 + offset) % 7
                    Text(["일", "월", "화", "수", "목", "금", "토"][weekday] + (compact ? "" : "요일"))
                        .font(.caption2).foregroundStyle(weekday == 0 ? Theme.calendarAccent : .secondary)
                        .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
                        .padding(.leading, compact ? 0 : 8)
                }
            }.frame(height: compact ? 20 : 28)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7), spacing: 0) {
                ForEach(days, id: \.self) { date in
                    dayCell(date)
                }
            }
        }
        .accessibilityIdentifier("calendarGrid")
    }

    private func dayCell(_ date: Date) -> some View {
        let events = items.filter { CalendarMath.occurs($0, on: date, calendar: calendar) }
        let isSelected = calendar.isDate(date, inSameDayAs: selected)
        let isCurrentMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let isSunday = calendar.component(.weekday, from: date) == 1
        let limit = max(1, min(3, Int((cellHeight - 40) / 21)))
        return VStack(alignment: compact ? .center : .leading, spacing: 3) {
            Button { workspace.select(date) } label: {
                Text("\(calendar.component(.day, from: date))")
                    .font(compact ? .body : .caption)
                    .foregroundStyle(isSelected ? Color.white : !isCurrentMonth ? Color.secondary : isSunday ? Theme.calendarAccent : Color.primary)
                    .frame(width: compact ? daySize : 26, height: compact ? daySize : 26)
                    .background(isSelected ? Theme.calendarAccent : .clear, in: Circle())
                    .overlay(Circle().strokeBorder(calendar.isDateInToday(date) && !isSelected ? Theme.calendarAccent : .clear))
                    .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(date.korean("M월 d일 EEEE") + ", 투두 \(events.count)개")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("day-\(date.korean("yyyy-MM-dd"))")
            if compact {
                HStack(spacing: 3) {
                    ForEach(store.categories.filter { category in events.contains { $0.categoryID == category.id } }.prefix(4)) { category in
                        CategoryDot(color: category.color)
                    }
                }.frame(height: 5)
            } else {
                ForEach(events.prefix(limit)) { item in
                    let color = store.category(for: item)?.color ?? .school
                    Button { workspace.select(date); workspace.editor = item } label: {
                        HStack(spacing: 3) {
                            CategoryDot(color: color)
                            Text(item.title).lineLimit(1).font(.caption2)
                                .strikethrough(item.isCompleted)
                            if item.id == events.prefix(limit).last?.id && events.count > limit {
                                Text("+\(events.count - limit)").font(.caption2).fixedSize()
                            }
                        }
                        .foregroundStyle(color.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(color.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain).help(item.title)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(compact ? 0 : 5)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: compact ? max(cellHeight, daySize + 12) : cellHeight, alignment: .topLeading)
        .background(Theme.background)
        .overlay { if !compact { Rectangle().strokeBorder(Theme.separator.opacity(0.55), lineWidth: 0.5).allowsHitTesting(false) } }
        .contentShape(Rectangle())
        .onTapGesture { workspace.select(date) }
    }
}
