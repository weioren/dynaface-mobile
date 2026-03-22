import SwiftUI
import UserNotifications

struct HomePage: View {
    let baseWidth: CGFloat = 390
    let baseHeight: CGFloat = 844
    
    @State private var currentStreak: Int = 0
    @State private var isReminderOn: Bool = false
    
    // Reminder (multiple weekdays: 1=Sun ... 7=Sat)
    @State private var reminderTime: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
    @State private var selectedWeekdays: Set<Int> = [] // Multiple days allowed
    
    // Exercise history -> streak + calendar highlights
    @State private var exercisedDays: Set<Date> = []
    private let calendar = Calendar.current
    @State private var displayedMonthStart: Date = {
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: now)
        return cal.date(from: comps)!
    }()
    
    // Persistence keys
    private let kReminderOn  = "reminderOn"
    private let kReminderTime = "reminderTime"
    private let kReminderDays  = "reminderDays"
    
    // Space to keep your bottom dashboard unobstructed
    private let dashboardReserve: CGFloat = 80
    
    var body: some View {
        GeometryReader { geometry in
            let widthScale = geometry.size.width / baseWidth
            let heightScale = geometry.size.height / baseHeight
            
            ScrollView {
                VStack(spacing: 20 * heightScale) {
                    // Streak card
                    VStack {
                        Text("\(currentStreak) days")
                            .font(.system(size: 32 * widthScale))
                            .fontWeight(.bold)
                        Text("Your current streak")
                            .font(.system(size: 20 * widthScale))
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10 * widthScale)
                    
                    // Calendar card
                    VStack(spacing: 10 * heightScale) {
                        HStack {
                            Button { shiftMonth(by: -1) } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 20 * widthScale, weight: .semibold))
                                    .frame(width: 32 * widthScale, height: 32 * widthScale)
                            }
                            Spacer()
                            Text(monthTitle(for: displayedMonthStart))
                                .font(.system(size: 20 * widthScale))
                                .fontWeight(.semibold)
                            Spacer()
                            Button { shiftMonth(by: 1) } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 20 * widthScale, weight: .semibold))
                                    .frame(width: 32 * widthScale, height: 32 * widthScale)
                            }
                        }
                        
                        let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]
                        HStack {
                            ForEach(Array(daysOfWeek.enumerated()), id: \.offset) { index, day in
                                Text(day)
                                    .frame(maxWidth: .infinity)
                                    .font(.system(size: 16 * widthScale))
                            }
                        }
                        
                        let firstWeekdayOffset = firstWeekdayOffsetForMonth(displayedMonthStart)
                        let daysInMonth = daysCount(in: displayedMonthStart)
                        let totalCells = firstWeekdayOffset + daysInMonth
                        let gridItems = Array(repeating: GridItem(.flexible()), count: 7)
                        
                        LazyVGrid(columns: gridItems, spacing: 10 * heightScale) {
                            ForEach(0..<totalCells, id: \.self) { cell in
                                if cell < firstWeekdayOffset {
                                    Text("")
                                        .frame(width: 32 * widthScale, height: 32 * widthScale)
                                } else {
                                    let dayNumber = cell - firstWeekdayOffset + 1
                                    let date = dateFor(day: dayNumber, in: displayedMonthStart)
                                    let isLogged = exercisedDays.contains(startOfDay(date))
                                    
                                    Text("\(dayNumber)")
                                        .font(.system(size: 14 * widthScale))
                                        .frame(width: 32 * widthScale, height: 32 * widthScale)
                                        .background(
                                            isLogged
                                            ? Color(red: 0.12, green: 0.29, blue: 0.64).opacity(0.65)
                                            : Color.clear
                                        )
                                        .cornerRadius(16 * widthScale)
                                        .foregroundColor(.black)
                                        .accessibilityLabel("\(dayNumber) \(isLogged ? "logged" : "not logged")")
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10 * widthScale)
                    
                    // Reminder card (row + optional panel) -> matches calendar card width/margins
                    VStack(alignment: .leading, spacing: 12 * heightScale) {
                        // Compact row
                        HStack(spacing: 8 * widthScale) {
                            Text("Add Reminder:")
                                .font(.system(size: 16 * widthScale))
                            Spacer(minLength: 8 * widthScale)
                            Toggle("", isOn: $isReminderOn)
                                .labelsHidden()
                        }
                        
                        // Panel (only when ON)
                        if isReminderOn {
                            VStack(alignment: .leading, spacing: 12) {
                                // Multiple day selection
                                Text("Which days of the week would you like reminders?")
                                    .font(.system(size: 14 * widthScale))
                                    .foregroundColor(.secondary)

                                HStack(spacing: 8) {
                                    ForEach(1...7, id: \.self) { wd in
                                        let label = calendar.shortWeekdaySymbols[wd - 1]
                                        Button {
                                            if selectedWeekdays.contains(wd) {
                                                selectedWeekdays.remove(wd)
                                            } else {
                                                selectedWeekdays.insert(wd)
                                            }
                                        } label: {
                                            Text(String(label.prefix(3)))
                                                .font(.system(size: 14 * widthScale, weight: .semibold))
                                                .foregroundColor(selectedWeekdays.contains(wd) ? .white : .primary)
                                                .padding(.vertical, 8)
                                                .frame(minWidth: 36)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .fill(selectedWeekdays.contains(wd)
                                                              ? Color(red: 0.12, green: 0.29, blue: 0.64)
                                                              : Color.gray.opacity(0.2))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                Text("Remind me at")
                                    .font(.system(size: 14 * widthScale))
                                    .foregroundColor(.secondary)

                                // Compact time picker to save vertical space
                                DatePicker("", selection: $reminderTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()

                                if !selectedWeekdays.isEmpty {
                                    Text("You'll get reminders on the selected days at \(formattedTime(reminderTime)).")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10 * widthScale)
                    
                    // Keep clear space above your bottom dashboard
                    Color.clear.frame(height: dashboardReserve)
                }
                .padding(.horizontal, 30 * widthScale)
                .padding(.top, 16)
            }
            // gives room for any overlay/tab bar; content scrolls
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 0) }
        }
        .onAppear {
            loadReminderSettings()
            reloadExerciseDays()
            recomputeStreak()
            if isReminderOn { ensurePermissionAndSchedule() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            reloadExerciseDays(); recomputeStreak()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingAccepted)) { _ in
            reloadExerciseDays(); recomputeStreak()
        }
        .onChange(of: isReminderOn) { _ in
            saveReminderSettings()
            isReminderOn ? ensurePermissionAndSchedule() : cancelWeeklyReminders()
        }
        .onChange(of: reminderTime) { _ in
            saveReminderSettings()
            if isReminderOn { rescheduleWeeklyReminder() }
        }
        .onChange(of: selectedWeekdays) { _ in
            saveReminderSettings()
            if isReminderOn { rescheduleWeeklyReminder() }
        }
    }
}

// MARK: - Data loading & streak logic
extension HomePage {
    private func loadReminderSettings() {
        let ud = UserDefaults.standard
        isReminderOn = ud.bool(forKey: kReminderOn)
        if let t = ud.object(forKey: kReminderTime) as? Date { reminderTime = t }
        if let savedDays = ud.array(forKey: kReminderDays) as? [Int] {
            selectedWeekdays = Set(savedDays.filter { $0 >= 1 && $0 <= 7 })
        }
    }
    private func saveReminderSettings() {
        let ud = UserDefaults.standard
        ud.set(isReminderOn, forKey: kReminderOn)
        ud.set(reminderTime, forKey: kReminderTime)
        ud.set(Array(selectedWeekdays), forKey: kReminderDays)
    }
    
    private func reloadExerciseDays() {
        exercisedDays.removeAll()
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            let movFiles = files.filter { $0.pathExtension.lowercased() == "mov" }
            for url in movFiles {
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let created = values?.creationDate ?? values?.contentModificationDate ?? Date.distantPast
                exercisedDays.insert(startOfDay(created))
            }
        } catch {
            print("Error loading video files: \(error)")
        }
    }
    
    private func recomputeStreak() {
        var streak = 0
        var day = startOfDay(Date())
        while exercisedDays.contains(day) {
            streak += 1
            if let prev = calendar.date(byAdding: .day, value: -1, to: day) {
                day = startOfDay(prev)
            } else { break }
        }
        currentStreak = streak
    }
}

// MARK: - Notifications (single weekly reminder)
extension HomePage {
    private var notificationPrefix: String { "weeklyExercise-" }
    
    private func ensurePermissionAndSchedule() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                rescheduleWeeklyReminder()
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted { rescheduleWeeklyReminder() }
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }
    
    private func rescheduleWeeklyReminder() {
        cancelWeeklyReminders {
            scheduleWeeklyReminder()
        }
    }
    
    private func cancelWeeklyReminders(completion: (() -> Void)? = nil) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(notificationPrefix) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            completion?()
        }
    }
    
    private func scheduleWeeklyReminder() {
        let center = UNUserNotificationCenter.current()
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)

        // Schedule a notification for each selected weekday
        for weekday in selectedWeekdays {
            var dc = DateComponents()
            dc.weekday = weekday        // 1=Sun ... 7=Sat
            dc.hour = comps.hour ?? 9
            dc.minute = comps.minute ?? 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)
            let content = UNMutableNotificationContent()
            content.title = "Time to practice"
            content.body = "Reminder to do your facial exercises today!"
            content.sound = .default

            let id = "\(notificationPrefix)\(weekday)-\(dc.hour!)-\(dc.minute!)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(request, withCompletionHandler: nil)
        }
    }
}

// MARK: - Calendar helpers
extension HomePage {
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
    private func daysCount(in monthStart: Date) -> Int {
        calendar.range(of: .day, in: .month, for: monthStart)!.count
    }
    private func firstWeekdayOffsetForMonth(_ monthStart: Date) -> Int {
        calendar.component(.weekday, from: monthStart) - 1 // 0..6
    }
    private func dateFor(day: Int, in monthStart: Date) -> Date {
        calendar.date(byAdding: .day, value: day - 1, to: monthStart)!
    }
    private func monthTitle(for monthStart: Date) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "MMMM yyyy"; return fmt.string(from: monthStart)
    }
    private func shiftMonth(by delta: Int) {
        if let newStart = calendar.date(byAdding: .month, value: delta, to: displayedMonthStart) {
            let comps = calendar.dateComponents([.year, .month], from: newStart)
            displayedMonthStart = calendar.date(from: comps) ?? newStart
        }
    }
}

// MARK: - Preview
#Preview {
    HomePage()
}
