import CompanionCore
import CryptoKit
import Darwin
import Foundation
import ImageIO

enum StrictJSON {
    static func object(_ data: Data, maximumBytes: Int = CharacterPackageLimits.maximumManifestBytes) throws -> [String: Any] {
        guard data.count <= maximumBytes else { throw CharacterPackageImportFailure(.invalidManifest, .validate) }
        var scanner = DuplicateKeyScanner(data)
        try scanner.scanDocument()
        // `try?` rather than `try`: the scanner accepts a well-formed top-level
        // scalar, which JSONSerialization refuses as a fragment. Letting that
        // NSError propagate would put a Foundation error where every caller
        // expects a stable import code.
        guard let parsed = try? JSONSerialization.jsonObject(with: data, options: []),
              let object = parsed as? [String: Any] else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
        return object
    }

    private struct DuplicateKeyScanner {
        let bytes: [UInt8]
        var index = 0

        init(_ data: Data) { bytes = Array(data) }

        mutating func scanDocument() throws {
            skipWhitespace()
            try scanValue(depth: 0)
            skipWhitespace()
            guard index == bytes.count else { throw invalid() }
        }

        mutating func scanValue(depth: Int) throws {
            guard depth <= 64, index < bytes.count else { throw invalid() }
            switch bytes[index] {
            case 0x7b: try scanObject(depth: depth + 1)
            case 0x5b: try scanArray(depth: depth + 1)
            case 0x22: _ = try scanString()
            case 0x74: try literal("true")
            case 0x66: try literal("false")
            case 0x6e: try literal("null")
            case 0x2d, 0x30...0x39: try scanNumber()
            default: throw invalid()
            }
        }

        mutating func scanObject(depth: Int) throws {
            index += 1
            skipWhitespace()
            var keys = Set<String>()
            if consume(0x7d) { return }
            while true {
                guard index < bytes.count, bytes[index] == 0x22 else { throw invalid() }
                let key = try scanString()
                guard keys.insert(key).inserted else { throw invalid() }
                skipWhitespace()
                guard consume(0x3a) else { throw invalid() }
                skipWhitespace()
                try scanValue(depth: depth)
                skipWhitespace()
                if consume(0x7d) { return }
                guard consume(0x2c) else { throw invalid() }
                skipWhitespace()
            }
        }

        mutating func scanArray(depth: Int) throws {
            index += 1
            skipWhitespace()
            if consume(0x5d) { return }
            while true {
                try scanValue(depth: depth)
                skipWhitespace()
                if consume(0x5d) { return }
                guard consume(0x2c) else { throw invalid() }
                skipWhitespace()
            }
        }

        mutating func scanString() throws -> String {
            let start = index
            index += 1
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x22 {
                    index += 1
                    let data = Data(bytes[start..<index])
                    guard let decoded = try? JSONDecoder().decode(String.self, from: data) else { throw invalid() }
                    return decoded
                }
                if byte == 0x5c {
                    index += 1
                    guard index < bytes.count else { throw invalid() }
                    if bytes[index] == 0x75 {
                        guard index + 4 < bytes.count,
                              bytes[(index + 1)...(index + 4)].allSatisfy({ hex($0) }) else { throw invalid() }
                        index += 4
                    } else if ![0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74].contains(bytes[index]) {
                        throw invalid()
                    }
                } else if byte < 0x20 {
                    throw invalid()
                }
                index += 1
            }
            throw invalid()
        }

        mutating func scanNumber() throws {
            let start = index
            if consume(0x2d), index == bytes.count { throw invalid() }
            if consume(0x30) {
                if index < bytes.count, (0x30...0x39).contains(bytes[index]) { throw invalid() }
            } else {
                guard consumeDigits(minimum: 1) else { throw invalid() }
            }
            if consume(0x2e), !consumeDigits(minimum: 1) { throw invalid() }
            if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
                index += 1
                if index < bytes.count, bytes[index] == 0x2b || bytes[index] == 0x2d { index += 1 }
                guard consumeDigits(minimum: 1) else { throw invalid() }
            }
            guard index > start else { throw invalid() }
        }

        mutating func literal(_ value: String) throws {
            let literal = Array(value.utf8)
            guard index + literal.count <= bytes.count,
                  Array(bytes[index..<(index + literal.count)]) == literal else { throw invalid() }
            index += literal.count
        }

        mutating func consumeDigits(minimum: Int) -> Bool {
            let start = index
            while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
            return index - start >= minimum
        }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0a, 0x0d].contains(bytes[index]) { index += 1 }
        }

        mutating func consume(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        func hex(_ byte: UInt8) -> Bool {
            (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
        }

        func invalid() -> CharacterPackageImportFailure { .init(.invalidManifest, .validate) }
    }
}

enum CharacterManifestValidator {
    struct Decoded {
        let manifest: CharacterPackageManifestV1
        let legacyReceipt: LegacyManifestReceiptV1?
        let warnings: [String]
    }

    private static let canonicalRequired: Set<String> = [
        "schema", "packageID", "characterID", "version", "displayName", "renderer", "entryPath", "locales", "assets", "provenance",
    ]
    private static let canonicalAllowed = canonicalRequired.union(["portraitPath", "motions"])
    private static let canonicalFamily: Set<String> = ["packageID", "characterID", "renderer", "entryPath", "assets", "provenance"]
    private static let legacyFamily: Set<String> = ["id", "identity", "appearance"]
    private static let legacyAllowed: Set<String> = [
        "schema", "id", "version", "locale", "locales", "identity", "appearance", "persona", "voice", "lorebook", "license",
        "knowledge", "capabilities", "creator", "source", "provenance", "security", "localizations", "extensions",
    ]
    private static let forbiddenFragments = [
        "memory", "messages", "affinity", "permission", "secret", "sync", "runtime", "token", "apikey", "api_key", "credential",
        "grant", "capability", "modelweight", "model_weight", "privatekey", "private_key",
    ]
    /// A generic anti-blowup bound on an array anywhere in a package document. It
    /// exists so a hostile document cannot make the forbidden-content walk
    /// expensive; it says nothing about how many files a character may have.
    private static let maximumArrayElements = 300
    private static let maximumStringBytes = 12_000
    private static let maximumWalkDepth = 32

