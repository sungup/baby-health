import SwiftUI
import UserNotifications

/// 아기별 식사 시간과 알람 설정.
struct AlarmSettingsView: View {
    @Bindable var baby: Baby
    @Environment(\.dismiss) private var dismiss

    @State private var status: UNAuthorizationStatus = .notDetermined

    private var upcoming: [PlannedAlarm] {
        AlarmPlanner.plan(inputs: [AlarmBabyInput(baby: baby)], from: .now, limit: 5)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("식사·취침 시간") {
                    timePicker("아침", minutes: $baby.breakfastMinutes)
                    timePicker("점심", minutes: $baby.lunchMinutes)
                    timePicker("저녁", minutes: $baby.dinnerMinutes)
                    timePicker("취침", minutes: $baby.bedtimeMinutes)
                    Text("식사 기준 투약 알람은 이 시간에 식전/식후 간격을 더해 계산합니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("알람") {
                    Toggle("식사 알람", isOn: $baby.mealAlarmsEnabled)
                    Toggle("투약 알람", isOn: $baby.medicationAlarmsEnabled)
                    Text("투약 기간(처방전의 복용일) 동안에만 울립니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("알림 권한") {
                    switch status {
                    case .authorized, .provisional, .ephemeral:
                        Label("알림이 허용되어 있습니다.", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    case .denied:
                        Label("알림이 꺼져 있습니다.", systemImage: "bell.slash")
                            .foregroundStyle(.red)
                        Button("설정 앱에서 허용하기") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    default:
                        Button("알림 허용 요청") {
                            Task {
                                await AlarmScheduler.shared.requestAuthorization()
                                await loadStatus()
                            }
                        }
                    }
                }

                Section("다음 알람 미리보기") {
                    if upcoming.isEmpty {
                        Text("예정된 알람이 없습니다. 투약 기간 중인 처방이 있어야 알람이 생성됩니다.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(upcoming) { alarm in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alarm.fireDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(alarm.title).font(.subheadline.bold())
                            Text(alarm.body).font(.footnote)
                            ShareLink(item: alarm.shareText) {
                                Label("공유", systemImage: "square.and.arrow.up")
                                    .font(.footnote)
                            }
                        }
                    }
                }

                Section {
                    Text("참고용이며 의료진 상담을 대체하지 않습니다. iOS 제한으로 가까운 알람 최대 60개까지만 예약되며, 앱을 열 때마다 다시 채워집니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("알람 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
            .task { await loadStatus() }
        }
    }

    private func loadStatus() async {
        status = await AlarmScheduler.shared.authorizationStatus()
    }

    private func timePicker(_ title: String, minutes: Binding<Int>) -> some View {
        DatePicker(
            title,
            selection: Binding(
                get: { MinuteOfDay.date(for: minutes.wrappedValue) },
                set: { minutes.wrappedValue = MinuteOfDay.minutes(from: $0) }
            ),
            displayedComponents: .hourAndMinute
        )
    }
}
