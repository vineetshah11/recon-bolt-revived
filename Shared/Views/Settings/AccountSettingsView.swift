import SwiftUI

import ValorantAPI

import UserDefault

private struct AccountOverviewSection: View {

	let accountManager: AccountManager

	@State private var loaded: AccountOverviewLoaded? = nil

	@State private var isLoading = false

	var body: some View {

		Section {

			if let l = loaded {

				HStack(spacing: 14) {

					VStack(alignment: .leading, spacing: 4) {

						UserLabel(userID: l.accountID)

							.tint(.primary)

						Text(l.tierAndRankLabel)

							.font(.subheadline)

							.foregroundStyle(.secondary)

					}

					VStack(spacing: 4) {

						if l.tier != nil {

							CompetitiveTierImage(tierInfo: l.tier)

								.resizable()

								.aspectRatio(contentMode: .fit)

								.frame(width: 44, height: 44)

								.foregroundStyle(l.tier?.color ?? .secondary)

							Text(String(format: "%@ %d", l.tier?.name ?? "Unranked", l.tier?.number ?? 0))

								.font(.caption.bold())

							Text(l.currentSeasonName)

								.font(.caption2)

								.foregroundStyle(.secondary)

						} else {

							Text("Unranked")

								.font(.subheadline)

								.foregroundStyle(.secondary)

						}

					}

				}

			} else if isLoading {

				HStack {

					Text("Loading overview...")

					Spacer()

				}

			} else {

				EmptyView()

			}

		} header: {

			Text("Overview")

		}

	}

	init(accountManager: AccountManager) {

		self.accountManager = accountManager

	}

	task(id: accountManager.activeAccount?.id) {

		guard let id = accountManager.activeAccount?.id else {

			loaded = nil

			return

		}

		isLoading = true

		defer { isLoading = false }

		do {

			let client = accountManager.activeAccount?.client

			async let seasons = getSeasons()

			async let user = client?.getUser(byID: id)

			async let tier = client?.getCompetitiveTierRating(of: id)

			let (s, u, t) = try await (seasons, user, tier)

			let currentSeason = s?.current

			let currentActID = currentSeason?.id

			let rank = try? await client?.getCompetitiveRank(of: id, seasonID: currentActID)

			loaded = AccountOverviewLoaded(

				accountID: id,

				user: u,

				tier: t,

				rank: rank,

				currentSeason: currentSeason

			)

		} catch {

			loaded = nil

			print("could not load account overview: \(error)")

		}

	}

}

struct AccountSettingsView: View {

	@ObservedObject var accountManager: AccountManager

	@Binding var loginTarget: LoginTarget?

	var showSignOutButton: Bool = true

	@State var isConfirmingSignOut = false

	@Environment(\.ownsProVersion) private var ownsProVersion

	var body: some View {

		Group {

			Section {

				cells

			} header: {

				Text("Accounts", comment: "Settings: section")

			} footer: {

				legalBoilerplate

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

			.moveDisabled(!ownsProVersion)

			Button {

				loginTarget = .extraAccount

			} label: {

				HStack {

					Label {

						Text("Add another Account", comment: "Account Settings")

					} icon: {

						// the icon doesn't get tinted correctly if i don't do this…

						Image(systemName: "plus")

							.foregroundColor(ownsProVersion ? nil : .primary.opacity(0.25))

					}

					Spacer()

					if !ownsProVersion {

						ProExclusiveBadge()

					}

				}

			}

			.disabled(!ownsProVersion)

		}

	}

	var legalBoilerplate: some View {

		Text(verbatim: "Vantage is not endorsed by Riot Games and does not reflect the views or opinions of Riot Games or anyone officially involved in producing or managing Riot Games properties. Riot Games and all associated properties are trademarks or registered trademarks of Riot Games, Inc.") // legally best not to translate this ig, couldn't find versions in other languages

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

		@Environment(\.ownsProVersion) private var ownsProVersion

		var body: some View {

			let isActive = accountManager.activeAccount?.id == accountID

			let index = accountManager.storedAccounts.firstIndex(of: accountID)

			HStack {

				Button {

					withAnimation {

						do {

							try accountManager.toggleActive(accountID)

						} catch {

							print(error)

							loadError = error

						}

					}

				} label: {

					Label {

						UserLabel(userID: accountID)

							.tint(.primary)

					} icon: {

						Image(systemName: "checkmark")

							.opacity(isActive ? 1 : 0)

					}

				}

				.disabled(!ownsProVersion && !isActive && (index ?? 0) > 0)

				Spacer()

			}

			.alert(Text("Could Not Load Account!"), for: $loadError)

			.deleteDisabled(isActive)

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

private struct AccountOverviewLoaded {

	let accountID: User.ID

	let user: User?

	let tier: CompetitiveTier?

	let rank: CompetitiveRank?

	let currentSeason: Act?

	var tierAndRankLabel: String {

		if let tier, let tierName = tier.name.nonEmpty, let number = tier.number.nonEmpty {

			return "\(tierName) \(number)"

		}

		return "Unranked"

	}

	var currentSeasonName: String {

		guard let currentSeason else { return "" }

		if let episode = currentSeason.episode {

			return "\(episode.name) // \(currentSeason.name)"

		}

		return currentSeason.name

	}

}

#endif