    static func decodeAndAdapt(at root: URL) throws -> Decoded {
        let url = root.appendingPathComponent("manifest.json")
        let data = try CharacterPackageMaterializer.readBounded(url, maximum: CharacterPackageLimits.maximumManifestBytes, phase: .validate)
        let object = try StrictJSON.object(data)
        guard object["schema"] as? String == "joi.character.v1" else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
        let keys = Set(object.keys)
        let canonical = canonicalFamily.isSubset(of: keys)
        let legacy = legacyFamily.isSubset(of: keys)
        guard canonical != legacy else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
        if canonical {
            try requireExact(keys, required: canonicalRequired, allowed: canonicalAllowed)
            try rejectForbidden(object, path: [], failureCode: .invalidManifest, canonicalManifest: true)
            try validateCanonicalShape(object)
            do {
                return Decoded(manifest: try CharacterCoding.decoder.decode(CharacterPackageManifestV1.self, from: data), legacyReceipt: nil, warnings: [])
            } catch {
                throw CharacterPackageImportFailure(.invalidManifest, .validate)
            }
        }
        return try adaptLegacy(object, root: root)
    }

    static func validateActiveJSON(_ data: Data) throws {
        let object = try StrictJSON.object(data, maximumBytes: 4 * 1024 * 1024)
        try rejectForbidden(object, path: [], failureCode: .invalidManifest)
    }

    static func validateCanonical(
        at root: URL,
        expected: CharacterPackageManifestV1? = nil
    ) throws -> CharacterPackageManifestV1 {
        let decoded = try decodeCanonicalOnly(at: root)
        if let expected, decoded != expected {
            throw CharacterPackageImportFailure(.hashMismatch, .validate)
        }
        let manifest = decoded
        guard validIdentifier(manifest.packageID, maximum: 160),
              validIdentifier(manifest.characterID, maximum: 160),
              !manifest.version.isEmpty, manifest.version.count <= 80,
              !manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.displayName.count <= 160,
              !manifest.provenance.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.provenance.author.count <= 500,
              !manifest.provenance.license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.provenance.license.count <= 1_000,
              manifest.provenance.source.map(validRemoteProvenanceSource) ?? true,
              !manifest.locales.isEmpty,
              Set(manifest.locales).count == manifest.locales.count,
              manifest.locales.allSatisfy({ ["zh-Hans", "zh-Hant", "en", "ja", "ko"].contains($0) }),
              manifest.assets.count <= CharacterPackageLimits.maximumFileCount else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
        var assetPaths = Set<String>()
        for asset in manifest.assets {
            let normalized = try RestrictedZIPPolicy.normalizedPath(asset.path)
            guard normalized == asset.path,
                  assetPaths.insert(asset.path).inserted,
                  CharacterDigests.isLowercaseSHA(asset.sha256) else {
                throw CharacterPackageImportFailure(.invalidManifest, .validate)
            }
            let assetURL = root.appendingPathComponent(asset.path)
            let fileDigest = try CharacterDigests.sha256File(
                assetURL,
                maximum: CharacterPackageLimits.maximumFileBytes,
                phase: .validate
            )
            guard fileDigest.digest == asset.sha256 else {
                throw CharacterPackageImportFailure(.hashMismatch, .validate)
            }
            try CharacterMediaValidator.validate(url: assetURL, path: asset.path, declaredMediaType: asset.mediaType)
        }
        let files = try CharacterTreeVerifier.regularFiles(at: root)
        guard Set(files) == assetPaths.union(["manifest.json"]),
              assetPaths.contains(manifest.entryPath),
              manifest.portraitPath.map(assetPaths.contains) ?? true else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
        // A motion table is a VRM-only renderer graph. Live2D declares its motions
        // inside its own `.model3.json` closure, and a second mechanism would put
        // two sources of truth on the same model.
        if manifest.renderer != .vrm, !manifest.declaredMotions.isEmpty {
            throw CharacterPackageImportFailure(.invalidRenderer, .validate)
        }
        switch manifest.renderer {
        case .static:
            guard let portrait = manifest.portraitPath, portrait == manifest.entryPath else {
                throw CharacterPackageImportFailure(.invalidRenderer, .validate)
            }
            guard assetPaths == [manifest.entryPath] else {
                throw CharacterPackageImportFailure(.invalidRenderer, .validate)
            }
        case .vrm:
            guard manifest.entryPath.lowercased().hasSuffix(".vrm") else {
                throw CharacterPackageImportFailure(.invalidRenderer, .validate)
            }
            // The extension is a claim; the glTF extensions are the fact. This
            // stops a `.vrma` renamed to `.vrm` from being loaded as the model,
            // and vice versa below.
            let entryFormat = try CharacterMediaValidator.vrmFormat(
                at: root.appendingPathComponent(manifest.entryPath)
            )
            guard entryFormat == .vrm0 || entryFormat == .vrm1 else {
                throw CharacterPackageImportFailure(.invalidRenderer, .validate)
            }
            var expectedPaths: Set<String> = [manifest.entryPath]
            if let portrait = manifest.portraitPath { expectedPaths.insert(portrait) }
            let motions = manifest.declaredMotions
            guard motions.count <= CharacterPackageLimits.maximumMotionCount else {
                throw CharacterPackageImportFailure(.invalidRenderer, .validate)
            }
            var motionNames = Set<String>()
            for motion in motions {
                guard validMotionName(motion.motion),
                      motionNames.insert(motion.motion).inserted,
                      motion.animation.lowercased().hasSuffix(".vrma"),
                      motion.animation != manifest.entryPath,
                      assetPaths.contains(motion.animation) else {
                    throw CharacterPackageImportFailure(.invalidRenderer, .validate)
                }
                let format = try CharacterMediaValidator.vrmFormat(
                    at: root.appendingPathComponent(motion.animation)
                )
                guard format == .vrma else {
                    throw CharacterPackageImportFailure(.invalidRenderer, .validate)
                }
                expectedPaths.insert(motion.animation)
            }
            // Still exact: an undeclared animation sitting in the tree is refused
            // just as any other unexpected file is.
            guard assetPaths == expectedPaths else {
                throw CharacterPackageImportFailure(.invalidRenderer, .validate)
            }
        case .live2d:
            guard manifest.entryPath.lowercased().hasSuffix(".model3.json") else {
                throw CharacterPackageImportFailure(.invalidRenderer, .validate)
            }
            let model = try CharacterPackageMaterializer.readBounded(root.appendingPathComponent(manifest.entryPath), maximum: 4 * 1024 * 1024, phase: .validate)
            let base = (manifest.entryPath as NSString).deletingLastPathComponent
            let references = try Live2DClosure.references(model).map { base.isEmpty ? $0 : base + "/" + $0 }
            var expectedPaths = Set(references)
            expectedPaths.insert(manifest.entryPath)
            if let portrait = manifest.portraitPath { expectedPaths.insert(portrait) }
            guard expectedPaths == assetPaths else {
                throw CharacterPackageImportFailure(.invalidRenderer, .validate)
            }
        }
        return manifest
    }

