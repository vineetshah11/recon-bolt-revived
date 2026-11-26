import Foundation
import CryptoKit

struct VerifiedBackupArchive {
	let flags: UInt16
	let manifest: BackupManifest
	let manifestBytes: Data
	let integrity: BackupIntegrityBlock
	let wireChunksByID: [String: Data]
	let trustStatus: BackupTrustStatus
	
	var isPasswordEncrypted: Bool {
		(flags & BackupContainer.Flag.passwordEncrypted) != 0
	}
}

enum BackupContainer {
	static let magic = Data([0x52, 0x42, 0x42, 0x4B]) // "RBBK"
	static let currentFormatVersion: UInt16 = 1
	
	enum Flag {
		static let passwordEncrypted: UInt16 = 1 << 0
		static let allowedMask: UInt16 = passwordEncrypted
	}
	
	private static let maxManifestBytes = 16 * 1024 * 1024
	private static let maxModuleCount = 256
	private static let maxModuleIDBytes = 256
	private static let maxWireChunkBytes = 256 * 1024 * 1024
	private static let maxIntegrityBytes = 64 * 1024
	
	struct RawModuleInput {
		let kindID: String
		let schemaVersion: Int
		let itemCount: Int
		let rawJSON: Data
	}
	
	static func signedInput(flags: UInt16, manifestBytes: Data) -> Data {
		var result = Data("RBBK:v1:integrity:".utf8)
		var beFlags = flags.bigEndian
		Swift.withUnsafeBytes(of: &beFlags) { result.append(contentsOf: $0) }
		result.append(manifestBytes)
		return result
	}
	
	private static func moduleAAD(exportID: UUID, moduleID: String, plaintextSHA256: String) -> Data {
		Data("RBBK:v1:\(exportID.uuidString):\(moduleID):\(plaintextSHA256)".utf8)
	}
	
	static func buildArchive(
		exportID: UUID = UUID(),
		createdAt: Date = Date(),
		appVersion: String,
		players: [BackupPlayerSummary],
		modules: [RawModuleInput],
		password: String?
	) throws -> (data: Data, manifest: BackupManifest, fingerprint: String) {
		guard !modules.isEmpty else {
			throw BackupError.emptySelection
		}
		
		let trimmedPassword: String?
		if let password, !password.isEmpty {
			trimmedPassword = password
		} else {
			trimmedPassword = nil
		}
		
		var encryptionMetadata: BackupEncryptionMetadata?
		var encKey: SymmetricKey?
		var authKey: SymmetricKey?
		
		if let trimmedPassword {
			let salt = try BackupCrypto.randomBytes(count: 32)
			let iterations = BackupCrypto.defaultPBKDF2Iterations
			let masterKey = try BackupCrypto.derivePBKDF2Key(
				password: trimmedPassword,
				salt: salt,
				iterations: iterations
			)
			let derived = BackupCrypto.deriveEncryptionAndAuthKeys(masterKey: masterKey, salt: salt)
			encKey = derived.encKey
			authKey = derived.authKey
			encryptionMetadata = BackupEncryptionMetadata(
				algorithm: "AES-256-GCM",
				kdf: "PBKDF2-HMAC-SHA256",
				iterations: iterations,
				saltBase64: salt.base64EncodedString()
			)
		}
		
		var descriptors: [BackupModuleDescriptor] = []
		var wireChunks: [(id: String, data: Data)] = []
		descriptors.reserveCapacity(modules.count)
		wireChunks.reserveCapacity(modules.count)
		
		for module in modules {
			let plaintextSHA = BackupCrypto.sha256Hex(module.rawJSON)
			let compressed = try BackupCrypto.compressLZFSE(module.rawJSON)
			let wireData: Data
			if let encKey {
				let aad = moduleAAD(exportID: exportID, moduleID: module.kindID, plaintextSHA256: plaintextSHA)
				wireData = try BackupCrypto.encryptModule(compressed, using: encKey, aad: aad)
			} else {
				wireData = compressed
			}
			let wireSHA = BackupCrypto.sha256Hex(wireData)
			
			descriptors.append(
				BackupModuleDescriptor(
					id: module.kindID,
					schemaVersion: module.schemaVersion,
					compression: "lzfse",
					itemCount: module.itemCount,
					uncompressedBytes: module.rawJSON.count,
					wireBytes: wireData.count,
					wireSHA256: wireSHA,
					plaintextSHA256: plaintextSHA
				)
			)
			wireChunks.append((id: module.kindID, data: wireData))
		}
		
		let manifest = BackupManifest(
			formatVersion: Int(currentFormatVersion),
			exportID: exportID,
			createdAt: createdAt,
			appVersion: appVersion,
			encryption: encryptionMetadata,
			players: players,
			modules: descriptors
		)
		
		let encoder = BackupCoders.makeEncoder()
		let manifestBytes = try encoder.encode(manifest)
		let flags: UInt16 = (encKey != nil) ? Flag.passwordEncrypted : 0
		let authInput = signedInput(flags: flags, manifestBytes: manifestBytes)
		
		let appHMAC = BackupCrypto.computeAppHMAC(for: authInput)
		let signed = try DeviceSigningKeyStore.sign(authInput)
		let passwordHMAC = authKey.map { BackupCrypto.computePasswordHMAC(for: authInput, using: $0) }
		
		let integrity = BackupIntegrityBlock(
			hmacAlgorithm: "HMAC-SHA256",
			appHMACBase64: appHMAC.base64EncodedString(),
			signatureAlgorithm: "ECDSA-P256-SHA256",
			signerPublicKeyBase64: signed.publicKeyX963.base64EncodedString(),
			signerFingerprint: signed.fingerprint,
			deviceSignatureBase64: signed.signatureDER.base64EncodedString(),
			passwordHMACBase64: passwordHMAC?.base64EncodedString()
		)
		let integrityBytes = try encoder.encode(integrity)
		
		var output = Data()
		output.append(magic)
		appendUInt16(currentFormatVersion, to: &output)
		appendUInt16(flags, to: &output)
		appendLengthPrefixed(manifestBytes, to: &output)
		appendUInt32(UInt32(wireChunks.count), to: &output)
		for chunk in wireChunks {
			appendLengthPrefixed(Data(chunk.id.utf8), to: &output)
			appendLengthPrefixed(chunk.data, to: &output)
		}
		appendLengthPrefixed(integrityBytes, to: &output)
		
		return (output, manifest, signed.fingerprint)
	}
	
