import Foundation
import CryptoKit
import Security

enum BackupCrypto {
	static let defaultPBKDF2Iterations = 100_000
	static let minPBKDF2Iterations = 10_000
	static let maxPBKDF2Iterations = 1_000_000
	static let maxDecompressedModuleBytes = 128 * 1024 * 1024
	
	static func sha256Hex(_ data: Data) -> String {
		Data(SHA256.hash(data: data)).hexEncoded()
	}
	
	static func randomBytes(count: Int) throws -> Data {
		var bytes = Data(count: count)
		let status = bytes.withUnsafeMutableBytes { ptr in
			guard let base = ptr.baseAddress else { return errSecParam }
			return SecRandomCopyBytes(kSecRandomDefault, count, base)
		}
		guard status == errSecSuccess else {
			throw BackupError.cryptoFailure("SecRandomCopyBytes failed with status \(status)")
		}
		return bytes
	}
	
	// MARK: - Application Integrity HMAC
	
	private static let appIntegrityKey: SymmetricKey = {
		let p1: [UInt8] = [0x52, 0x42, 0x42, 0x4B, 0x2D, 0x37, 0x66, 0x39, 0x31, 0x2D, 0x56, 0x41, 0x4C, 0x4F, 0x2D, 0x4B]
		let p2: [UInt8] = [0x39, 0xA4, 0x1C, 0x8E, 0x42, 0xD7, 0x09, 0x5B, 0xF3, 0x61, 0x8A, 0x20, 0xCE, 0x45, 0x99, 0x12]
		let ikm = SymmetricKey(data: Data(p1 + p2))
		return HKDF<SHA256>.deriveKey(
			inputKeyMaterial: ikm,
			salt: Data("ReconBoltRevived.Backup.Salt.v1".utf8),
			info: Data("com.dtl21.recon-bolt.backup.integrity.v1".utf8),
			outputByteCount: 32
		)
	}()
	
	static func computeAppHMAC(for data: Data) -> Data {
		Data(HMAC<SHA256>.authenticationCode(for: data, using: appIntegrityKey))
	}
	
	static func verifyAppHMAC(_ mac: Data, for data: Data) -> Bool {
		guard mac.count == 32 else { return false }
		return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: data, using: appIntegrityKey)
	}
	
	// MARK: - Password Key Derivation & Authenticated Encryption
	
	static func derivePBKDF2Key(
		password: String,
		salt: Data,
		iterations: Int = defaultPBKDF2Iterations,
		keyByteCount: Int = 32
	) throws -> SymmetricKey {
		guard let passwordData = password.data(using: .utf8), !passwordData.isEmpty else {
			throw BackupError.passwordRequired
		}
		guard salt.count >= 16,
			  (minPBKDF2Iterations...maxPBKDF2Iterations).contains(iterations),
			  keyByteCount > 0 else {
			throw BackupError.invalidFormat("Invalid key derivation parameters.")
		}
		
		let prfKey = SymmetricKey(data: passwordData)
		let hashLen = 32
		let blockCount = (keyByteCount + hashLen - 1) / hashLen
		var derived = Data()
		derived.reserveCapacity(blockCount * hashLen)
		
		var u = [UInt8](repeating: 0, count: hashLen)
		var t = [UInt8](repeating: 0, count: hashLen)
		
		for blockIndex in 1...blockCount {
			var beIndex = UInt32(blockIndex).bigEndian
			var firstHMAC = HMAC<SHA256>(key: prfKey)
			firstHMAC.update(data: salt)
			Swift.withUnsafeBytes(of: &beIndex) { firstHMAC.update(data: $0) }
			let d1 = firstHMAC.finalize()
			d1.withUnsafeBytes { src in
				for i in 0..<hashLen {
					let byte = src[i]
					u[i] = byte
					t[i] = byte
				}
			}
			if iterations > 1 {
				for _ in 2...iterations {
					let nextDigest = HMAC<SHA256>.authenticationCode(for: u, using: prfKey)
					nextDigest.withUnsafeBytes { src in
						for i in 0..<hashLen {
							let byte = src[i]
							u[i] = byte
							t[i] ^= byte
						}
					}
				}
			}
			derived.append(contentsOf: t)
		}
		
		return SymmetricKey(data: derived.prefix(keyByteCount))
	}
	
	static func deriveEncryptionAndAuthKeys(
		masterKey: SymmetricKey,
		salt: Data
	) -> (encKey: SymmetricKey, authKey: SymmetricKey) {
		let encKey = HKDF<SHA256>.deriveKey(
			inputKeyMaterial: masterKey,
			salt: salt,
			info: Data("rbbk-module-aesgcm-v1".utf8),
			outputByteCount: 32
		)
		let authKey = HKDF<SHA256>.deriveKey(
			inputKeyMaterial: masterKey,
			salt: salt,
			info: Data("rbbk-manifest-mac-v1".utf8),
			outputByteCount: 32
		)
		return (encKey, authKey)
	}
	
	static func computePasswordHMAC(for data: Data, using authKey: SymmetricKey) -> Data {
		Data(HMAC<SHA256>.authenticationCode(for: data, using: authKey))
	}
	
	static func verifyPasswordHMAC(_ mac: Data, for data: Data, using authKey: SymmetricKey) -> Bool {
		guard mac.count == 32 else { return false }
		return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: data, using: authKey)
	}
	
	static func encryptModule(_ plaintext: Data, using key: SymmetricKey, aad: Data) throws -> Data {
		let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
		guard let combined = sealed.combined else {
			throw BackupError.cryptoFailure("Failed to serialize AES-GCM sealed box.")
		}
		return combined
	}
	
	static func decryptModule(_ ciphertext: Data, using key: SymmetricKey, aad: Data) throws -> Data {
		do {
			let box = try AES.GCM.SealedBox(combined: ciphertext)
			return try AES.GCM.open(box, using: key, authenticating: aad)
		} catch {
			throw BackupError.decryptionFailed
		}
	}
	
	// MARK: - Compression (LZFSE)
	
	static func compressLZFSE(_ data: Data) throws -> Data {
		do {
			return try (data as NSData).compressed(using: .lzfse) as Data
		} catch {
			throw BackupError.cryptoFailure("Compression failed: \(error.localizedDescription)")
		}
	}
	
	static func decompressLZFSE(
		_ data: Data,
		expectedSize: Int,
		maxAllowedBytes: Int = maxDecompressedModuleBytes
	) throws -> Data {
		guard expectedSize >= 0, expectedSize <= maxAllowedBytes else {
			throw BackupError.decompressionFailed("Declared uncompressed size (\(expectedSize) bytes) is invalid or exceeds safety limits.")
		}
		let decompressed: Data
		do {
			decompressed = try (data as NSData).decompressed(using: .lzfse) as Data
		} catch {
			throw BackupError.decompressionFailed(error.localizedDescription)
		}
		guard decompressed.count == expectedSize else {
			throw BackupError.integrityViolation("Decompressed payload size mismatch (expected \(expectedSize), got \(decompressed.count))")
		}
		return decompressed
	}
}