    private static func decodeCanonicalOnly(at root: URL) throws -> CharacterPackageManifestV1 {
        let data = try CharacterPackageMaterializer.readBounded(root.appendingPathComponent("manifest.json"), maximum: CharacterPackageLimits.maximumManifestBytes, phase: .validate)
        let object = try StrictJSON.object(data)
        let keys = Set(object.keys)
        try requireExact(keys, required: canonicalRequired, allowed: canonicalAllowed)
        guard canonicalFamily.isSubset(of: keys), legacyFamily.intersection(keys).isEmpty else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
        try rejectForbidden(object, path: [], failureCode: .invalidManifest, canonicalManifest: true)
        try validateCanonicalShape(object)
        do { return try CharacterCoding.decoder.decode(CharacterPackageManifestV1.self, from: data) }
        catch { throw CharacterPackageImportFailure(.invalidManifest, .validate) }
    }

    private static func validateCanonicalShape(_ object: [String: Any]) throws {
        guard let assets = object["assets"] as? [[String: Any]],
              let provenance = object["provenance"] as? [String: Any] else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
        for asset in assets {
            try requireExact(Set(asset.keys), required: ["path", "mediaType", "sha256"], allowed: ["path", "mediaType", "sha256"])
        }
        if let motions = object["motions"] {
            guard let motions = motions as? [[String: Any]] else {
                throw CharacterPackageImportFailure(.invalidManifest, .validate)
            }
            for motion in motions {
                try requireExact(
                    Set(motion.keys),
                    required: ["motion", "animation"],
                    allowed: ["motion", "animation", "loop"]
                )
            }
        }
        try requireExact(Set(provenance.keys), required: ["author", "license"], allowed: ["author", "license", "source"])
    }

