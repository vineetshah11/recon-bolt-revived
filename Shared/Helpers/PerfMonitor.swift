import Foundation
#if DEBUG
import os
#endif

enum PerfMonitor {
#if DEBUG
	private static let logger = Logger(subsystem: "com.dtl21.Recon-Bolt", category: "Perf")
	
	static func measure<T>(_ label: String, warnOverMs: Double = 4.0, _ block: () throws -> T) rethrows -> T {
		let start = ContinuousClock.now
		let result = try block()
		logDuration(label, start: start, warnOverMs: warnOverMs)
		return result
	}
	
	static func measureAsync<T>(_ label: String, warnOverMs: Double = 4.0, _ block: () async throws -> T) async rethrows -> T {
		let start = ContinuousClock.now
		let result = try await block()
		logDuration(label, start: start, warnOverMs: warnOverMs)
		return result
	}
	
	private static func logDuration(_ label: String, start: ContinuousClock.Instant, warnOverMs: Double) {
		let duration = start.duration(to: .now)
		let ms = Double(duration.components.seconds) * 1000.0
			+ Double(duration.components.attoseconds) / 1e15
		if ms >= warnOverMs {
			let formatted = String(format: "%.2f", ms)
			let isMain = Thread.isMainThread
			logger.notice("[PERF] \(label, privacy: .public): \(formatted, privacy: .public)ms (main=\(isMain))")
		}
	}
	
	static func log(_ tag: String, _ message: String) {
		logger.notice("[\(tag, privacy: .public)] \(message, privacy: .public)")
	}
#else
	@inline(__always)
	static func measure<T>(_ label: String, warnOverMs: Double = 4.0, _ block: () throws -> T) rethrows -> T {
		try block()
	}
	
	@inline(__always)
	static func measureAsync<T>(_ label: String, warnOverMs: Double = 4.0, _ block: () async throws -> T) async rethrows -> T {
		try await block()
	}
	
	@inline(__always)
	static func log(_ tag: String, _ message: String) {}
#endif
}
