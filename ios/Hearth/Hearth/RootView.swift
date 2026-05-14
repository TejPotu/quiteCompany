import SwiftUI

struct RootView: View {
    @State private var screen: HearthScreen = {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--initial"), idx + 1 < args.count,
           let s = HearthScreen(rawValue: args[idx + 1]) {
            return s
        }
        return .tv
    }()

    private func greeting(at date: Date) -> String {
        switch screen {
        case .tv:     return "Watching"
        case .people: return "Looking"
        case .cues:   return "Setup"
        }
    }

    var body: some View {
        ZStack {
            HearthColor.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    TopBar(
                        greeting: greeting(at: context.date),
                        time: Self.timeString(context.date),
                        day: Self.dayString(context.date),
                        weatherTemp: "72°",
                        weatherIcon: "sun.max.fill",
                        listening: false
                    )
                }
                Group {
                    switch screen {
                    case .tv:     TVScreen()
                    case .people: PersonScreen()
                    case .cues:   CuesScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                BottomNav(current: $screen)
            }
        }
        .preferredColorScheme(.light)
        .tint(HearthColor.ember)
    }

    private static func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"   // "8:42 AM"
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return f.string(from: date)
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"     // "Tuesday"
        return f.string(from: date)
    }
}

#Preview {
    RootView()
}
