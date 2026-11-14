// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only
//
// The helper behind Scripts/release-key.sh. Run that script instead of this file.

import CryptoKit
import Foundation
import Security

let keyFile = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".notchpal/release-key")
let publicKeyFile = URL(fileURLWithPath: "Support/release-public-key.txt")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadKey() -> SecureEnclave.P256.Signing.PrivateKey {
    guard let blob = try? Data(contentsOf: keyFile) else {
        fail("No release key on this Mac yet. Make one with: bash Scripts/release-key.sh create")
    }
    do {
        return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob)
    } catch {
        fail("The release key couldn't be opened on this Mac's security chip: \(error)")
    }
}

func publicKeyText(_ key: SecureEnclave.P256.Signing.PrivateKey) -> String {
    key.publicKey.rawRepresentation.base64EncodedString()
}

func savedPublicKeys() -> [String] {
    guard let text = try? String(contentsOf: publicKeyFile, encoding: .utf8) else { return [] }
    return text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first ?? "" {
case "create":
    guard SecureEnclave.isAvailable else { fail("This Mac has no security chip (Secure Enclave), so it can't hold a release key.") }
    if FileManager.default.fileExists(atPath: keyFile.path) {
        fail("""
        This Mac already has a release key, so nothing was changed.
        A new key would make every copy of NotchPal refuse your next update.
        Public key: \(publicKeyText(loadKey()))
        """)
    }
    var error: Unmanaged<CFError>?
    // Usable only on this Mac while it's unlocked, and every signature needs Touch ID (or your password).
    guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                       [.privateKeyUsage, .userPresence], &error) else {
        fail("macOS refused to set up the key's protection: \(String(describing: error?.takeRetainedValue()))")
    }
    let key: SecureEnclave.P256.Signing.PrivateKey
    do {
        key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
    } catch {
        fail("The security chip couldn't make a key: \(error)")
    }
    do {
        try FileManager.default.createDirectory(at: keyFile.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // This file is only a sealed reference to the key inside the chip. It's useless on any other Mac.
        try key.dataRepresentation.write(to: keyFile, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
        try (publicKeyText(key) + "\n").write(to: publicKeyFile, atomically: true, encoding: .utf8)
    } catch {
        fail("The key was made but couldn't be saved: \(error)")
    }
    print("Release key made inside this Mac's security chip.")
    print("Public key (safe to share): \(publicKeyText(key))")
    print("Saved to \(publicKeyFile.path)")

case "public-key":
    print(publicKeyText(loadKey()))

case "sign":
    guard arguments.count == 3 else { fail("Usage: release-signer sign <zip> <version>") }
    let zip = URL(fileURLWithPath: arguments[1])
    let version = arguments[2]
    guard let data = try? Data(contentsOf: zip) else { fail("Couldn't read \(zip.path)") }
    let hash = ReleaseSignature.sha256Hex(of: data)
    let key = loadKey()
    print("Touch the Touch ID sensor to sign NotchPal \(version)…")
    let signature: P256.Signing.ECDSASignature
    do {
        signature = try key.signature(for: ReleaseSignature.message(version: version, sha256Hex: hash))
    } catch {
        fail("Not signed (Touch ID was cancelled or failed): \(error)")
    }
    let text = signature.rawRepresentation.base64EncodedString()
    guard ReleaseSignature.isValid(text, version: version, sha256Hex: hash, keys: [publicKeyText(key)]) else {
        fail("The new signature didn't check out, so it wasn't saved.")
    }
    let sigFile = zip.appendingPathExtension("sig")
    do {
        try (text + "\n").write(to: sigFile, atomically: true, encoding: .utf8)
    } catch {
        fail("Couldn't save \(sigFile.path): \(error)")
    }
    print("Signed: \(sigFile.path)")

case "verify":
    guard arguments.count == 4 else { fail("Usage: release-signer verify <zip> <version> <sig file>") }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
          let text = try? String(contentsOf: URL(fileURLWithPath: arguments[3]), encoding: .utf8)
    else { fail("Couldn't read the zip or the signature.") }
    let keys = ReleaseSignature.makerKeys.isEmpty ? savedPublicKeys() : ReleaseSignature.makerKeys
    if ReleaseSignature.isValid(text, version: arguments[2], sha256Hex: ReleaseSignature.sha256Hex(of: data), keys: keys) {
        print("VALID: NotchPal would install this update.")
    } else {
        print("REFUSED: NotchPal would not install this update.")
        exit(2)
    }

default:
    fail("""
    Usage: bash Scripts/release-key.sh create            make the key (once)
           bash Scripts/release-key.sh public-key        show the public key
           bash Scripts/release-key.sh sign              sign the release zip in dist/
           bash Scripts/release-key.sh verify <zip> <version> <sig>
    """)
}