	static func inspectArchive(_ data: Data) throws -> VerifiedBackupArchive {
		var cursor = BinaryCursor(data: data)
		
		let fileMagic = try cursor.readBytes(magic.count)
		guard fileMagic == magic else {
			throw BackupError.invalidFormat("Missing RBBK header.")
		}
		
		let formatVersion = try cursor.readUInt16()
		guard formatVersion == currentFormatVersion else {
			throw BackupError.unsupportedVersion(Int(formatVersion))
		}
		
		let flags = try cursor.readUInt16()
		guard (flags & ~Flag.allowedMask) == 0 else {
			throw BackupError.unsupportedVersion(Int(formatVersion))
		}
		
		let manifestBytes = try cursor.readLengthPrefixed(maxBytes: maxManifestBytes)
		let moduleCount = Int(try cursor.readUInt32())
		guard moduleCount > 0, moduleCount <= maxModuleCount else {
			throw BackupError.invalidFormat("Invalid module count (\(moduleCount)).")
		}
		
		var orderedModuleIDs: [String] = []
		var wireChunksByID: [String: Data] = [:]
		orderedModuleIDs.reserveCapacity(moduleCount)
		wireChunksByID.reserveCapacity(moduleCount)
		
		for _ in 0..<moduleCount {
			let idBytes = try cursor.readLengthPrefixed(maxBytes: maxModuleIDBytes)
			guard let moduleID = String(data: idBytes, encoding: .utf8), !moduleID.isEmpty else {
				throw BackupError.invalidFormat("Invalid UTF-8 module identifier.")
			}
			guard wireChunksByID[moduleID] == nil else {
				throw BackupError.integrityViolation("Duplicate module '\(moduleID)'")
			}
			let payload = try cursor.readLengthPrefixed(maxBytes: maxWireChunkBytes)
			orderedModuleIDs.append(moduleID)
			wireChunksByID[moduleID] = payload
		}
		
		let integrityBytes = try cursor.readLengthPrefixed(maxBytes: maxIntegrityBytes)
		try cursor.assertEOF()
		
		let decoder = BackupCoders.makeDecoder()
		let manifest: BackupManifest
		let integrity: BackupIntegrityBlock
		do {
			manifest = try decoder.decode(BackupManifest.self, from: manifestBytes)
			integrity = try decoder.decode(BackupIntegrityBlock.self, from: integrityBytes)
		} catch {
			throw BackupError.invalidFormat("Corrupted manifest or integrity metadata.")
		}
		
		guard manifest.formatVersion == Int(currentFormatVersion) else {
			throw BackupError.unsupportedVersion(manifest.formatVersion)
		}
		guard manifest.modules.map(\.id) == orderedModuleIDs else {
			throw BackupError.integrityViolation("Manifest module list does not match archive sections")
		}
		
		for descriptor in manifest.modules {
			guard let wireChunk = wireChunksByID[descriptor.id] else {
				throw BackupError.integrityViolation("Missing module payload for '\(descriptor.id)'")
			}
			guard wireChunk.count == descriptor.wireBytes else {
				throw BackupError.integrityViolation("Byte length mismatch for module '\(descriptor.id)'")
			}
			let actualWireHash = BackupCrypto.sha256Hex(wireChunk)
			guard actualWireHash == descriptor.wireSHA256.lowercased() else {
				throw BackupError.integrityViolation("SHA-256 mismatch for module '\(descriptor.id)'")
			}
		}
		
		let authInput = signedInput(flags: flags, manifestBytes: manifestBytes)
		
		guard integrity.hmacAlgorithm == "HMAC-SHA256",
			  let appHMAC = Data(base64Encoded: integrity.appHMACBase64),
			  BackupCrypto.verifyAppHMAC(appHMAC, for: authInput) else {
			throw BackupError.integrityViolation("Application HMAC verification failed")
		}
		
		guard integrity.signatureAlgorithm == "ECDSA-P256-SHA256",
			  let publicKey = Data(base64Encoded: integrity.signerPublicKeyBase64),
			  let signature = Data(base64Encoded: integrity.deviceSignatureBase64),
			  DeviceSigningKeyStore.fingerprint(for: publicKey) == integrity.signerFingerprint,
			  DeviceSigningKeyStore.verify(signatureDER: signature, for: authInput, publicKeyX963: publicKey) else {
			throw BackupError.integrityViolation("Device ECDSA signature verification failed")
		}
		
		let isEncryptedFlag = (flags & Flag.passwordEncrypted) != 0
		if isEncryptedFlag {
			guard let enc = manifest.encryption,
				  enc.algorithm == "AES-256-GCM",
				  enc.kdf == "PBKDF2-HMAC-SHA256",
				  (BackupCrypto.minPBKDF2Iterations...BackupCrypto.maxPBKDF2Iterations).contains(enc.iterations),
				  let salt = Data(base64Encoded: enc.saltBase64),
				  salt.count >= 16,
				  let passwordHMACB64 = integrity.passwordHMACBase64,
				  Data(base64Encoded: passwordHMACB64) != nil else {
				throw BackupError.integrityViolation("Invalid encryption header")
			}
		} else {
			guard manifest.encryption == nil, integrity.passwordHMACBase64 == nil else {
				throw BackupError.integrityViolation("Unexpected encryption metadata on unencrypted archive")
			}
		}
		
		let trustStatus: BackupTrustStatus
		if let localPubKey = DeviceSigningKeyStore.currentPublicKeyX963(), localPubKey == publicKey {
			trustStatus = .verifiedThisDevice(fingerprint: integrity.signerFingerprint)
		} else {
			trustStatus = .verifiedOtherDevice(fingerprint: integrity.signerFingerprint)
		}
		
		return VerifiedBackupArchive(
			flags: flags,
			manifest: manifest,
			manifestBytes: manifestBytes,
			integrity: integrity,
			wireChunksByID: wireChunksByID,
			trustStatus: trustStatus
		)
	}
	
