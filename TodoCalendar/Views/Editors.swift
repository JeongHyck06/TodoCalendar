import SwiftUI

struct TodoEditor: View {
    @Environment(TodoStore.self) private var store
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodoItem
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var saving = false

    init(item: TodoItem) { _draft = State(initialValue: item) }
    private var isNew: Bool { !store.items.contains { $0.id == draft.id } }
    private var valid: Bool { !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (draft.isAllDay || draft.end > draft.start) }
    private var day: Binding<Date> {
        Binding(get: { draft.start }, set: { date in
            let cal = Calendar.current
            let duration = draft.end.timeIntervalSince(draft.start)
            let time = cal.dateComponents([.hour, .minute], from: draft.start)
            draft.start = cal.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: date)!
            draft.end = draft.start.addingTimeInterval(duration)
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("제목", text: $draft.title).accessibilityIdentifier("todoTitle")
                    TextField("메모", text: $draft.notes, axis: .vertical).lineLimit(2...4)
                        .accessibilityIdentifier("todoNotes")
                    Picker("종류", selection: $draft.categoryID) {
                        ForEach(store.categories) { category in
                            Label(category.name, systemImage: "circle.fill").foregroundStyle(category.color.color).tag(category.id)
                        }
                    }
                }
                Section {
                    DatePicker("날짜", selection: day, displayedComponents: .date)
                    Toggle("하루 종일", isOn: $draft.isAllDay)
                    if !draft.isAllDay {
                        DatePicker("시작", selection: $draft.start, displayedComponents: [.hourAndMinute])
                        DatePicker("종료", selection: $draft.end, displayedComponents: [.date, .hourAndMinute])
                    }
                    Picker("반복", selection: Binding(get: { draft.repeatRule ?? .never }, set: { draft.repeatRule = $0 })) {
                        ForEach(TodoRepeat.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("todoRepeat")
                    Picker("알림", selection: $draft.reminder) {
                        ForEach(Reminder.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    if !draft.isAllDay && draft.end <= draft.start {
                        Text("종료 시간은 시작 시간보다 늦어야 합니다.").foregroundStyle(.red)
                    } else if draft.repeatsWeekly {
                        Text("시작일과 같은 요일과 시간에 매주 반복됩니다. 수정과 삭제는 반복 전체에 적용되며 각 주의 완료는 목록에서 표시할 수 있습니다.")
                    } else {
                        Text("\(store.categories.first { $0.id == draft.categoryID }?.name ?? "선택한 종류") 캘린더에 추가됩니다.")
                    }
                }
                if !isNew {
                    Section {
                        if !draft.repeatsWeekly { Toggle("완료", isOn: $draft.isCompleted) }
                        Button(draft.repeatsWeekly ? "반복 전체 삭제" : "투두 삭제", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "새로운 투두" : "투두 편집")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", systemImage: "xmark") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", systemImage: "checkmark") { Task { await save() } }
                        .buttonStyle(.borderedProminent).disabled(!valid || saving)
                        .accessibilityIdentifier("saveTodo")
                }
            }
            .alert("저장할 수 없어요", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("확인", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .confirmationDialog(draft.repeatsWeekly ? "매주 반복되는 모든 일정을 삭제할까요?" : "이 투두를 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(draft.repeatsWeekly ? "반복 전체 삭제" : "투두 삭제", role: .destructive) {
                    do { try store.delete(draft); dismiss() }
                    catch { errorMessage = error.localizedDescription }
                }
            }
        }
        .interactiveDismissDisabled(saving)
        #if os(macOS)
        .frame(width: 500, height: 570)
        #else
        .presentationDetents([.large])
        #endif
    }

    @MainActor private func save() async {
        saving = true
        defer { saving = false }
        var item = draft
        if item.isAllDay {
            item.start = Calendar.current.startOfDay(for: item.start)
            item.end = Calendar.current.date(byAdding: .day, value: 1, to: item.start)!
        }
        do {
            var reminderAllowed = true
            if item.reminder != .none { reminderAllowed = try await ReminderService.shared.requestPermission() }
            try store.save(item)
            workspace.select(item.start)
            if !(workspace.filterIDs?.contains(item.categoryID) ?? true) { workspace.filterIDs = nil }
            dismiss()
            if !reminderAllowed { store.errorMessage = "투두를 저장했습니다. 알림을 받으려면 시스템 설정에서 Todo Calendar의 알림을 허용해 주세요." }
        } catch { errorMessage = error.localizedDescription }
    }
}

struct CategoriesScreen: View {
    @Environment(TodoStore.self) private var store
    @Environment(Workspace.self) private var workspace
    var body: some View {
        List {
            Section("내 투두 종류") {
                ForEach(store.categories) { category in
                    Button { workspace.categoryEditor = category } label: {
                        HStack {
                            Image(systemName: "circle.fill").foregroundStyle(category.color.color)
                            Text(category.name).foregroundStyle(.primary)
                            Spacer()
                            Text("\(store.items.filter { $0.categoryID == category.id && !$0.isCompleted }.count)개 남음").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            Section {
                Button("새로운 종류", systemImage: "plus") { workspace.categoryEditor = TodoCategory(name: "", color: .school) }
                Button("설정", systemImage: "gearshape") { workspace.showSettings = true }
            }
        }
        .navigationTitle("종류")
    }
}

struct CategoryEditor: View {
    @Environment(TodoStore.self) private var store
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodoCategory
    @State private var moveTarget: UUID?
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    init(category: TodoCategory) { _draft = State(initialValue: category) }
    private var existing: Bool { store.categories.contains { $0.id == draft.id } }
    private var others: [TodoCategory] { store.categories.filter { $0.id != draft.id } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("종류 이름", text: $draft.name).accessibilityIdentifier("categoryName")
                    Picker("색상", selection: $draft.color) {
                        ForEach(CategoryColor.allCases) { color in
                            Label(color.title, systemImage: "circle.fill").foregroundStyle(color.color).tag(color)
                        }
                    }
                }
                if existing && !others.isEmpty {
                    Section {
                        Picker("투두를 이동할 종류", selection: $moveTarget) {
                            ForEach(others) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Button("종류 삭제", role: .destructive) { confirmDelete = true }
                    } footer: { Text("종류를 삭제하면 해당 투두는 선택한 종류로 이동합니다.") }
                }
            }.formStyle(.grouped)
                .navigationTitle(existing ? "종류 편집" : "새로운 종류")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("취소", systemImage: "xmark") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장", systemImage: "checkmark") {
                            do { try store.saveCategory(draft); dismiss() }
                            catch { errorMessage = error.localizedDescription }
                        }.buttonStyle(.borderedProminent).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .confirmationDialog("‘\(draft.name)’ 종류를 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("투두 이동 후 삭제", role: .destructive) {
                        guard let target = moveTarget else { return }
                        do {
                            try store.deleteCategory(draft.id, movingTo: target)
                            workspace.filterIDs = nil
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
                .alert("종류를 저장할 수 없어요", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                    Button("확인", role: .cancel) { errorMessage = nil }
                } message: { Text(errorMessage ?? "") }
        }
        .onAppear { moveTarget = others.first?.id }
        #if os(macOS)
        .frame(width: 420, height: 340)
        #endif
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showCompleted") private var showCompleted = true
    @AppStorage("mondayFirst") private var mondayFirst = false
    var body: some View {
        NavigationStack {
            Form {
                Section("캘린더") {
                    Toggle("완료한 투두 표시", isOn: $showCompleted)
                    Toggle("월요일부터 시작", isOn: $mondayFirst)
                }
                Section("데이터") {
                    Text("일정은 이 기기에 자동으로 저장됩니다.")
                    Text("처음 실행하면 현재 월에 예시 일정 14개가 표시됩니다. 자유롭게 수정하거나 삭제할 수 있습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("안내") {
                    Link("개인정보 처리방침", destination: URL(string: "https://jeonghyck06.github.io/TodoCalendar/privacy.html")!)
                    Link("고객지원", destination: URL(string: "https://jeonghyck06.github.io/TodoCalendar/support.html")!)
                }
            }.formStyle(.grouped).navigationTitle("설정")
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("완료", systemImage: "checkmark") { dismiss() }
                } }
        }
        #if os(macOS)
        .frame(width: 420, height: 330)
        #endif
    }
}
