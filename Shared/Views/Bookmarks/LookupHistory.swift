import Foundation
import Combine
import ValorantAPI
import UserDefault

@MainActor
final class LookupHistory: ObservableObject {
	private static let maxCount = 3
	static let didImportNotification = Notification.Name("ReconBolt.LookupHistory.didImport")
	
	@UserDefault("LookupHistory.stored")
	private static var sharedStored: [Entry] = []
	
	@UserDefault("LookupHistory.stored")
	private var stored: [Entry] = []
	
	@Published var entries: [Entry] {
		didSet { stored = entries }
	}
	
	private var importObserver: AnyCancellable?
	
	init() {
		entries = _stored.wrappedValue
		importObserver = NotificationCenter.default.publisher(for: Self.didImportNotification)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _ in
				guard let self else { return }
				self.entries = self._stored.wrappedValue
			}
	}
	
#if DEBUG
	init(entries: [Entry]) {
		assert(isInSwiftUIPreview)
		_entries = .init(wrappedValue: entries)
	}
#endif
	
	func lookedUp(_ user: User.ID, location: Location) {
		let entry = Entry(user: user, location: location)
		entries = [entry] + entries
			.filter { $0.user != user }
			.prefix(Self.maxCount - 1)
	}
	
	static func exportEntries(for playerIDs: Set<User.ID>?) -> [Entry] {
		let current = sharedStored
		guard let playerIDs else { return current }
		return current.filter { playerIDs.contains($0.user) }
	}
	
	@discardableResult
	static func importEntries(_ incoming: [Entry], replaceAll: Bool) -> Int {
		var working = replaceAll ? [] : sharedStored
		var changedCount = 0
		
		for entry in incoming {
			if let idx = working.firstIndex(where: { $0.user == entry.user }) {
				if working[idx].location != entry.location {
					working[idx] = entry
					changedCount += 1
				}
			} else {
				working.append(entry)
				changedCount += 1
			}
		}
		
		if working.count > maxCount {
			working = Array(working.prefix(maxCount))
		}
		sharedStored = working
		NotificationCenter.default.post(name: didImportNotification, object: nil)
		return replaceAll ? working.count : changedCount
	}
	
	struct Entry: Hashable, Identifiable, Codable, DefaultsValueConvertible {
		let user: User.ID
		let location: Location
		
		var id: User.ID { user }
	}
}