	static func unlockEncryptionKey(
		for archive: VerifiedBackupArchive,
		password: String
	) throws -> SymmetricKey {
		guard archive.isPasswordEncrypted,
			  let enc = archive.manifest.encryption,
			  let salt = Data(base64Encoded: enc.saltBase64),
			  let macB64 = archive.integrity.passwordHMACBase64,
			  let expectedMAC = Data(base64Encoded: macB64) else {
			throw BackupError.invalidFormat("Archive is not password-encrypted.")
		}
		guard !password.isEmpty else {
			throw BackupError.passwordRequired
		}
		
		let masterKey = try BackupCrypto.derivePBKDF2Key(
			password: password,
			salt: salt,
			iterations: enc.iterations
		)
		let (encKey, authKey) = BackupCrypto.deriveEncryptionAndAuthKeys(masterKey: masterKey, salt: salt)
		let authInput = signedInput(flags: archive.flags, manifestBytes: archive.manifestBytes)
		guard BackupCrypto.verifyPasswordHMAC(expectedMAC, for: authInput, using: authKey) else {
			throw BackupError.wrongPassword
		}
		return encKey
	}
	
	static func extractModuleJSON(
		descriptor: BackupModuleDescriptor,
		from archive: VerifiedBackupArchive,
		encryptionKey: SymmetricKey?
	) throws -> Data {
		guard descriptor.compression == "lzfse" else {
			throw BackupError.unsupportedVersion(archive.manifest.formatVersion)
		}
		guard let wireChunk = archive.wireChunksByID[descriptor.id] else {
			throw BackupError.integrityViolation("Missing payload for '\(descriptor.id)'")
		}
		
		let compressed: Data
		if archive.isPasswordEncrypted {
			guard let encryptionKey else {
				throw BackupError.passwordRequired
			}
			let aad = moduleAAD(
				exportID: archive.manifest.exportID,
				moduleID: descriptor.id,
				plaintextSHA256: descriptor.plaintextSHA256.lowercased()
			)
			compressed = try BackupCrypto.decryptModule(wireChunk, using: encryptionKey, aad: aad)
		} else {
			compressed = wireChunk
		}
		
		let rawJSON = try BackupCrypto.decompressLZFSE(compressed, expectedSize: descriptor.uncompressedBytes)
		let actualPlainSHA = BackupCrypto.sha256Hex(rawJSON)
		guard actualPlainSHA == descriptor.plaintextSHA256.lowercased() else {
			throw BackupError.integrityViolation("Plaintext SHA-256 mismatch for module '\(descriptor.id)'")
		}
		return rawJSON
	}
	