    private static func adaptLegacy(_ object: [String: Any], root: URL) throws -> Decoded {
        let keys = Set(object.keys)
        let canonicalExclusive: Set<String> = ["packageID", "characterID", "renderer", "entryPath", "assets"]
        guard legacyFamily.isSubset(of: keys), canonicalExclusive.intersection(keys).isEmpty,
              keys.isSubset(of: legacyAllowed) else {
            throw CharacterPackageImportFailure(.unsupportedLegacy, .validate)
        }
        try validateLegacyShape(object)
        try rejectForbiddenLegacy(object)
        guard let id = boundedString(object["id"], maximum: 160),
              let identity = object["identity"] as? [String: Any],
              let name = boundedString(identity["name"], maximum: 160),
              let appearance = object["appearance"] as? [String: Any],
              let type = boundedString(appearance["model_type"], maximum: 32),
              let renderer = CharacterRendererKind(rawValue: type.lowercased()) else {
            throw CharacterPackageImportFailure(.unsupportedLegacy, .validate)
        }
        let localeSource: String
        if let locale = object["locale"] as? String { localeSource = locale }
        else if let locales = object["locales"] as? [String], locales.count == 1, let locale = locales.first { localeSource = locale }
        else { throw CharacterPackageImportFailure(.unsupportedLegacy, .validate) }
        let mapped = localeSource == "zh" ? "zh-Hans" : localeSource
        guard ["zh-Hans", "zh-Hant", "en", "ja", "ko"].contains(mapped) else {
            throw CharacterPackageImportFailure(.unsupportedLegacy, .validate)
        }
        let model = appearance["model"] as? String
        let portrait = appearance["portrait"] as? String
        let entry: String
        switch renderer {
        case .static:
            guard let portrait else { throw CharacterPackageImportFailure(.unsupportedLegacy, .validate) }
            entry = portrait
        case .live2d, .vrm:
            guard let model else { throw CharacterPackageImportFailure(.unsupportedLegacy, .validate) }
            entry = model
        }
        let normalizedEntry = try RestrictedZIPPolicy.normalizedPath(entry)
        let normalizedPortrait = try portrait.map(RestrictedZIPPolicy.normalizedPath)

        var closure = Set([normalizedEntry])
        if let normalizedPortrait { closure.insert(normalizedPortrait) }
        if renderer == .live2d {
            let modelData = try CharacterPackageMaterializer.readBounded(root.appendingPathComponent(normalizedEntry), maximum: 4 * 1024 * 1024, phase: .validate)
            let base = (normalizedEntry as NSString).deletingLastPathComponent
            for reference in try Live2DClosure.references(modelData) {
                closure.insert(base.isEmpty ? reference : base + "/" + reference)
            }
        }
        let allFiles = try CharacterTreeVerifier.regularFiles(at: root)
        guard Set(allFiles) == closure.union(["manifest.json"]) else {
            throw CharacterPackageImportFailure(.unsupportedLegacy, .validate)
        }
        var assets: [CharacterAssetV1] = []
        for path in closure.sorted() {
            let media = CharacterMediaValidator.mediaType(for: path)
            try CharacterMediaValidator.validate(url: root.appendingPathComponent(path), path: path, declaredMediaType: media)
            let digest = try CharacterDigests.sha256File(root.appendingPathComponent(path), maximum: CharacterPackageLimits.maximumFileBytes, phase: .validate).digest
            assets.append(.init(path: path, mediaType: media, sha256: digest))
        }
        let allowlisted = try canonicalLegacyBytes(object)
        let legacySourceID = CharacterDigests.sha256(Data("joi.legacy-source.v1\0".utf8) + allowlisted)
        let warning = localeSource == "zh" ? ["legacy_locale_zh_mapped_to_zh_Hans"] : []
        let receiptFields = try legacyReceiptFields(object)
        let manifest = CharacterPackageManifestV1(
            packageID: "legacy." + legacySourceID,
            characterID: id,
            version: boundedString(object["version"], maximum: 80) ?? "1.0.0",
            displayName: name,
            renderer: renderer,
            entryPath: normalizedEntry,
            portraitPath: normalizedPortrait,
            locales: [mapped],
            assets: assets,
            provenance: CharacterProvenanceV1(author: "Legacy import", license: "Unverified legacy package")
        )
        let manifestData = try CharacterCoding.encoder.encode(manifest)
        try manifestData.write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
        return Decoded(
            manifest: manifest,
            legacyReceipt: LegacyManifestReceiptV1(
                legacySourceID: legacySourceID,
                mappedLocale: mapped,
                warnings: warning,
                creatorName: receiptFields.creatorName,
                sourceType: receiptFields.sourceType,
                sourceURL: receiptFields.sourceURL,
                updateURL: receiptFields.updateURL,
                provenanceFormat: receiptFields.provenanceFormat,
                archiveSHA256: receiptFields.archiveSHA256,
                declaredLicense: receiptFields.declaredLicense
            ),
            warnings: warning
        )
    }

