import Foundation
import ValorantAPI

enum BackupSemanticValidator {
	/// 2020-01-01T00:00:00Z
	private static let earliestValidDate = Date(timeIntervalSince1970: 1_577_836_800)
	private static let maxFutureSkewSeconds: TimeInterval = 7 * 86_400
	private static let maxMatchLengthMillis = 12 * 3_600_000
	
	private static func isValidDate(_ date: Date, now: Date = Date()) -> Bool {
		date >= earliestValidDate && date <= now.addingTimeInterval(maxFutureSkewSeconds)
	}
	
	static func validateMatchLists(_ entries: [LocalDataManager<MatchList>.Entry]) throws {
		let now = Date()
		guard entries.count <= 10_000 else {
			throw BackupError.semanticValidationFailed("Too many match lists (\(entries.count)).")
		}
		for entry in entries {
			guard isValidDate(entry.lastUpdate, now: now) else {
				throw BackupError.semanticValidationFailed("Match list timestamp out of range.")
			}
			guard entry.object.matches.count <= 20_000 else {
				throw BackupError.semanticValidationFailed("Match list contains too many matches (\(entry.object.matches.count)).")
			}
			for update in entry.object.matches {
				guard isValidDate(update.startTime, now: now) else {
					throw BackupError.semanticValidationFailed("Competitive update start time out of range.")
				}
				guard (0...50).contains(update.tierBeforeUpdate),
					  (0...50).contains(update.tierAfterUpdate) else {
					throw BackupError.semanticValidationFailed("Competitive tier out of valid range.")
				}
				guard (-500...20_000).contains(update.tierProgressBeforeUpdate),
					  (-500...20_000).contains(update.tierProgressAfterUpdate) else {
					throw BackupError.semanticValidationFailed("Ranked rating value out of valid range.")
				}
				guard (-300...300).contains(update.ratingEarned),
					  (0...200).contains(update.performanceBonus),
					  (-200...200).contains(update.afkPenalty) else {
					throw BackupError.semanticValidationFailed("RR delta out of valid range.")
				}
			}
		}
	}
	
	static func validateMatchDetails(_ entries: [LocalDataManager<MatchDetails>.Entry]) throws {
		let now = Date()
		guard entries.count <= 50_000 else {
			throw BackupError.semanticValidationFailed("Too many match details (\(entries.count)).")
		}
		for entry in entries {
			let match = entry.object
			guard isValidDate(entry.lastUpdate, now: now),
				  isValidDate(match.matchInfo.gameStart, now: now) else {
				throw BackupError.semanticValidationFailed("Match timestamp out of valid range.")
			}
			guard (0...maxMatchLengthMillis).contains(match.matchInfo.gameLengthMillis) else {
				throw BackupError.semanticValidationFailed("Match duration out of valid range.")
			}
			guard (1...32).contains(match.players.count) else {
				throw BackupError.semanticValidationFailed("Match player count (\(match.players.count)) out of range.")
			}
			guard match.roundResults.count <= 300, match.kills.count <= 5_000 else {
				throw BackupError.semanticValidationFailed("Match round or kill log size out of range.")
			}
			
			for team in match.teams {
				guard (0...300).contains(team.roundsPlayed),
					  (0...300).contains(team.roundsWon),
					  team.roundsWon <= team.roundsPlayed + 2 else {
					throw BackupError.semanticValidationFailed("Team round counts are inconsistent.")
				}
			}
			
			for player in match.players {
				guard (0...50).contains(player.competitiveTier) else {
					throw BackupError.semanticValidationFailed("Player competitive tier out of valid range.")
				}
				if let level = player.accountLevel, !(0...10_000).contains(level) {
					throw BackupError.semanticValidationFailed("Player account level (\(level)) out of valid range.")
				}
				if let stats = player.stats {
					guard (0...1_000).contains(stats.kills),
						  (0...1_000).contains(stats.deaths),
						  (0...1_000).contains(stats.assists),
						  (0...300).contains(stats.roundsPlayed),
						  (0...1_000_000).contains(stats.score),
						  (0...maxMatchLengthMillis).contains(stats.playtimeMillis) else {
						throw BackupError.semanticValidationFailed("Player match stats contain impossible values.")
					}
					if !match.kills.isEmpty && stats.kills > match.kills.count + 10 {
						throw BackupError.semanticValidationFailed("Player kills exceed recorded match kill events.")
					}
				}
			}
			
			for round in match.roundResults {
				guard (0...300).contains(round.number) else {
					throw BackupError.semanticValidationFailed("Round index out of range.")
				}
				for pStat in round.playerStats {
					guard pStat.kills.count <= 50,
						  (-50_000...100_000).contains(pStat.combatScore) else {
						throw BackupError.semanticValidationFailed("Round player stats out of range.")
					}
					for dmg in pStat.damageDealt {
						guard (0...50_000).contains(dmg.damage),
							  (0...500).contains(dmg.headshots),
							  (0...500).contains(dmg.bodyshots),
							  (0...500).contains(dmg.legshots) else {
							throw BackupError.semanticValidationFailed("Round damage breakdown out of range.")
						}
					}
				}
			}
		}
	}
	
