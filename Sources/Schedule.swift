import Foundation

/// The days and hours you work. Outside them Sway stays quiet.
enum WorkHours {
    /// Whether `date` falls in work hours. With an end before the start (a night shift),
    /// the hours run past midnight and belong to the day they started.
    static func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let day = calendar.component(.weekday, from: date)
        let days = Settings.workDays, start = Settings.workStart, end = Settings.workEnd
        if start < end { return days.contains(day) && minute >= start && minute < end }
        let yesterday = day == 1 ? 7 : day - 1
        return (days.contains(day) && minute >= start) || (days.contains(yesterday) && minute < end)
    }

    /// When work hours next begin after `date`, if any day is picked.
    static func nextStart(after date: Date) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  Settings.workDays.contains(calendar.component(.weekday, from: day)),
                  let start = calendar.date(bySettingHour: Settings.workStart / 60, minute: Settings.workStart % 60,
                                            second: 0, of: day),
                  start > date else { continue }
            return start
        }
        return nil
    }
}

/// A break at a set time of day, such as lunch or an afternoon walk.
struct PlannedBreak: Codable, Equatable {
    var id = UUID()
    var title: String
    /// Start time, in minutes after midnight.
    var start: Int
    /// Length in minutes.
    var length: Int

    /// A planned break this long after its time still starts, e.g. once a call holding it ends.
    static let grace: TimeInterval = 60 * 60

    /// Today's start, moved later by any snoozes.
    func due(on date: Date, snoozed: TimeInterval) -> Date? {
        Calendar.current.date(bySettingHour: start / 60, minute: start % 60, second: 0, of: date)?
            .addingTimeInterval(snoozed)
    }
}
