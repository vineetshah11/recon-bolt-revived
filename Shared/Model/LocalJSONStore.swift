import Foundation

enum LocalJSONStore {
	private struct UncheckedBox<T>: @unchecked Sendable {
		let value: T
	}
	
	private static let ioQueue = DispatchQueue(label: "com.reconbolt.localjsonstore", qos: .utility)
	
	private static let sharedDecoder: JSONDecoder = {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return decoder
	}()
	
	private static let sharedEncoder: JSONEncoder = {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		return encoder
	}()
	
	private static var didEnsureDirectory = false
	
	static func url(for filename: String) -> URL {
		FolderLocations.localData.appendingPathComponent(filename, isDirectory: false)
	}
	
	static func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
		let fileURL = url(for: filename)
		return ioQueue.sync {
			decodeOnQueue(T.self, from: fileURL)
		}
	}
	
	static func loadAsync<T: Decodable>(_ type: T.Type, from filename: String) async -> T? {
		let fileURL = url(for: filename)
		let box = await withCheckedContinuation { (continuation: CheckedContinuation<UncheckedBox<T?>, Never>) in
			ioQueue.async {
				let decoded = decodeOnQueue(T.self, from: fileURL)
				continuation.resume(returning: UncheckedBox(value: decoded))
			}
		}
		return box.value
	}
	
	static func save<T: Encodable>(_ value: T, to filename: String) {
		let fileURL = url(for: filename)
		let boxed = UncheckedBox(value: value)
		ioQueue.async {
			writeOnQueue(boxed.value, to: fileURL, filename: filename)
		}
	}
	
	static func saveAndWait<T: Encodable>(_ value: T, to filename: String) async {
		let fileURL = url(for: filename)
		let boxed = UncheckedBox(value: value)
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			ioQueue.async {
				writeOnQueue(boxed.value, to: fileURL, filename: filename)
				continuation.resume()
			}
		}
	}
	
	private static func writeOnQueue<T: Encodable>(_ value: T, to fileURL: URL, filename: String) {
		do {
			if !didEnsureDirectory {
				try FileManager.default.createDirectory(
					at: fileURL.deletingLastPathComponent(),
					withIntermediateDirectories: true
				)
				didEnsureDirectory = true
			}
			let data = try sharedEncoder.encode(value)
			try data.write(to: fileURL, options: .atomic)
		} catch {
			print("Failed saving \(filename):", error)
		}
	}
	
	private static func decodeOnQueue<T: Decodable>(_ type: T.Type, from fileURL: URL) -> T? {
		guard let data = try? Data(contentsOf: fileURL) else { return nil }
		return try? sharedDecoder.decode(T.self, from: data)
	}
}