	static func validateCareerSummaries(_ entries: [LocalDataManager<CareerSummary>.Entry]) throws {
		let now = Date()
		guard entries.count <= 20_000 else {
			throw BackupError.semanticValidationFailed("Too many career summaries.")
		}
		for entry in entries {
			guard isValidDate(entry.lastUpdate, now: now) else {
				throw BackupError.semanticValidationFailed("Career summary timestamp out of range.")
			}
			for queue in entry.object.infoByQueue.values {
				for season in (queue.bySeason ?? [:]).values {
					guard (0...50).contains(season.competitiveTier),
						  (0...50).contains(season.actRank),
						  (0...50_000).contains(season.winCount),
						  (0...50_000).contains(season.winCountIncludingPlacements),
						  (0...100_000).contains(season.gameCount),
						  season.winCount <= season.gameCount + 50,
						  (-500...20_000).contains(season.rankedRating),
						  (0...100_000).contains(season.leaderboardRank) else {
						throw BackupError.semanticValidationFailed("Career seasonal stats out of valid range.")
					}
				}
			}
		}
	}
	
	static func validateUsers(_ entries: [LocalDataManager<User>.Entry]) throws {
		let now = Date()
		guard entries.count <= 100_000 else {
			throw BackupError.semanticValidationFailed("Too many user entries.")
		}
		for entry in entries {
			guard isValidDate(entry.lastUpdate, now: now),
				  entry.object.gameName.count <= 128,
				  entry.object.tagLine.count <= 64 else {
				throw BackupError.semanticValidationFailed("User record failed validation.")
			}
		}
	}
	
	static func validatePlayerIdentities(_ entries: [LocalDataManager<Player.Identity>.Entry]) throws {
		let now = Date()
		guard entries.count <= 100_000 else {
			throw BackupError.semanticValidationFailed("Too many player identity entries.")
		}
		for entry in entries {
			guard isValidDate(entry.lastUpdate, now: now),
				  (0...10_000).contains(entry.object.accountLevel) else {
				throw BackupError.semanticValidationFailed("Player identity level out of valid range.")
			}
		}
	}
	
	static func validateUsernameHistory(_ records: [User.ID: [NameHistoryRecord]]) throws {
		let now = Date()
		guard records.count <= 100_000 else {
			throw BackupError.semanticValidationFailed("Too many username histories.")
		}
		for list in records.values {
			guard list.count <= 1_000 else {
				throw BackupError.semanticValidationFailed("Username timeline too long.")
			}
			for record in list {
				guard record.gameName.count <= 128,
					  record.tagLine.count <= 64,
					  isValidDate(record.firstSeen, now: now),
					  isValidDate(record.lastSeen, now: now),
					  record.firstSeen <= record.lastSeen.addingTimeInterval(60) else {
					throw BackupError.semanticValidationFailed("Username history record invalid.")
				}
			}
		}
	}
	
