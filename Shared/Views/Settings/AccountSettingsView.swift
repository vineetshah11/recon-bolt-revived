import SwiftUI
import ValorantAPI

struct AccountSettingsView: View {
	@ObservedObject var accountManager: AccountManager
	
	@Binding var loginTarget: LoginTarget?
	var showSignOutButton: Bool = true
	@State var isConfirmingSignOut = false
	
	var body: some View {
		Group {
			Section {
				cells
			} header: {
				Text("Accounts", comment: "Settings: section")
			} footer: {
				VStack(alignment: .leading, spacing: 10) {
					if !accountManager.storedAccounts.isEmpty {
						Text("Swipe left on an account to log out and remove it.")
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
					legalBoilerplate
				}
			}
			
			let isExpired = accountManager.activeAccount?.session.hasExpired == true
			if isExpired || showSignOutButton {
				Section {
					if isExpired {
						HStack {
							Text("Session expired!", comment: "Account Settings: shown when the current account's session has expired")
							Spacer()
							Button {
								loginTarget = .sessionRefresh
							} label: {
								Text("Refresh", comment: "Account Settings: button to refresh expired session")
							}
							.font(.body.bold())
						}
					}
					
					if showSignOutButton {
						Button {
							isConfirmingSignOut = true
						} label: {
							Text("Sign Out of All Accounts", comment: "Account Settings: button")
						}
						.disabled(accountManager.storedAccounts.isEmpty)
						.confirmationDialog(
							Text("Are You Sure?", comment: "Account Settings: title for alert to confirm signing out of all accounts—not always visible; iOS decides when to show this"),
							isPresented: $isConfirmingSignOut
						) {
							Button(role: .destructive) {
								accountManager.clear()
							} label: {
								Text("Sign Out", comment: "Account Settings: button in alert to confirm signing out of all accounts")
							}
						}
					}
				} header: {
					Text("Management", comment: "Settings: section")
				}
			}
		}
	}
	
	@ViewBuilder
	var cells: some View {
		if accountManager.storedAccounts.isEmpty {
			Text("Not signed in yet.", comment: "Account Settings")
			
			Button {
				loginTarget = .firstAccount
			} label: {
				Text("Sign In", comment: "Account Settings: button")
			}
			.font(.body.weight(.medium))
		} else {
			ForEach(accountManager.storedAccounts, id: \.self) { accountID in
				AccountCell(accountID: accountID, accountManager: accountManager)
			}
			.onDelete { accountManager.removeAccounts(at: $0) }
			.onMove { accountManager.storedAccounts.move(fromOffsets: $0, toOffset: $1) }
			
			Button {
				loginTarget = .extraAccount
			} label: {
				Label {
					Text("Add Account", comment: "Account Settings")
						.foregroundStyle(.primary)
				} icon: {
					Image(systemName: "plus")
						.foregroundStyle(.tint)
				}
			}
			
			NavigationLink {
				AccountOverviewView(accountManager: accountManager)
			} label: {
				Label {
					Text("Account Overview")
						.foregroundStyle(.primary)
				} icon: {
					Image(systemName: "person.text.rectangle")
						.foregroundStyle(.tint)
				}
			}
		}
	}
	
	var legalBoilerplate: some View {
		Text(verbatim: "Recon Bolt is not endorsed by Riot Games and does not reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games and all associated properties are trademarks or registered trademarks of Riot Games, Inc.") // legally best not to translate this ig, couldn't find versions in other languages
			.font(.footnote)
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity, alignment: .leading)
	}
	
	init(
		accountManager: AccountManager,
		loginTarget: Binding<LoginTarget?> = .constant(nil),
		showSignOutButton: Bool = true
	) {
		self.accountManager = accountManager
		self._loginTarget = loginTarget
		self.showSignOutButton = showSignOutButton
	}
	
	enum LoginTarget: Hashable, Identifiable {
		case firstAccount
		case extraAccount
		case sessionRefresh
		
		var shouldRestoreCredentials: Bool {
			self != .extraAccount
		}
		
		var id: Self { self }
	}
	
	struct AccountCell: View {
		var accountID: User.ID
		@ObservedObject var accountManager: AccountManager
		@State var loadError: Error?
		
		@LocalData var identity: Player.Identity?
		@LocalData var summary: CareerSummary?
		
		@Environment(\.assets) private var assets
		@Environment(\.seasons) private var seasons
		
