// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import CryptoKit
import Foundation

/// Proof that an update really comes from NotchPal's maker.
///
/// Every release is signed by a key that lives inside the security chip (Secure Enclave) of the
/// maker's Mac. That key can't be copied off the chip, and signing needs the maker's Touch ID.
/// NotchPal only installs an update whose signature matches, so even someone who broke into the
/// GitHub account couldn't push a fake update. Scripts/release-key.sh makes and uses the key.
///
/// This file is also built into that script's helper, so both check signatures the same way.
enum ReleaseSignature {
    /// The public half of the maker's release key. It's safe to publish: it can only check
    /// signatures, never make them.
    static let makerKeys: [String] = [
        // Mohammed Saif's MacBook Air, made 14 November 2026.
        "D7pvawIFTxcfQTsOVy7/pt3p1fTv/2e9u43kVRwRTBl96f1zqvXsYc4YCz538bq3+Gkfx5aVc1g6UkY0TR4JmQ==",
    ]

    /// What gets signed: the version and the exact download, so a signature can't be reused for
    /// another file or another version.
    static func message(version: String, sha256Hex: String) -> Data {
        Data("NotchPal update\n\(version)\n\(sha256Hex.lowercased())".utf8)
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// True when `signatureText` (the contents of a .sig file) is a valid signature, by one of
    /// `keys`, of this version of this download.
    static func isValid(_ signatureText: String, version: String, sha256Hex: String,
                        keys: [String] = makerKeys) -> Bool {
        guard let raw = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: raw)
        else { return false }
        let signed = message(version: version, sha256Hex: sha256Hex)
        return keys.contains { text in
            guard let data = Data(base64Encoded: text),
                  let key = try? P256.Signing.PublicKey(rawRepresentation: data)
            else { return false }
            return key.isValidSignature(signature, for: signed)
        }
    }
}
