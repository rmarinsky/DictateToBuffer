import Foundation
import OSLog

/// Service for fetching application logs from the unified logging system.
@MainActor
final class LogsService: ObservableObject {
    static let shared = LogsService()

    @Published var logs: [LogEntry] = []
    @Published var isLoading = false
    @Published var loadingProgress: String = ""
    @Published var errorMessage: String?

    private let subsystem = "com.dictate.buffer"
    private var currentFetchTask: Task<Void, Never>?

    /// Maximum number of log entries to fetch to prevent UI overwhelming
    private let maxEntries = 5000
    /// Batch size for processing entries before yielding
    private let batchSize = 100

    struct LogEntry: Identifiable, Hashable, Sendable {
        let id: UUID
        let date: Date
        let category: String
        let level: OSLogEntryLog.Level
        let message: String

        init(date: Date, category: String, level: OSLogEntryLog.Level, message: String) {
            self.id = UUID()
            self.date = date
            self.category = category
            self.level = level
            self.message = message
        }

        var levelString: String {
            switch level {
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .notice: return "NOTICE"
            case .error: return "ERROR"
            case .fault: return "FAULT"
            default: return "UNKNOWN"
            }
        }

        var levelColor: String {
            switch level {
            case .debug: return "gray"
            case .info: return "blue"
            case .notice: return "green"
            case .error: return "orange"
            case .fault: return "red"
            default: return "gray"
            }
        }
    }

    private init() {}

    /// Cancels any ongoing fetch operation
    func cancelFetch() {
        currentFetchTask?.cancel()
        currentFetchTask = nil
        isLoading = false
        loadingProgress = ""
    }

    /// Fetches logs from the last specified time interval.
    /// - Parameter timeInterval: Time interval in seconds to look back (default: 1 hour)
    func fetchLogs(timeInterval: TimeInterval = 3600) async {
        // Cancel any existing fetch
        currentFetchTask?.cancel()

        isLoading = true
        loadingProgress = "Initializing..."
        errorMessage = nil
        logs = []

        let task = Task { [weak self] in
            guard let self = self else { return }

            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let startDate = Date().addingTimeInterval(-timeInterval)
                let position = store.position(date: startDate)
                let predicate = NSPredicate(format: "subsystem == %@", self.subsystem)
                let entries = try store.getEntries(at: position, matching: predicate)

                // Process entries off the main thread
                let result = await self.processEntries(
                    entries: entries,
                    maxEntries: self.maxEntries,
                    batchSize: self.batchSize
                )

                // Check for cancellation before updating UI
                if Task.isCancelled { return }

                await MainActor.run {
                    self.logs = result.sorted { $0.date > $1.date }
                    self.isLoading = false
                    self.loadingProgress = ""
                }
            } catch {
                if Task.isCancelled { return }

                await MainActor.run {
                    self.errorMessage = "Failed to fetch logs: \(error.localizedDescription)"
                    self.isLoading = false
                    self.loadingProgress = ""
                }
            }
        }

        currentFetchTask = task
        await task.value
    }

    /// Processes log entries in batches off the main thread
    /// - Parameters:
    ///   - entries: The sequence of log entries from OSLogStore
    ///   - maxEntries: Maximum number of entries to process
    ///   - batchSize: Number of entries to process before yielding
    /// - Returns: Array of processed LogEntry objects
    private nonisolated func processEntries(
        entries: AnySequence<OSLogEntry>,
        maxEntries: Int,
        batchSize: Int
    ) async -> [LogEntry] {
        var fetchedLogs: [LogEntry] = []
        fetchedLogs.reserveCapacity(min(maxEntries, 1000))

        var count = 0
        var batchCount = 0

        for entry in entries {
            // Check for cancellation periodically
            if Task.isCancelled { break }

            if let logEntry = entry as? OSLogEntryLog {
                fetchedLogs.append(LogEntry(
                    date: logEntry.date,
                    category: logEntry.category,
                    level: logEntry.level,
                    message: logEntry.composedMessage
                ))
                count += 1
                batchCount += 1

                // Yield after each batch to keep things responsive
                if batchCount >= batchSize {
                    batchCount = 0

                    // Update progress on main thread
                    let currentCount = count
                    await MainActor.run { [weak self] in
                        self?.loadingProgress = "Processing \(currentCount) entries..."
                    }

                    // Yield to allow other work
                    await Task.yield()
                }

                // Stop if we've reached the limit
                if count >= maxEntries {
                    await MainActor.run { [weak self] in
                        self?.loadingProgress = "Reached limit of \(maxEntries) entries"
                    }
                    break
                }
            }
        }

        return fetchedLogs
    }

    /// Exports logs to a string for sharing/copying.
    func exportLogs() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        return logs.map { entry in
            "[\(dateFormatter.string(from: entry.date))] [\(entry.levelString)] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
    }

    /// Clears the in-memory log cache.
    func clearLogs() {
        logs = []
    }
}
