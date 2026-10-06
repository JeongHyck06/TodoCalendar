import SwiftUI

struct CalendarDateRow: View {
    let title: String
    @Binding var selection: Date
    @State private var showingCalendar = false

    var body: some View {
        LabeledContent(title) {
            Button { showingCalendar = true } label: {
                HStack(spacing: 8) {
                    Text(selection.korean("yyyy년 M월 d일 (E)"))
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                }.font(.body).padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
                .accessibilityLabel(title + " " + selection.korean("yyyy년 M월 d일"))
                .popover(isPresented: $showingCalendar) {
                    CalendarDatePopover(selection: $selection) { showingCalendar = false }
                }
        }
    }
}

private struct CalendarDatePopover: View {
    @Binding var selection: Date
    let done: () -> Void
    @State private var month: Date
    private let calendar = Calendar.current

    init(selection: Binding<Date>, done: @escaping () -> Void) {
        _selection = selection
        self.done = done
        _month = State(initialValue: CalendarMath.monthStart(selection.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(month.korean("yyyy년 M월")).font(.headline)
                Spacer()
                Button { move(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("이전 달")
                Button { month = CalendarMath.monthStart(.now) } label: { Image(systemName: "circle.fill").font(.caption2) }
                    .accessibilityLabel("이번 달")
                Button { move(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("다음 달")
            }.buttonStyle(.borderless)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<7) { offset in
                    let weekday = (calendar.firstWeekday - 1 + offset) % 7
                    Text(["일", "월", "화", "수", "목", "금", "토"][weekday])
                        .font(.caption).foregroundStyle(.secondary).frame(height: 26)
                }
                ForEach(CalendarMath.monthDays(containing: month, calendar: calendar), id: \.self) { date in
                    let selected = calendar.isDate(date, inSameDayAs: selection)
                    let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
                    Button { choose(date) } label: {
                        Text("\(calendar.component(.day, from: date))")
                            .font(.body.monospacedDigit())
                            .frame(width: 32, height: 32)
                            .foregroundStyle(selected ? Color.white : inMonth ? Color.primary : Color.secondary)
                            .background(selected ? Color.accentColor : .clear, in: Circle())
                            .overlay(Circle().strokeBorder(calendar.isDateInToday(date) && !selected ? Color.accentColor : .clear))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(date.korean("yyyy년 M월 d일 EEEE"))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Divider()
            HStack {
                Button("오늘") { choose(.now) }
                Spacer()
                Button("닫기", action: done)
            }.buttonStyle(.borderless)
        }.padding(20).frame(width: 310)
    }
    private func move(_ amount: Int) { month = calendar.date(byAdding: .month, value: amount, to: month)! }
    private func choose(_ date: Date) {
        let time = calendar.dateComponents([.hour, .minute, .second], from: selection)
        selection = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                                  second: time.second ?? 0, of: date)!
        done()
    }
}

struct CalendarTimeRow: View {
    let title: String
    @Binding var selection: Date
    @State private var showingTime = false
    private let calendar = Calendar.current

    var body: some View {
        LabeledContent(title) {
            Button { showingTime = true } label: {
                HStack(spacing: 8) {
                    Text(selection.korean("a h:mm")).monospacedDigit()
                    Image(systemName: "clock").foregroundStyle(.secondary)
                }.font(.body).padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
                .accessibilityLabel(title + " " + selection.korean("a h:mm"))
                .popover(isPresented: $showingTime) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(title).font(.headline)
                        HStack(spacing: 16) {
                            Picker("시", selection: component(.hour)) {
                                ForEach(0..<24) { hour in Text("\(hour < 12 ? "오전" : "오후") \(hour % 12 == 0 ? 12 : hour % 12)시").tag(hour) }
                            }.pickerStyle(.menu)
                            Picker("분", selection: component(.minute)) {
                                ForEach(0..<60) { minute in Text(String(format: "%02d분", minute)).tag(minute) }
                            }.pickerStyle(.menu)
                        }
                        HStack { Spacer(); Button("완료") { showingTime = false }.buttonStyle(.borderedProminent) }
                    }.padding(20).frame(width: 300)
                }
        }
    }
    private func component(_ component: Calendar.Component) -> Binding<Int> {
        Binding(get: { calendar.component(component, from: selection) }, set: { value in
            let hour = component == .hour ? value : calendar.component(.hour, from: selection)
            let minute = component == .minute ? value : calendar.component(.minute, from: selection)
            selection = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: selection)!
        })
    }
}
