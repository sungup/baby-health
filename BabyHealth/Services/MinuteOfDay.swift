import Foundation

/// 하루 중 시각을 "자정 기준 분"(0...1439)으로 다루는 도우미.
enum MinuteOfDay {
    static func string(from minutes: Int) -> String {
        let normalized = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// 오늘 날짜의 해당 시각 Date (DatePicker 바인딩용).
    static func date(for minutes: Int, calendar: Calendar = .current, on day: Date = .now) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }

    /// 지금 시각을 10분 단위로 올림한 값 (최초 투약 시간의 기본값).
    static func roundedUpMinutes(from date: Date, calendar: Calendar = .current, step: Int = 10) -> Int {
        let current = minutes(from: date, calendar: calendar)
        let rounded = ((current + step - 1) / step) * step
        return rounded % 1440
    }
}