	// MARK: - Binary Helpers
	
	private static func appendUInt16(_ value: UInt16, to data: inout Data) {
		var be = value.bigEndian
		Swift.withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
	}
	
	private static func appendUInt32(_ value: UInt32, to data: inout Data) {
		var be = value.bigEndian
		Swift.withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
	}
	
	private static func appendLengthPrefixed(_ payload: Data, to data: inout Data) {
		appendUInt32(UInt32(payload.count), to: &data)
		data.append(payload)
	}
	
	private struct BinaryCursor {
		let data: Data
		var offset: Int = 0
		
		mutating func readBytes(_ count: Int) throws -> Data {
			guard count >= 0, count <= data.count - offset else {
				throw BackupError.invalidFormat("Unexpected end of backup file.")
			}
			let slice = data[offset..<(offset + count)]
			offset += count
			return Data(slice)
		}
		
		mutating func readUInt16() throws -> UInt16 {
			let bytes = try readBytes(2)
			return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
		}
		
		mutating func readUInt32() throws -> UInt32 {
			let bytes = try readBytes(4)
			return (UInt32(bytes[0]) << 24)
				| (UInt32(bytes[1]) << 16)
				| (UInt32(bytes[2]) << 8)
				| UInt32(bytes[3])
		}
		
		mutating func readLengthPrefixed(maxBytes: Int) throws -> Data {
			let length = Int(try readUInt32())
			guard length >= 0, length <= maxBytes else {
				throw BackupError.invalidFormat("Section length (\(length)) exceeds allowed limit.")
			}
			return try readBytes(length)
		}
		
		func assertEOF() throws {
			guard offset == data.count else {
				throw BackupError.integrityViolation("Unexpected trailing data at end of backup file")
			}
		}
	}
}