	static func validateBookmarks(_ entries: [BookmarkList.Entry]) throws {
		guard entries.count <= 10_000 else {
			throw BackupError.semanticValidationFailed("Too many bookmarks.")
		}
		for entry in entries {
			guard !entry.location.region.isEmpty,
				  entry.location.region.count <= 32,
				  !entry.location.shard.isEmpty,
				  entry.location.shard.count <= 32 else {
				throw BackupError.semanticValidationFailed("Bookmark region/shard invalid.")
			}
		}
	}
	
	static func validateLookupHistory(_ entries: [LookupHistory.Entry]) throws {
		guard entries.count <= 100 else {
			throw BackupError.semanticValidationFailed("Lookup history exceeds expected bounds.")
		}
		for entry in entries {
			guard !entry.location.region.isEmpty, entry.location.region.count <= 32,
				  !entry.location.shard.isEmpty, entry.location.shard.count <= 32 else {
				throw BackupError.semanticValidationFailed("Lookup history region invalid.")
			}
		}
	}
	
	static func validateShopHistory(_ days: [ShopHistoryDay]) throws {
		let now = Date()
		guard days.count <= 20_000 else {
			throw BackupError.semanticValidationFailed("Too many shop history days.")
		}
		for day in days {
			guard day.id.count == 10,
				  isValidDate(day.date, now: now),
				  day.offerSkinLevelIDs.count <= 16,
				  (day.nightMarketLevelIDs?.count ?? 0) <= 16,
				  (day.accessoryOffers?.count ?? 0) <= 16 else {
				throw BackupError.semanticValidationFailed("Shop history day entry invalid.")
			}
		}
	}
	
	static func validateSeasonGoals(_ goals: [SeasonGoal]) throws {
		let now = Date()
		guard goals.count <= 2_000 else {
			throw BackupError.semanticValidationFailed("Too many season goals.")
		}
		for goal in goals {
			guard (0...50).contains(goal.targetTier),
				  (0...50).contains(goal.baselineTier),
				  (-500...20_000).contains(goal.baselineRR),
				  (0...20_000).contains(goal.baselineElo),
				  isValidDate(goal.createdAt, now: now) else {
				throw BackupError.semanticValidationFailed("Season goal values out of valid range.")
			}
		}
	}
	
	static func validateProgressTimeline(_ points: [ProgressTimelinePoint]) throws {
		let now = Date()
		guard points.count <= 25_000 else {
			throw BackupError.semanticValidationFailed("Too many progress timeline entries.")
		}
		for point in points {
			guard point.dayKey.count == 10,
				  isValidDate(point.recordedAt, now: now),
				  point.accountLevel.map({ (0...10_000).contains($0) }) ?? true,
				  point.accountXP.map({ (0...50_000).contains($0) }) ?? true,
				  point.leaderboardRank.map({ (1...500_000).contains($0) }) ?? true,
				  point.competitiveTier.map({ (0...50).contains($0) }) ?? true,
				  point.rankedRating.map({ (-500...20_000).contains($0) }) ?? true,
				  point.vp.map({ (0...50_000_000).contains($0) }) ?? true,
				  point.rp.map({ (0...50_000_000).contains($0) }) ?? true,
				  point.kc.map({ (0...50_000_000).contains($0) }) ?? true else {
				throw BackupError.semanticValidationFailed("Progress timeline entry values out of valid range.")
			}
		}
	}
	
	static func validateLoadoutPresets(_ presets: [LoadoutPreset]) throws {
		let now = Date()
		guard presets.count <= 5_000 else {
			throw BackupError.semanticValidationFailed("Too many loadout presets.")
		}
		for preset in presets {
			guard preset.name.count <= 128,
				  isValidDate(preset.createdAt, now: now),
				  isValidDate(preset.updatedAt, now: now),
				  preset.loadout.guns.count <= 64,
				  (preset.includedWeapons?.count ?? 0) <= 64,
				  preset.bannerImageData.map({ $0.count <= 512_000 }) ?? true else {
				throw BackupError.semanticValidationFailed("Loadout preset invalid.")
			}
		}
	}
	
