import Foundation

struct ReminderItem: Identifiable {
    let id = UUID()
    let state: State
    let time: String
    let ampm: String
    let icon: String
    let title: String

    enum State { case done, now, next }
}

enum RemindersData {
    static let today: [ReminderItem] = [
        ReminderItem(state: .done, time: "8:00",  ampm: "AM", icon: "coffee",     title: "Breakfast"),
        ReminderItem(state: .now,  time: "9:00",  ampm: "AM", icon: "pill",       title: "Medicine"),
        ReminderItem(state: .next, time: "12:30", ampm: "PM", icon: "fork-knife", title: "Lunch"),
        ReminderItem(state: .next, time: "4:00",  ampm: "PM", icon: "user",       title: "Tom is visiting"),
        ReminderItem(state: .next, time: "8:00",  ampm: "PM", icon: "moon",       title: "Evening medicine"),
    ]

    // Returns the next upcoming reminder strictly after `now`, with the absolute
    // delta in minutes. Used to ground Hearth's narration in real schedule state.
    static func nextReminder(after now: Date = Date(), calendar: Calendar = .current)
        -> (item: ReminderItem, minutesFromNow: Int)?
    {
        let upcoming = today.compactMap { item -> (ReminderItem, Date)? in
            guard let date = parseTime(item.time, ampm: item.ampm, on: now, calendar: calendar)
            else { return nil }
            return (item, date)
        }
        let future = upcoming.filter { $0.1 > now }.sorted { $0.1 < $1.1 }
        guard let pick = future.first else { return nil }
        let minutes = Int(pick.1.timeIntervalSince(now) / 60.0)
        return (pick.0, minutes)
    }

    private static func parseTime(_ time: String, ampm: String, on day: Date,
                                  calendar: Calendar) -> Date? {
        let parts = time.split(separator: ":")
        guard let hRaw = Int(parts.first ?? ""), let mRaw = parts.count > 1 ? Int(parts[1]) : 0
        else { return nil }
        var hour = hRaw % 12
        if ampm.uppercased() == "PM" { hour += 12 }
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = hour
        comps.minute = mRaw
        return calendar.date(from: comps)
    }
}
