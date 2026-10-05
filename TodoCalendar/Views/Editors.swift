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
                    Picker("알림", selection: $draft.reminder) {
                        ForEach(Reminder.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    if !draft.isAllDay && draft.end <= draft.start {
                        Text("종료 시간은 시작 시간보다 늦어야 합니다.").foregroundStyle(.red)
                    } else {
                        Text("\(store.categories.first { $0.id == draft.categoryID }?.name ?? "선택한 종류") 캘린더에 추가됩니다.")
                    }
                }
                if !isNew {
                    Section {
                        Toggle("완료", isOn: $draft.isCompleted)
                        Button("투두 삭제", role: .destructive) { confirmDelete = true }
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
            .confirmationDialog("이 투두를 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("투두 삭제", role: .destructive) {
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

