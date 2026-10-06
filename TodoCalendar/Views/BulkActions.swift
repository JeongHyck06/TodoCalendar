import SwiftUI

struct DeleteAllTodosButton: View {
    @Environment(TodoStore.self) private var store
    @State private var confirming = false

    var body: some View {
        Button("전체 삭제", systemImage: "trash", role: .destructive) { confirming = true }
            .disabled(store.items.isEmpty)
            .accessibilityIdentifier("deleteAllTodos")
            .confirmationDialog("모든 투두를 삭제할까요?", isPresented: $confirming, titleVisibility: .visible) {
                Button("모든 투두 삭제", role: .destructive) { store.perform { try store.deleteAllItems() } }
                    .accessibilityIdentifier("confirmDeleteAllTodos")
                Button("취소", role: .cancel) { }
            } message: {
                Text("검색이나 필터에 가려진 항목을 포함해 등록된 일정 \(store.items.count)개와 반복 일정의 모든 회차 및 완료 기록이 삭제됩니다. 종류는 유지되며 삭제는 되돌릴 수 없습니다.")
            }
    }
}