    private static func canonicalLegacyBytes(_ object: [String: Any]) throws -> Data {
        var retained: [String: Any] = [:]
        for key in ["schema", "id", "version", "locale", "locales", "persona", "lorebook", "license", "localizations"] {
            if let value = object[key] { retained[key] = value }
        }
        if let identity = object["identity"] as? [String: Any] {
            retained["identity"] = identity.filter { $0.key != "post_history_instructions" }
        }
        if let appearance = object["appearance"] { retained["appearance"] = appearance }
        if var voice = object["voice"] as? [String: Any] {
            voice.removeValue(forKey: "gpt_model")
            voice.removeValue(forKey: "sovits_model")
            retained["voice"] = voice
        }
        if var knowledge = object["knowledge"] as? [String: Any] {
            knowledge.removeValue(forKey: "memory_namespace")
            retained["knowledge"] = knowledge
        }
        if let creator = object["creator"] { retained["creator"] = creator }
        if let receipt = try? legacyReceiptFields(object) {
            retained["receipt"] = receipt.safeJSONObject
        }
        guard JSONSerialization.isValidJSONObject(retained) else {
            throw CharacterPackageImportFailure(.unsupportedLegacy, .validate)
        }
        let data = try JSONSerialization.data(withJSONObject: retained, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 64 * 1024 else { throw CharacterPackageImportFailure(.unsupportedLegacy, .validate) }
        return data
    }

    private struct LegacyReceiptFields {
        let creatorName: String?
        let sourceType: String?
        let sourceURL: String?
        let updateURL: String?
        let provenanceFormat: String?
        let archiveSHA256: String?
        let declaredLicense: String?

        var safeJSONObject: [String: String] {
            var result: [String: String] = [:]
            for (key, value) in [
                ("creatorName", creatorName), ("sourceType", sourceType), ("sourceURL", sourceURL), ("updateURL", updateURL),
                ("provenanceFormat", provenanceFormat), ("archiveSHA256", archiveSHA256), ("declaredLicense", declaredLicense),
            ] where value != nil {
                result[key] = value
            }
            return result
        }
    }

    private static func legacyReceiptFields(_ object: [String: Any]) throws -> LegacyReceiptFields {
        let creator = object["creator"] as? [String: Any]
        let source = object["source"] as? [String: Any]
        let provenance = object["provenance"] as? [String: Any]
        let security = object["security"] as? [String: Any]
        let sourceURL = try boundedRemoteURL(source?["url"])
        let updateURL = try boundedRemoteURL(source?["update_url"])
        let archiveSHA = boundedString(provenance?["archive_sha256"], maximum: 64)
        if let archiveSHA, !CharacterDigests.isLowercaseSHA(archiveSHA) {
            throw CharacterPackageImportFailure(.unsupportedLegacy, .validate)
        }
        let fields = LegacyReceiptFields(
            creatorName: boundedString(creator?["name"], maximum: 500),
            sourceType: boundedString(source?["type"], maximum: 80),
            sourceURL: sourceURL,
            updateURL: updateURL,
            provenanceFormat: boundedString(provenance?["format"], maximum: 80),
            archiveSHA256: archiveSHA,
            declaredLicense: boundedString(security?["license"] ?? object["license"], maximum: 1_000)
        )
        guard let receiptBytes = try? JSONSerialization.data(withJSONObject: fields.safeJSONObject, options: [.sortedKeys]),
              receiptBytes.count <= 16 * 1024 else {
            throw CharacterPackageImportFailure(.unsupportedLegacy, .validate)
        }
        return fields
    }

    private static func validateLegacyShape(_ object: [String: Any]) throws {
        try requireSubset(object["identity"], allowed: [
            "name", "avatar", "persona", "personality", "scenario", "tone", "boundaries", "system_prompt",
            "post_history_instructions", "greeting", "alternate_greetings", "example_dialogue", "description",
        ])
        try requireSubset(object["appearance"], allowed: [
            "model_type", "portrait", "model", "background", "accent_color", "sprite_color", "expressions", "motions", "lip_sync",
        ])
        try requireSubset(object["voice"], allowed: [
            "id", "label", "language", "prompt_language", "speed", "volume", "reference_audio", "prompt_text", "design",
            "gpt_model", "sovits_model", "emotion_map", "motion_lines",
        ])
        try requireSubset(object["knowledge"], allowed: ["lorebook", "memory_namespace"])
        try requireSubset(object["capabilities"], allowed: ["requested_skills", "approved_skills"])
        try requireSubset(object["creator"], allowed: ["name", "notes"])
        try requireSubset(object["source"], allowed: ["type", "url", "update_url"])
        try requireSubset(object["provenance"], allowed: ["format", "file_name", "archive_sha256", "imported_at"])
        try requireSubset(object["security"], allowed: ["license", "compatibility", "built_in", "file_hashes", "package_hash"])
    }

    private static func requireSubset(_ value: Any?, allowed: Set<String>) throws {
        guard let value else { return }
        guard let dictionary = value as? [String: Any], Set(dictionary.keys).isSubset(of: allowed) else {
            throw CharacterPackageImportFailure(.unsupportedLegacy, .validate)
        }
    }

    private static func rejectForbiddenLegacy(_ object: [String: Any]) throws {
        var sanitized = object
        sanitized.removeValue(forKey: "capabilities")
        if var identity = sanitized["identity"] as? [String: Any] {
            identity.removeValue(forKey: "post_history_instructions")
            sanitized["identity"] = identity
        }
        if var appearance = sanitized["appearance"] as? [String: Any] {
            appearance.removeValue(forKey: "lip_sync")
            sanitized["appearance"] = appearance
        }
        if var voice = sanitized["voice"] as? [String: Any] {
            voice.removeValue(forKey: "gpt_model")
            voice.removeValue(forKey: "sovits_model")
            sanitized["voice"] = voice
        }
        if var knowledge = sanitized["knowledge"] as? [String: Any] {
            knowledge.removeValue(forKey: "memory_namespace")
            sanitized["knowledge"] = knowledge
        }
        try rejectForbidden(sanitized, path: [])
    }

    private static func boundedRemoteURL(_ value: Any?) throws -> String? {
        guard let value else { return nil }
        guard let string = value as? String, validRemoteProvenanceSource(string) else {
            throw CharacterPackageImportFailure(.unsupportedLegacy, .validate)
        }
        return string
    }

    private static func validRemoteProvenanceSource(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 2_000,
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              components.host?.isEmpty == false,
              !value.contains("\\") else { return false }
        return true
    }

    private static func rejectForbidden(
        _ value: Any,
        path: [String],
        depth: Int = 0,
        failureCode: CharacterPackageImportCode = .unsupportedLegacy,
        canonicalManifest: Bool = false
    ) throws {
        guard depth <= maximumWalkDepth else { throw CharacterPackageImportFailure(failureCode, .validate) }
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let folded = key.lowercased().replacingOccurrences(of: "-", with: "_")
                if forbiddenFragments.contains(where: { folded.contains($0) }) {
                    throw CharacterPackageImportFailure(failureCode, .validate)
                }
                try rejectForbidden(
                    child,
                    path: path + [key],
                    depth: depth + 1,
                    failureCode: failureCode,
                    canonicalManifest: canonicalManifest
                )
            }
        } else if let array = value as? [Any] {
            let bound = arrayBound(path: path, depth: depth, canonicalManifest: canonicalManifest)
            guard array.count <= bound else { throw CharacterPackageImportFailure(failureCode, .validate) }
            for child in array {
                try rejectForbidden(
                    child,
                    path: path,
                    depth: depth + 1,
                    failureCode: failureCode,
                    canonicalManifest: canonicalManifest
                )
            }
        } else if let string = value as? String, string.utf8.count > maximumStringBytes {
            throw CharacterPackageImportFailure(failureCode, .validate)
        }
    }

    /// The declared asset list is the one array the contract gives a size of its
    /// own: the schema's `assets.maxItems`, `CharacterPackageLimits.maximumFileCount`,
    /// the ZIP preflight and the tree verifier all say 2000, so the generic guard
    /// must not quietly say 300 (DEC-028).
    ///
    /// The exemption is that array and nothing else. `depth == 1` is a member of
    /// the root object, so an array nested inside an asset entry reaches here
    /// carrying the same path but a greater depth, and keeps the generic bound.
    private static func arrayBound(path: [String], depth: Int, canonicalManifest: Bool) -> Int {
        guard canonicalManifest, depth == 1, path == ["assets"] else { return maximumArrayElements }
        return CharacterPackageLimits.maximumFileCount
    }

    private static func requireExact(_ actual: Set<String>, required: Set<String>, allowed: Set<String>) throws {
        guard required.isSubset(of: actual), actual.isSubset(of: allowed) else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
    }

    /// Motion names are triggered by product code and appear in logs, so they are
    /// deliberately narrower than an asset path: lowercase ASCII, digits, `_` and
    /// `-`, starting alphanumeric.
    private static func validMotionName(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64, let first = value.unicodeScalars.first else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-")
        let leading = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        return leading.contains(first) && value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func validIdentifier(_ value: String, maximum: Int) -> Bool {
        guard !value.isEmpty, value.count <= maximum, let first = value.unicodeScalars.first else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return CharacterSet.alphanumerics.contains(first) && value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func boundedString(_ value: Any?, maximum: Int) -> String? {
        guard let string = value as? String,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              string.count <= maximum else { return nil }
        return string
    }
}

enum Live2DClosure {
    static func references(_ data: Data) throws -> [String] {
        let object = try StrictJSON.object(data, maximumBytes: 4 * 1024 * 1024)
        guard let refs = object["FileReferences"] as? [String: Any] else {
            throw CharacterPackageImportFailure(.invalidRenderer, .validate)
        }
        var paths: [String] = []
        if let moc = refs["Moc"] as? String { paths.append(moc) }
        if let textures = refs["Textures"] as? [String] { paths.append(contentsOf: textures) }
        if let motions = refs["Motions"] as? [String: [[String: Any]]] {
            for group in motions.values { paths.append(contentsOf: group.compactMap { $0["File"] as? String }) }
        }
        if let expressions = refs["Expressions"] as? [[String: Any]] {
            paths.append(contentsOf: expressions.compactMap { $0["File"] as? String })
        }
        for key in ["Physics", "Pose", "DisplayInfo", "UserData"] {
            if let path = refs[key] as? String { paths.append(path) }
        }
        guard !paths.isEmpty else { throw CharacterPackageImportFailure(.invalidRenderer, .validate) }
        return try paths.map {
            let normalized = try RestrictedZIPPolicy.normalizedPath($0)
            guard normalized == $0, !normalized.hasSuffix("/") else {
                throw CharacterPackageImportFailure(.invalidRenderer, .validate)
            }
            return normalized
        }.removingDuplicateStrings()
    }
}

enum CharacterMediaValidator {
    static func mediaType(for path: String) -> String {
        let lower = path.lowercased()
        if lower.hasSuffix(".vrm") || lower.hasSuffix(".vrma") { return "model/gltf-binary" }
        if lower.hasSuffix(".png") { return "image/png" }
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "image/jpeg" }
        if lower.hasSuffix(".webp") { return "image/webp" }
        if lower.hasSuffix(".wav") { return "audio/wav" }
        if lower.hasSuffix(".mp3") { return "audio/mpeg" }
        if lower.hasSuffix(".m4a") { return "audio/mp4" }
        if lower.hasSuffix(".ogg") { return "audio/ogg" }
        if lower.hasSuffix(".moc3") { return "application/vnd.live2d.moc3" }
        if lower.hasSuffix(".json") { return "application/json" }
        return "application/octet-stream"
    }

    static func validate(data: Data, path: String, declaredMediaType: String) throws {
        let expected = mediaType(for: path)
        guard expected != "application/octet-stream", declaredMediaType == expected else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
        let valid: Bool
        switch expected {
        case "model/gltf-binary": valid = (try? VRMNativeMetadataInspector().inspect(data)) != nil
        case "image/png": valid = data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) && imageDecodes(data)
        case "image/jpeg": valid = data.count >= 4 && data.starts(with: [0xff, 0xd8, 0xff]) && data.suffix(2) == Data([0xff, 0xd9]) && imageDecodes(data)
        case "image/webp": valid = data.count >= 12 && data.prefix(4) == Data("RIFF".utf8) && data[8..<12] == Data("WEBP".utf8) && imageDecodes(data)
        case "audio/wav": valid = data.count >= 12 && data.prefix(4) == Data("RIFF".utf8) && data[8..<12] == Data("WAVE".utf8)
        case "audio/mpeg": valid = data.starts(with: Data("ID3".utf8)) || (data.count >= 2 && data[0] == 0xff && data[1] & 0xe0 == 0xe0)
        case "audio/mp4": valid = data.count >= 12 && data[4..<8] == Data("ftyp".utf8)
        case "audio/ogg": valid = data.starts(with: Data("OggS".utf8))
        case "application/vnd.live2d.moc3": valid = data.starts(with: Data("MOC3".utf8))
        case "application/json": valid = (try? CharacterManifestValidator.validateActiveJSON(data)) != nil
        default: valid = false
        }
        guard valid, !looksLikeNestedArchive(data.prefix(512), path: path) else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
    }

    static func validate(url: URL, path: String, declaredMediaType: String) throws {
        let expected = mediaType(for: path)
        guard expected != "application/octet-stream", declaredMediaType == expected else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
        let size = try CharacterPackageMaterializer.readRange(url, offset: 0, count: 0, phase: .validate).fileSize
        let prefixCount = min(size, 512)
        let prefix = try CharacterPackageMaterializer.readRange(url, offset: 0, count: prefixCount, phase: .validate).data
        guard !looksLikeNestedArchive(prefix, path: path) else {
            throw CharacterPackageImportFailure(.invalidManifest, .validate)
        }
        let valid: Bool
        switch expected {
        case "model/gltf-binary":
            valid = (try? VRMNativeMetadataInspector().inspect(vrmMetadataEnvelope(url: url, size: size))) != nil
        case "image/png":
            valid = prefix.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) && imageDecodes(url)
        case "image/jpeg":
            let suffix = size >= 2 ? try CharacterPackageMaterializer.readRange(url, offset: size - 2, count: 2, phase: .validate).data : Data()
            valid = prefix.count >= 3 && prefix.starts(with: [0xff, 0xd8, 0xff]) && suffix == Data([0xff, 0xd9]) && imageDecodes(url)
        case "image/webp":
            valid = prefix.count >= 12 && prefix.prefix(4) == Data("RIFF".utf8) && prefix[8..<12] == Data("WEBP".utf8) && imageDecodes(url)
        case "application/json":
            valid = (try? CharacterManifestValidator.validateActiveJSON(
                CharacterPackageMaterializer.readBounded(url, maximum: 4 * 1024 * 1024, phase: .validate)
            )) != nil
        case "audio/wav": valid = prefix.count >= 12 && prefix.prefix(4) == Data("RIFF".utf8) && prefix[8..<12] == Data("WAVE".utf8)
        case "audio/mpeg": valid = prefix.starts(with: Data("ID3".utf8)) || (prefix.count >= 2 && prefix[0] == 0xff && prefix[1] & 0xe0 == 0xe0)
        case "audio/mp4": valid = prefix.count >= 12 && prefix[4..<8] == Data("ftyp".utf8)
        case "audio/ogg": valid = prefix.starts(with: Data("OggS".utf8))
        case "application/vnd.live2d.moc3": valid = prefix.starts(with: Data("MOC3".utf8))
        default: valid = false
        }
        guard valid else { throw CharacterPackageImportFailure(.invalidManifest, .validate) }
    }

    /// Which VRM flavour a GLB actually is, read from its own glTF extensions
    /// rather than from its file name. Only the JSON chunk is read, so this stays
    /// cheap on a multi-megabyte animation whose bulk is binary.
    static func vrmFormat(at url: URL) throws -> VRMNativeFormat {
        let size = try CharacterPackageMaterializer.readRange(url, offset: 0, count: 0, phase: .validate).fileSize
        do {
            return try VRMNativeMetadataInspector().inspect(vrmMetadataEnvelope(url: url, size: size)).format
        } catch let failure as CharacterPackageImportFailure {
            throw failure
        } catch {
            throw CharacterPackageImportFailure(.invalidRenderer, .validate)
        }
    }

    private static func vrmMetadataEnvelope(url: URL, size: Int) throws -> Data {
        let firstCount = min(size, 20)
        let header = try CharacterPackageMaterializer.readRange(url, offset: 0, count: firstCount, phase: .validate).data
        guard header.count >= 4 else { throw CharacterPackageImportFailure(.invalidRenderer, .validate) }
        if header[0] == Character("{").asciiValue {
            return try CharacterPackageMaterializer.readBounded(url, maximum: 16 * 1024 * 1024, phase: .validate)
        }
        guard header.count == 20,
              readU32(header, 0) == 0x4654_6c67,
              readU32(header, 4) == 2,
              let chunkLength32 = readU32(header, 12),
              readU32(header, 16) == 0x4e4f_534a else {
            throw CharacterPackageImportFailure(.invalidRenderer, .validate)
        }
        let chunkLength = Int(chunkLength32)
        guard chunkLength <= 16 * 1024 * 1024, chunkLength <= size - 20 else {
            throw CharacterPackageImportFailure(.invalidRenderer, .validate)
        }
        let json = try CharacterPackageMaterializer.readRange(url, offset: 20, count: chunkLength, phase: .validate).data
        var envelope = header
        var adjusted = UInt32(20 + chunkLength).littleEndian
        withUnsafeBytes(of: &adjusted) { envelope.replaceSubrange(8..<12, with: $0) }
        envelope.append(json)
        return envelope
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    static func looksLikeNestedArchive<D: DataProtocol>(_ prefix: D, path: String) -> Bool {
        let data = Data(prefix)
        let lower = path.lowercased()
        if [".zip", ".gz", ".gzip", ".7z", ".rar", ".tar"].contains(where: lower.hasSuffix) { return true }
        if data.starts(with: [0x50, 0x4b, 0x03, 0x04]) || data.starts(with: [0x1f, 0x8b]) || data.starts(with: [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c]) { return true }
        if data.starts(with: Data("Rar!\u{1a}\u{07}".utf8)) { return true }
        return data.count >= 262 && data[257..<262] == Data("ustar".utf8)
    }

    private static func imageDecodes(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0,
              width.intValue <= 8192, height.intValue <= 8192,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { return false }
        return true
    }

    private static func imageDecodes(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0,
              width.intValue <= 8192, height.intValue <= 8192,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { return false }
        return true
    }
}