		init(accountID: User.ID, accountManager: AccountManager) {
			self.accountID = accountID
			self.accountManager = accountManager
			self._identity = .init(id: accountID)
			self._summary = .init(id: accountID)
		}
		
		private var resolvedTierInfo: CompetitiveTier? {
			guard let assets, let seasons else { return nil }
			if let currentAct = seasons.currentAct(),
			   let currentInfo = summary?.competitiveInfo?.inSeason(currentAct.id) {
				return assets.seasons.tierInfo(number: currentInfo.competitiveTier, in: currentAct.id)
			}
			if let latestRanked = assets.seasons.actsInOrder.reversed().first(where: {
				(summary?.competitiveInfo?.inSeason($0.id)?.competitiveTier ?? 0) >= 3
			}),
			   let info = summary?.competitiveInfo?.inSeason(latestRanked.id) {
				return assets.seasons.tierInfo(number: info.competitiveTier, in: latestRanked.id)
			}
			if let currentAct = seasons.currentAct() {
				return assets.seasons.tierInfo(number: 0, in: currentAct.id)
			}
			return nil
		}
		
		var body: some View {
			let isActive = accountManager.activeAccount?.id == accountID
			let showActiveMarker = isActive && accountManager.storedAccounts.count > 1
			
			Button {
				withAnimation {
					do {
						try accountManager.setActive(accountID)
					} catch {
						print(error)
						loadError = error
					}
				}
			} label: {
				HStack(spacing: 12) {
					PlayerCardImage.small(identity?.cardID)
						.frame(width: 44, height: 44)
						.cornerRadius(8)
						.overlay {
							if showActiveMarker {
								RoundedRectangle(cornerRadius: 8, style: .continuous)
									.stroke(Color.accentColor, lineWidth: 1.5)
							}
						}
						.overlay(alignment: .bottomTrailing) {
							if showActiveMarker {
								Image(systemName: "checkmark.circle.fill")
									.font(.caption.bold())
									.foregroundStyle(Color.accentColor)
									.background(Circle().fill(Color.secondaryGroupedBackground).padding(1))
									.offset(x: 4, y: 4)
							}
						}
					
					VStack(alignment: .leading, spacing: 2) {
						UserLabel(userID: accountID, shouldAutoUpdate: false, allowTapToCopy: false)
							.foregroundStyle(.primary)
							.lineLimit(1)
						
						if let level = identity?.accountLevel, level > 0 {
							Text("Level \(level)")
								.font(.subheadline)
								.foregroundStyle(.secondary)
						}
					}
					
					Spacer(minLength: 8)
					
					if let tierInfo = resolvedTierInfo {
						CompetitiveTierImage(tierInfo: tierInfo)
							.frame(width: 36, height: 36)
					}
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.padding(.vertical, 2)
			.alert(Text("Could Not Load Account!"), for: $loadError)
			.withLocalData($identity, id: accountID, shouldAutoUpdate: false)
			.withLocalData($summary, id: accountID, shouldAutoUpdate: false)
			.task(id: accountID) {
				let client: ValorantClient? = isActive
					? accountManager.activeAccount?.client
					: accountManager.makeReadOnlyClient(for: accountID)
				guard let client else { return }
				async let userTask: ()? = try? client.fetchUsers(for: [accountID])
				async let identityTask: ()? = try? client.fetchIdentity(for: accountID, forceFetch: false)
				async let summaryTask: ()? = try? client.fetchCareerSummary(for: accountID, forceFetch: false)
				_ = await (userTask, identityTask, summaryTask)
			}
		}
	}
}

struct ProExclusiveBadge: View {
	var body: some View {
		Text("Pro", comment: "Badge applied to buttons that are exclusive to Pro, e.g. in the account settings")
			.font(.callout.smallCaps())
			.padding(.horizontal, 4)
			.offset(y: -1) // visually center the small caps
			.foregroundColor(.white)
			.blendMode(.destinationOut)
			.background(RoundedRectangle(cornerRadius: 4, style: .continuous))
			.compositingGroup()
	}
}

#if DEBUG
struct AccountSettingsView_Previews: PreviewProvider {
	static var previews: some View {
		List { AccountSettingsView(accountManager: .mocked) }
			.withToolbar()
		List { AccountSettingsView(accountManager: .mockEmpty) }
			.withToolbar()
	}
}
#endif
