import Foundation
import HomeAutomationCore

/// Schedule parsing methods for automation pattern parsing.
extension AutomationPatternParser {
    internal static func extractRepeatRule(from normalized: String) -> HomeAutomationRepeatRule {
        if normalized.contains("weekdays") {
            return .daysOfWeek([.monday, .tuesday, .wednesday, .thursday, .friday])
        }
        if normalized.contains("weekends") {
            return .daysOfWeek([.saturday, .sunday])
        }

        let weekdayMap: [(String, HomeAutomationWeekday)] = [
            ("monday", .monday),
            ("tuesday", .tuesday),
            ("wednesday", .wednesday),
            ("thursday", .thursday),
            ("friday", .friday),
            ("saturday", .saturday),
            ("sunday", .sunday)
        ]
        let days = weekdayMap.compactMap { day, value in
            normalized.contains("every \(day)") ? value : nil
        }
        if !days.isEmpty {
            return .daysOfWeek(days)
        }

        if let match = normalized.firstAutomationMatch(of: #"\bevery\s+(\d+)\s+(minute|minutes|hour|hours|day|days)\b"#),
           let value = Int(match[1]) {
            let unit: HomeAutomationTimeUnit
            switch match[2] {
            case "hour", "hours":
                unit = .hour
            case "day", "days":
                unit = .day
            default:
                unit = .minute
            }
            return .interval(value: value, unit: unit)
        }

        if normalized.contains("once") {
            return .once
        }

        return .everyDay
    }

    internal static func extractTime(from normalized: String) -> HomeAutomationTimeOfDay? {
        guard let match = normalized.firstAutomationMatch(of: #"\bat\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#),
              var hour = Int(match[1]) else {
            return nil
        }
        let minute = Int(match[2]) ?? 0
        let meridiem = match[3]
        if meridiem == "pm", hour < 12 {
            hour += 12
        } else if meridiem == "am", hour == 12 {
            hour = 0
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            return nil
        }
        return HomeAutomationTimeOfDay(hour: hour, minute: minute)
    }

    internal static func unsupportedFragments(
        in normalized: String,
        repeatRule: HomeAutomationRepeatRule
    ) -> [String] {
        var fragments: [String] = []
        switch repeatRule {
        case .daysOfWeek(let days):
            if normalized.contains("weekdays") {
                fragments.append("weekdays")
            } else if normalized.contains("weekends") {
                fragments.append("weekends")
            } else {
                fragments.append(
                    days
                        .map { "every \($0.rawValue)" }
                        .joined(separator: ", ")
                )
            }
        case .unsupported(let rawValue):
            fragments.append(rawValue)
        case .once, .everyDay, .interval:
            break
        }

        if normalized.contains("holiday") || normalized.contains("holidays") {
            fragments.append("holidays")
        }
        return stableUnique(fragments)
    }

    internal static func repeatRuleString(_ repeatRule: HomeAutomationRepeatRule) -> String {
        switch repeatRule {
        case .once:
            return "once"
        case .everyDay:
            return "everyDay"
        case .interval(let value, let unit):
            return "every \(value) \(unit.rawValue)\(value == 1 ? "" : "s")"
        case .daysOfWeek(let days):
            return "daysOfWeek:" + days.map(\.rawValue).joined(separator: ",")
        case .unsupported(let rawValue):
            return rawValue
        }
    }

    internal static func timeString(_ time: HomeAutomationTimeOfDay) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }
}