	static func validateFavoritesPresets(_ presets: [FavoritesPreset]) throws {
		let now = Date()
		guard presets.count <= 5_000 else {
			throw BackupError.semanticValidationFailed("Too many favorites presets.")
		}
		for preset in presets {
			guard preset.name.count <= 128,
				  isValidDate(preset.createdAt, now: now),
				  isValidDate(preset.updatedAt, now: now),
				  preset.itemIDs.count <= 10_000,
				  preset.bannerImageData.map({ $0.count <= 512_000 }) ?? true else {
				throw BackupError.semanticValidationFailed("Favorites preset invalid.")
			}
		}
	}
	
	static func validateSettingsSnapshots(_ snapshots: [PlayerSettingsSnapshot]) throws {
		let now = Date()
		guard snapshots.count <= 2_000 else {
			throw BackupError.semanticValidationFailed("Too many settings snapshots.")
		}
		for snapshot in snapshots {
			guard snapshot.title.count <= 128,
				  snapshot.rawData.count <= 2_000_000,
				  isValidDate(snapshot.createdAt, now: now) else {
				throw BackupError.semanticValidationFailed("Settings snapshot invalid.")
			}
		}
	}
	
	static func validateSocialFriends(_ accounts: [String: SocialFriendsBackup]) throws {
		guard accounts.count <= 100 else {
			throw BackupError.semanticValidationFailed("Too many social accounts.")
		}
		for account in accounts.values {
			guard account.friendsByJID.count <= 5_000,
				  account.pinnedFriendJIDs.count <= 5_000,
				  account.changeEvents.count <= 1_000 else {
				throw BackupError.semanticValidationFailed("Social friends payload exceeds valid limits.")
			}
		}
	}
	
	static func validateSocialMessages(_ accounts: [String: [String: [XMPPChatMessage]]]) throws {
		let now = Date()
		guard accounts.count <= 100 else {
			throw BackupError.semanticValidationFailed("Too many social message accounts.")
		}
		for conversations in accounts.values {
			guard conversations.count <= 2_000 else {
				throw BackupError.semanticValidationFailed("Too many social conversations.")
			}
			for messages in conversations.values {
				guard messages.count <= 2_000 else {
					throw BackupError.semanticValidationFailed("Conversation message count out of range.")
				}
				for msg in messages {
					guard msg.body.count <= 32_768,
						  isValidDate(msg.timestamp, now: now) else {
						throw BackupError.semanticValidationFailed("Chat message invalid.")
					}
				}
			}
		}
	}
	
	static func validateWishlist(_ entries: [WishlistEntry]) throws {
		let now = Date()
		guard entries.count <= 5_000 else {
			throw BackupError.semanticValidationFailed("Too many wishlist entries.")
		}
		for entry in entries {
			guard isValidDate(entry.addedAt, now: now) else {
				throw BackupError.semanticValidationFailed("Wishlist timestamp invalid.")
			}
		}
	}
	
	static func validateLineupFavorites(_ guides: [LineupGuide]) throws {
		guard guides.count <= 5_000 else {
			throw BackupError.semanticValidationFailed("Too many lineup favorites.")
		}
		for guide in guides {
			guard guide.id.count <= 128, guide.title.count <= 512 else {
				throw BackupError.semanticValidationFailed("Lineup favorite entry invalid.")
			}
		}
	}
	
	static func validateAppSettings(_ snapshot: AppSettings.BackupSnapshot) throws {
		guard (0...3650).contains(snapshot.matchRetentionDays),
			  (1...168).contains(snapshot.notificationLeadTimeHours),
			  snapshot.customAccentColorComponents.count <= 128 else {
			throw BackupError.semanticValidationFailed("App settings values out of range.")
		}
	}
}
