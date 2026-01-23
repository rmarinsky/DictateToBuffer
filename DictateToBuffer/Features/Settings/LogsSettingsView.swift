import OSLog
import SwiftUI

struct LogsSettingsView: View {
    @StateObject private var logsService = LogsService.shared
    @State private var selectedTimeRange: TimeRange = .lastHour
    @State private var selectedCategory: String = "All"
    @State private var selectedLevel: LogLevelFilter = .all
    @State private var searchText = ""

    enum TimeRange: String, CaseIterable {
        case last15Minutes = "Last 15 min"
        case lastHour = "Last hour"
        case last6Hours = "Last 6 hours"
        case last24Hours = "Last 24 hours"

        var timeInterval: TimeInterval {
            switch self {
            case .last15Minutes: return 15 * 60
            case .lastHour: return 60 * 60
            case .last6Hours: return 6 * 60 * 60
            case .last24Hours: return 24 * 60 * 60
            }
        }
    }

    enum LogLevelFilter: String, CaseIterable {
        case all = "All Levels"
        case debug = "Debug"
        case info = "Info"
        case notice = "Notice"
        case error = "Error"
        case fault = "Fault"
    }

    private var categories: [String] {
        var cats = Set(logsService.logs.map { $0.category })
        cats.insert("All")
        return ["All"] + cats.filter { $0 != "All" }.sorted()
    }

    private var filteredLogs: [LogsService.LogEntry] {
        logsService.logs.filter { entry in
            let categoryMatch = selectedCategory == "All" || entry.category == selectedCategory
            let levelMatch = matchesLevel(entry.level)
            let searchMatch = searchText.isEmpty ||
                entry.message.localizedCaseInsensitiveContains(searchText) ||
                entry.category.localizedCaseInsensitiveContains(searchText)
            return categoryMatch && levelMatch && searchMatch
        }
    }

    private func matchesLevel(_ level: OSLogEntryLog.Level) -> Bool {
        switch selectedLevel {
        case .all: return true
        case .debug: return level == .debug
        case .info: return level == .info
        case .notice: return level == .notice
        case .error: return level == .error
        case .fault: return level == .fault
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Picker("Time", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .frame(width: 130)

                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .frame(width: 130)

                Picker("Level", selection: $selectedLevel) {
                    ForEach(LogLevelFilter.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }
                .frame(width: 110)

                Spacer()

                Button(action: {
                    Task {
                        await logsService.fetchLogs(timeInterval: selectedTimeRange.timeInterval)
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh logs")

                Button(action: copyLogs) {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy logs to clipboard")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Logs list
            if logsService.isLoading {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(logsService.loadingProgress.isEmpty ? "Loading logs..." : logsService.loadingProgress)
                        .foregroundColor(.secondary)
                    Button("Cancel") {
                        logsService.cancelFetch()
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            } else if let error = logsService.errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task {
                            await logsService.fetchLogs(timeInterval: selectedTimeRange.timeInterval)
                        }
                    }
                }
                Spacer()
            } else if filteredLogs.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No logs found")
                        .foregroundColor(.secondary)
                    if logsService.logs.isEmpty {
                        Button("Load Logs") {
                            Task {
                                await logsService.fetchLogs(timeInterval: selectedTimeRange.timeInterval)
                            }
                        }
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredLogs) { entry in
                            LogEntryRow(entry: entry)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // Status bar
            HStack {
                Text("\(filteredLogs.count) of \(logsService.logs.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if logsService.logs.count >= 5000 {
                    Text("(limit reached)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .task {
            if logsService.logs.isEmpty {
                await logsService.fetchLogs(timeInterval: selectedTimeRange.timeInterval)
            }
        }
        .onChange(of: selectedTimeRange) { _, newValue in
            Task {
                await logsService.fetchLogs(timeInterval: newValue.timeInterval)
            }
        }
    }

    private func copyLogs() {
        let logsText = filteredLogs.map { entry in
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            return "[\(dateFormatter.string(from: entry.date))] [\(entry.levelString)] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logsText, forType: .string)
    }
}

struct LogEntryRow: View {
    let entry: LogsService.LogEntry
    @State private var isExpanded = false

    private var levelColor: Color {
        switch entry.level {
        case .debug: return .gray
        case .info: return .blue
        case .notice: return .green
        case .error: return .orange
        case .fault: return .red
        default: return .gray
        }
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: entry.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 6) {
                Text(dateString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 85, alignment: .leading)

                Text(entry.levelString)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(levelColor)
                    .frame(width: 50, alignment: .leading)

                Text(entry.category)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.purple)
                    .frame(width: 80, alignment: .leading)

                Text(entry.message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(isExpanded ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(entry.level == .error || entry.level == .fault
                    ? levelColor.opacity(0.1)
                    : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}

#Preview {
    LogsSettingsView()
        .frame(width: 500, height: 600)
}