struct CharacterTreeVerification {
    let manifest: CharacterPackageManifestV1
    let receipt: CharacterPackageValidationReceiptV1
}

enum CharacterTreeVerifier {
    static func verify(record: StoredCharacterRecord, paths: CharacterStorePaths) throws -> CharacterTreeVerification {
        let root = try paths.assetRoot(record.contentID)
        guard try rootIdentity(at: root) == record.rootIdentity else {
            throw CharacterPackageImportFailure(.hashMismatch, .activation)
        }
        let verified = try verifyPackage(at: root, expected: record.manifest)
        guard try contentID(at: root) == record.contentID else {
            throw CharacterPackageImportFailure(.hashMismatch, .activation)
        }
        return verified
    }

    static func verifyPackage(
        at root: URL,
        expected: CharacterPackageManifestV1
    ) throws -> CharacterTreeVerification {
        try verifyRoot(root)
        let manifest = try CharacterManifestValidator.validateCanonical(at: root, expected: expected)
        let files = try regularFiles(at: root)
        var bytes = 0
        for path in files {
            try Task.checkCancellation()
            let values = try root.appendingPathComponent(path).resourceValues(forKeys: [.fileSizeKey])
            let size = values.fileSize ?? -1
            guard size >= 0, bytes <= CharacterPackageLimits.maximumExpandedBytes - size else {
                throw CharacterPackageImportFailure(.unsafeArchive, .activation)
            }
            bytes += size
        }
        let manifestData = try CharacterPackageMaterializer.readBounded(root.appendingPathComponent("manifest.json"), maximum: CharacterPackageLimits.maximumManifestBytes, phase: .activation)
        return CharacterTreeVerification(
            manifest: manifest,
            receipt: CharacterPackageValidationReceiptV1(
                manifestSHA256: CharacterDigests.sha256(manifestData),
                expandedBytes: bytes,
                fileCount: files.count,
                validatedAt: Date()
            )
        )
    }

