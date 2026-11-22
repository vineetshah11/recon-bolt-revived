import Foundation

enum LocalJSONStore {
	private static let decoder: JSONDecoder = {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return decoder
	}()
	
	private static let encoder: JSONEncoder = {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return encoder
	}()
	
	static func url(for filename: String) -> URL {
		FolderLocations.localData.appendingPathComponent(filename, isDirectory: false)
	}
	
	static func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
		let fileURL = url(for: filename)
		guard let data = try? Data(contentsOf: fileURL) else { return nil }
		return try? decoder.decode(T.self, from: data)
	}
	
	static func save<T: Encodable>(_ value: T, to filename: String) {
		let fileURL = url(for: filename)
		do {
			try FileManager.default.createDirectory(
				at: fileURL.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			let data = try encoder.encode(value)
			try data.write(to: fileURL, options: .atomic)
		} catch {
			print("Failed saving \(filename):", error)
		}
	}
}