enum DeviceSigningKeyStore {
	private static let keychainKey = "com.dtl21.recon-bolt.backup.deviceSigningKey.p256.v1"
	
	static func loadOrCreateSigningKey(keychain: any Keychain = OSKeychain.standard) throws -> P256.Signing.PrivateKey {
		if let stored = try? keychain.loadData(forKey: keychainKey),
		   let key = try? P256.Signing.PrivateKey(rawRepresentation: stored) {
			return key
		}
		let freshKey = P256.Signing.PrivateKey()
		try keychain.store(freshKey.rawRepresentation, forKey: keychainKey)
		return freshKey
	}
	
	static func currentPublicKeyX963(keychain: any Keychain = OSKeychain.standard) -> Data? {
		guard let stored = try? keychain.loadData(forKey: keychainKey),
			  let key = try? P256.Signing.PrivateKey(rawRepresentation: stored) else {
			return nil
		}
		return key.publicKey.x963Representation
	}
	
	static func fingerprint(for publicKeyX963: Data) -> String {
		let bytes = Array(SHA256.hash(data: publicKeyX963).prefix(8))
		return stride(from: 0, to: bytes.count, by: 2).map { idx in
			String(format: "%02X%02X", bytes[idx], bytes[idx + 1])
		}.joined(separator: "-")
	}
	
	static func sign(
		_ data: Data,
		keychain: any Keychain = OSKeychain.standard
	) throws -> (signatureDER: Data, publicKeyX963: Data, fingerprint: String) {
		let privateKey = try loadOrCreateSigningKey(keychain: keychain)
		let signature = try privateKey.signature(for: data).derRepresentation
		let publicKeyData = privateKey.publicKey.x963Representation
		return (signature, publicKeyData, fingerprint(for: publicKeyData))
	}
	
	static func verify(signatureDER: Data, for data: Data, publicKeyX963: Data) -> Bool {
		guard
			let publicKey = try? P256.Signing.PublicKey(x963Representation: publicKeyX963),
			let signature = try? P256.Signing.ECDSASignature(derRepresentation: signatureDER)
		else {
			return false
		}
		return publicKey.isValidSignature(signature, for: data)
	}
}