    /// Content identity: what a package *is*, independent of where it was
    /// unpacked (DEC-026).
    ///
    /// Paths enter the hash as their **NFC UTF-8 bytes**, and are ordered by
    /// those bytes, not by the form the filesystem happened to return. Darwin
    /// hands back a decomposed name for a file written composed, so hashing what
    /// the enumerator returned made identity a property of the volume: the same
    /// `.joi-character` installed under one identity here and a different one on
    /// a filesystem that stores names verbatim.
    ///
    /// No test could see that, because Swift's `String` equality is canonical —
    /// the old `normalized == path` guard compared NFC against NFD and returned
    /// true. `Contracts/conformance/content-id.json` is what caught it, by
    /// stating the rule in bytes and running it on both platforms.
    static func contentID(at root: URL) throws -> CharacterContentID {
        try verifyRoot(root)
        // The two forms are kept apart deliberately: the normalized one is what
        // the identity is over, the on-disk one is the only string that opens
        // the file.
        let entries = try regularFiles(at: root)
            .map { (normalized: try RestrictedZIPPolicy.normalizedPath($0), onDisk: $0) }
            .sorted { Array($0.normalized.utf8).lexicographicallyPrecedes(Array($1.normalized.utf8)) }
        var hasher = SHA256()
        frame(Data("joi.character.content-tree.v1".utf8), into: &hasher)
        for entry in entries {
            try Task.checkCancellation()
            let fileDigest = try CharacterDigests.sha256File(
                root.appendingPathComponent(entry.onDisk),
                maximum: CharacterPackageLimits.maximumFileBytes,
                phase: .seal
            )
            frame(Data(entry.normalized.utf8), into: &hasher)
            var size = fileDigest.size.bigEndian
            withUnsafeBytes(of: &size) { hasher.update(bufferPointer: $0) }
            frame(Data(fileDigest.digest.utf8), into: &hasher)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return CharacterContentID(rawValue: "sha256:" + digest)
    }

    static func regularFiles(at root: URL) throws -> [String] {
        try verifyRoot(root)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { throw CharacterPackageImportFailure(.unsafeArchive, .validate) }
        var files: [String] = []
        var collisionKeys = Set<String>()
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw CharacterPackageImportFailure(.unsafeArchive, .validate) }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw CharacterPackageImportFailure(.unsafeArchive, .validate) }
            let prefix = root.standardizedFileURL.path + "/"
            let absolute = url.standardizedFileURL.path
            guard absolute.hasPrefix(prefix) else { throw CharacterPackageImportFailure(.unsafeArchive, .validate) }
            let path = String(absolute.dropFirst(prefix.count))
            let normalized = try RestrictedZIPPolicy.normalizedPath(path)
            guard normalized == path,
                  collisionKeys.insert(RestrictedZIPPolicy.collisionKey(path)).inserted else {
                throw CharacterPackageImportFailure(.unsafeArchive, .validate)
            }
            let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw CharacterPackageImportFailure(.unsafeArchive, .validate) }
            var info = stat()
            let ok = fstat(fd, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG && info.st_nlink == 1
            Darwin.close(fd)
            guard ok else { throw CharacterPackageImportFailure(.unsafeArchive, .validate) }
            files.append(path)
        }
        guard files.count <= CharacterPackageLimits.maximumFileCount + 1 else {
            throw CharacterPackageImportFailure(.unsafeArchive, .validate)
        }
        return files
    }

    static func rootIdentity(at root: URL) throws -> CharacterRootIdentity {
        let fd = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CharacterPackageImportFailure(.notFound, .recovery) }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
            throw CharacterPackageImportFailure(.unsafeArchive, .recovery)
        }
        return CharacterRootIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    private static func verifyRoot(_ root: URL) throws {
        let fd = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CharacterPackageImportFailure(.notFound, .recovery) }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_nlink >= 1 else {
            throw CharacterPackageImportFailure(.unsafeArchive, .recovery)
        }
    }

    private static func frame(_ data: Data, into hasher: inout SHA256) {
        var length = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &length) { hasher.update(bufferPointer: $0) }
        hasher.update(data: data)
    }
}

private extension Array where Element == String {
    func removingDuplicateStrings() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
