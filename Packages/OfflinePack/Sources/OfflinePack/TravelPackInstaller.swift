import CompanionCore
import CryptoKit
import Foundation

/// The walkable content of a travel pack: the route, and the story along it.
///
/// Separate from `TravelPackManifestV1`, which describes the *pack* — identity,
/// version, rights, file list. This describes what the pack is *for*, and is one
/// of the files the manifest declares and hashes like any other.
public struct TravelPackContentV1: Codable, Equatable, Sendable {
    public struct Stop: Codable, Equatable, Sendable {
        public let stopID: String
        public let name: String
        public let latitude: Double
        public let longitude: Double
        public let narration: String
        public let sourceRevisionIDs: [String]
        public let suggestedDurationSeconds: TimeInterval

        public init(
            stopID: String,
            name: String,
            latitude: Double,
            longitude: Double,
            narration: String,
            sourceRevisionIDs: [String] = [],
            suggestedDurationSeconds: TimeInterval
        ) {
            self.stopID = stopID
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.narration = narration
            self.sourceRevisionIDs = sourceRevisionIDs
            self.suggestedDurationSeconds = suggestedDurationSeconds
        }
    }

    public let schema: String
    public let routeID: String
    public let title: String
    public let coordinates: [GeoCoordinate]
    public let stops: [Stop]

    public init(
        schema: String = "joi.travel-pack-content.v1",
        routeID: String,
        title: String,
        coordinates: [GeoCoordinate],
        stops: [Stop]
    ) {
        self.schema = schema
        self.routeID = routeID
        self.title = title
        self.coordinates = coordinates
        self.stops = stops
    }
}

/// A pack that passed every check and is now the one in use.
public struct InstalledTravelPack: Equatable, Sendable {
    public let packID: String
    public let version: String
    public let rights: String
    public let sourceRevisionIDs: [String]
    public let title: String
    public let route: AcceptedNavigationRoute
    public let stops: [RouteStop]
    /// The sealed directory the pack now lives in. Read-only to everything else.
    public let rootURL: URL
}

