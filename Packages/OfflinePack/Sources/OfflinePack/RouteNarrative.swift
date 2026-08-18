import CompanionCore
import Foundation

/// One stop on a cultural walk: somewhere to stand, something to hear, and what
/// stands behind it.
public struct RouteStop: Equatable, Sendable {
    public let stopID: String
    public let name: String
    public let coordinate: GeoCoordinate
    /// Cached narration. It travels with the route, so it is readable with no
    /// network — which is the whole point of a downloaded tour.
    public let narration: String
    /// The immutable source revisions supporting `narration`.
    ///
    /// Empty is a meaningful value, not a missing one: it declares the narration
    /// to be the character's own reflection rather than a factual claim. The
    /// recap keeps the two apart on exactly this field.
    public let sourceRevisionIDs: [String]
    /// How long this stop is worth, for pacing. Not a countdown and not
    /// enforced — a stop is finished by walking on, not by a timer.
    public let suggestedDurationSeconds: TimeInterval

    public init(
        stopID: String,
        name: String,
        coordinate: GeoCoordinate,
        narration: String,
        sourceRevisionIDs: [String] = [],
        suggestedDurationSeconds: TimeInterval
    ) {
        self.stopID = stopID
        self.name = name
        self.coordinate = coordinate
        self.narration = narration
        self.sourceRevisionIDs = sourceRevisionIDs
        self.suggestedDurationSeconds = suggestedDurationSeconds
    }

    /// Whether this stop's narration is a factual claim at all. A stop with no
    /// source is not unsupported — it is not making a claim.
    public var isFactual: Bool { !sourceRevisionIDs.isEmpty }
}

public enum StopCompletion: String, Codable, Equatable, Sendable {
    case ahead
    case completed
}

public struct StopProgress: Equatable, Sendable {
    public let stop: RouteStop
    /// Where this stop falls along the route, 0…1.
    public let progressAlongRoute: Double
    public let completion: StopCompletion

    public init(stop: RouteStop, progressAlongRoute: Double, completion: StopCompletion) {
        self.stop = stop
        self.progressAlongRoute = progressAlongRoute
        self.completion = completion
    }
}

/// One line of a trip recap, and whether it is a fact or the character talking.
///
/// `JM-P0-012` requires a recap that distinguishes sourced facts from the
/// character's reflective language. Two cases rather than one case with a flag,
/// so a reflection has nowhere to put a source revision and a fact cannot exist
/// without one — the distinction is unrepresentable-in-the-wrong-state rather
/// than a rule someone has to remember.
public enum RecapEntry: Equatable, Sendable {
    case fact(stopID: String, name: String, text: String, sourceRevisionIDs: [String])
    case reflection(stopID: String, name: String, text: String)

    public var stopID: String {
        switch self {
        case let .fact(stopID, _, _, _), let .reflection(stopID, _, _): stopID
        }
    }

    public var isFact: Bool {
        if case .fact = self { return true }
        return false
    }
}

public struct RouteNarrativeState: Equatable, Sendable {
    public let stops: [StopProgress]
    /// Where the walker is standing now — the last stop they have reached. It
    /// can sit behind `nextStop` when someone doubles back.
    public let currentStop: RouteStop?
    /// The first stop not yet reached, or `nil` on a finished walk.
    public let nextStop: RouteStop?
    public let completedCount: Int
    public let isComplete: Bool
    /// Suggested time still to spend, summed over stops not yet reached.
    public let remainingSuggestedSeconds: TimeInterval
}

/// The ordered story a cached route tells, and how far through it you are.
///
/// `JM-P0-012`. `RouteProgressEngine` answers "how far along the line am I";
/// this answers "which part of the story is that", which is a different
/// question and the one the product is actually about.
public struct RouteNarrative: Sendable {
    public let stops: [StopProgress]

    /// Fails rather than silently dropping a stop that is not on this route:
    /// a tour missing one of its stops is a broken pack, not a shorter tour.
    public init(engine: RouteProgressEngine, stops: [RouteStop]) throws {
        guard !stops.isEmpty else { throw OfflinePackError.noStops }
        var located: [StopProgress] = []
        for stop in stops {
            guard let progress = engine.progressAlong(stop.coordinate) else {
                throw OfflinePackError.stopOffRoute(stop.stopID)
            }
            located.append(
                StopProgress(stop: stop, progressAlongRoute: progress, completion: .ahead)
            )
        }
        // Ordered by the route, not by the order they were authored in, so a
        // pack that lists its stops out of order still tells the story in the
        // order a walker meets them.
        self.stops = located.sorted { $0.progressAlongRoute < $1.progressAlongRoute }
    }

    /// The state of the walk, given where the walker is now and the furthest
    /// they have got.
    ///
    /// Completion is decided by `furthestProgress`, never by `currentProgress`.
    /// Walking back to look at something again must not un-visit the stops
    /// beyond it, and a walk that is paused and resumed must not forget what it
    /// covered — keeping the high-water mark outside this type is what makes
    /// both true without any state living in here.
    public func state(currentProgress: Double, furthestProgress: Double) -> RouteNarrativeState {
        let reached = max(currentProgress, furthestProgress)
        let resolved = stops.map { entry in
            StopProgress(
                stop: entry.stop,
                progressAlongRoute: entry.progressAlongRoute,
                completion: entry.progressAlongRoute <= reached ? .completed : .ahead
            )
        }
        let next = resolved.first { $0.completion == .ahead }?.stop
        let current = resolved.last { $0.progressAlongRoute <= currentProgress }?.stop
        let remaining = resolved
            .filter { $0.completion == .ahead }
            .reduce(0) { $0 + $1.stop.suggestedDurationSeconds }
        return RouteNarrativeState(
            stops: resolved,
            currentStop: current,
            nextStop: next,
            completedCount: resolved.count { $0.completion == .completed },
            isComplete: next == nil,
            remainingSuggestedSeconds: remaining
        )
    }

    /// The trip recap: what was actually reached, in route order, with facts and
    /// reflections kept apart.
    ///
    /// Only reached stops appear. A recap of somewhere you did not go would be
    /// a summary of the pack rather than of the walk.
    public func recap(furthestProgress: Double) -> [RecapEntry] {
        stops
            .filter { $0.progressAlongRoute <= furthestProgress }
            .map { entry in
                entry.stop.isFactual
                    ? .fact(
                        stopID: entry.stop.stopID,
                        name: entry.stop.name,
                        text: entry.stop.narration,
                        sourceRevisionIDs: entry.stop.sourceRevisionIDs
                    )
                    : .reflection(
                        stopID: entry.stop.stopID,
                        name: entry.stop.name,
                        text: entry.stop.narration
                    )
            }
    }
}