/// Installs a travel pack from a directory the user chose.
///
/// `JM-P0-014`, and the two failure states behind it: `FAIL-025`
/// `offlinePackMissing` and `FAIL-026` `offlinePackInvalid`. `OfflinePackVerifier`
/// checked a manifest's shape and nothing checked its contents, so a "verified
/// pack" meant a well-formed sentence about files nobody had looked at.
///
/// Deliberately not an archive reader. `CharacterRuntime` owns the restricted
/// ZIP profile (DEC-011/DEC-029) and duplicating that policy here would create a
/// second, weaker copy of the most safety-critical code in the repository. A
/// pack arrives as a directory; packaging it is a later decision that should
/// reuse that profile rather than re-derive it.
public actor TravelPackInstaller {
    /// Ceilings, matching the character package contract's shape rather than
    /// inventing a second set of numbers.
    static let maximumFileCount = 2_000
    static let maximumTotalBytes = 512 * 1_024 * 1_024

    private let root: URL
    private let verifier = OfflinePackVerifier()

    public init(root: URL) {
        self.root = root
    }

    /// Verifies a candidate directory and, only if everything holds, seals it
    /// into the store and returns it.
    ///
    /// Nothing is moved until every check has passed, so a failure leaves the
    /// previously installed pack exactly where it was — which is what `FAIL-026`
    /// means by keeping the last valid version.
    public func install(from candidate: URL, now: Date = Date()) throws -> InstalledTravelPack {
        let manifest = try readManifest(at: candidate)
        try verifier.verify(manifest, now: now)
        guard !manifest.packID.isEmpty, !manifest.version.isEmpty else {
            throw OfflinePackError.invalidManifest
        }
        guard manifest.files.count <= Self.maximumFileCount else {
            throw OfflinePackError.tooManyFiles
        }

        try verifyDeclaredFiles(manifest, in: candidate)
        try refuseUndeclaredFiles(manifest, in: candidate)

        let content = try readContent(manifest, in: candidate)
        let route = AcceptedNavigationRoute(
            routeID: content.routeID,
            coordinates: content.coordinates,
            // A pack is by definition cached content; that is what it is for.
            cached: true
        )
        // Building the narrative is a check, not a convenience: it refuses a
        // route too short to follow and a stop that is not on it.
        let stops = content.stops.map(Self.routeStop)
        let engine = try RouteProgressEngine(route: route, configuration: RouteProgressConfiguration())
        _ = try RouteNarrative(engine: engine, stops: stops)

        let sealed = try seal(candidate, manifest: manifest)
        return InstalledTravelPack(
            packID: manifest.packID,
            version: manifest.version,
            rights: manifest.rights.joined(separator: "; "),
            sourceRevisionIDs: manifest.sourceRevisionIDs,
            title: content.title,
            route: route,
            stops: stops,
            rootURL: sealed
        )
    }

    // MARK: - Reading

    private func readManifest(at candidate: URL) throws -> TravelPackManifestV1 {
        let url = candidate.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OfflinePackError.missingFile("manifest.json")
        }
        do {
            return try Self.decoder.decode(TravelPackManifestV1.self, from: Data(contentsOf: url))
        } catch {
            throw OfflinePackError.invalidManifest
        }
    }

    private func readContent(_ manifest: TravelPackManifestV1, in candidate: URL) throws -> TravelPackContentV1 {
        let url = try Self.resolve(manifest.routePath, in: candidate)
        let content: TravelPackContentV1
        do {
            content = try Self.decoder.decode(TravelPackContentV1.self, from: Data(contentsOf: url))
        } catch {
            throw OfflinePackError.invalidContent
        }
        guard content.schema == "joi.travel-pack-content.v1" else {
            throw OfflinePackError.unsupportedSchema
        }
        return content
    }

    // MARK: - Checks

    /// Every declared file must be present and hash to what the manifest says.
    ///
    /// Missing is `FAIL-025`; wrong is `FAIL-026`. They are different errors
    /// because they need different recoveries — one is a redownload, the other
    /// is a pack you should not trust.
    private func verifyDeclaredFiles(_ manifest: TravelPackManifestV1, in candidate: URL) throws {
        var total = 0
        for file in manifest.files {
            let url = try Self.resolve(file.path, in: candidate)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw OfflinePackError.missingFile(file.path)
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
                throw OfflinePackError.unsupportedEntry(file.path)
            }
            total += (attributes[.size] as? Int) ?? 0
            guard total <= Self.maximumTotalBytes else {
                throw OfflinePackError.packTooLarge
            }
            guard try Self.sha256(of: url) == file.sha256.lowercased() else {
                throw OfflinePackError.hashMismatch(file.path)
            }
        }
    }

    /// A pack ships what it declares and nothing else.
    ///
    /// Without this a pack could carry files no receipt covers, which is the
    /// same hole `DEC-020` closes for character packages: a hash list proves the
    /// declared content, and says nothing at all about content nobody declared.
    private func refuseUndeclaredFiles(_ manifest: TravelPackManifestV1, in candidate: URL) throws {
        let declared = Set(manifest.files.map { Self.normalized($0.path) } + ["manifest.json"])
        for relative in try Self.regularFiles(in: candidate) where !declared.contains(relative) {
            throw OfflinePackError.undeclaredFile(relative)
        }
    }

    // MARK: - Sealing

    /// Copies the verified candidate into the store under its own identity, then
    /// re-reads the manifest from the sealed copy.
    ///
    /// The re-read is the point: a check that passed on the candidate proves
    /// nothing about the bytes that ended up in the store, which is the same
    /// reason the character installer re-opens after moving.
    private func seal(_ candidate: URL, manifest: TravelPackManifestV1) throws -> URL {
        let destination = root
            .appendingPathComponent("packs", isDirectory: true)
            .appendingPathComponent("\(manifest.packID)@\(manifest.version)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let staging = root
            .appendingPathComponent("staging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: staging.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: candidate, to: staging)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw OfflinePackError.activationFailed
        }

        let resealed = try readManifest(at: destination)
        guard resealed.packID == manifest.packID, resealed.version == manifest.version else {
            // The store now holds something other than what was verified. Take
            // it back out rather than leaving it reachable.
            try? FileManager.default.removeItem(at: destination)
            throw OfflinePackError.activationFailed
        }
        try verifyDeclaredFiles(resealed, in: destination)
        return destination
    }

    // MARK: - Helpers

    private static func routeStop(_ stop: TravelPackContentV1.Stop) -> RouteStop {
        RouteStop(
            stopID: stop.stopID,
            name: stop.name,
            coordinate: GeoCoordinate(latitude: stop.latitude, longitude: stop.longitude),
            narration: stop.narration,
            sourceRevisionIDs: stop.sourceRevisionIDs,
            suggestedDurationSeconds: stop.suggestedDurationSeconds
        )
    }

    /// Resolves a declared relative path, refusing anything that could reach
    /// outside the pack.
    private static func resolve(_ path: String, in root: URL) throws -> URL {
        let normalized = Self.normalized(path)
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.contains(".."),
              !normalized.contains("\\"),
              !normalized.unicodeScalars.contains(where: { $0.value < 0x20 })
        else {
            throw OfflinePackError.unsupportedEntry(path)
        }
        let url = root.appendingPathComponent(normalized)
        // A symlink inside the pack could still point anywhere, so the resolved
        // path has to land back inside the root.
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(root.resolvingSymlinksInPath().standardizedFileURL.path) else {
            throw OfflinePackError.unsupportedEntry(path)
        }
        return url
    }

    private static func normalized(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
    }

    private static func regularFiles(in root: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [] }
        var found: [String] = []
        let base = root.standardizedFileURL.path
        while let item = enumerator.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let path = item.standardizedFileURL.path
            guard path.hasPrefix(base) else { continue }
            found.append(normalized(String(path.dropFirst(base.count + 1))))
        }
        return found
    }

    /// Hashed incrementally, so a large narration asset does not have to be held
    /// in memory to be checked.
    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 16), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
