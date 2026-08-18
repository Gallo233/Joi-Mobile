import CompanionCore
import Foundation

/// One journey fact, carried from Map into Chat for exactly one turn.
///
/// `G2-J3B`. DEC-002 lets precise location reach Chat "only through explicit,
/// inspectable attachment/consent", and the load-bearing word is *inspectable*:
/// if the preview and the payload are two different objects, the user approves
/// one thing and the product sends another. So this type is both. It is built
/// once, from the journey owner's snapshot, already reduced to exactly the bytes
/// that will travel; the preview renders these fields and the request carries
/// this `payload`. There is deliberately no initialiser that takes a precise
/// coordinate and no accessor that returns one.
struct JourneyAttachment: Equatable, Sendable {
    /// The coarsening grid in degrees. 0.001° is about 111 m of latitude, and
    /// about 95 m of longitude at this route's latitude.
    static let gridDegrees = 0.001

    /// The floor this grid puts under positional uncertainty, in metres. A fix
    /// good to 5 m that has been rounded onto a ~111 m grid is not a 5 m fix any
    /// more, and saying so is the difference between coarsening and pretending.
    static let gridMeters = 111.0

    /// What the receipt records as the precision that was authorised. Stated as
    /// the grid rather than as a metre figure because the metre figure changes
    /// with latitude and the grid does not.
    static let precision = "coarse-0.001deg"

    /// Scope written into the payload itself, so the bytes say what they were
    /// authorised for. The digest covers this field, so a receipt issued for a
    /// one-turn chat payload cannot validate against the same position carrying
    /// any other scope — the authorisation is bound to the purpose, not just to
    /// the coordinates.
    static let consentScope = "chat-one-turn"

    /// How long the offer stands. A walking fact answers "where am I now", and
    /// five minutes later that answer is usually wrong; expiring is cheaper than
    /// sending a stale position and re-attaching costs one tap.
    static let lifetime: TimeInterval = 300

    /// The act being authorised, recorded in the receipt.
    static let userAction = "map.ask-in-chat"

    /// Exactly what will be sent. Already coarsened.
    let payload: JourneyContextSnapshot
    /// Display only — the walk's human name never enters the payload.
    let routeTitle: String
    let receiptID: String
    let issuedAt: Date
    let expiresAt: Date

    /// Builds the attachment from the journey owner's snapshot, or returns `nil`
    /// when there is no journey to speak of. Refusing here is what stops the
    /// action from manufacturing a location for a walk that is not running.
    init?(
        journey: JourneyContextSnapshot,
        routeTitle: String,
        at now: Date,
        receiptID: String = UUID().uuidString.lowercased()
    ) {
        guard journey.routeID != nil else { return nil }
        self.routeTitle = routeTitle
        self.receiptID = receiptID
        issuedAt = now
        expiresAt = now.addingTimeInterval(Self.lifetime)
        payload = JourneyContextSnapshot(
            journeyID: journey.journeyID,
            placeID: journey.placeID,
            routeID: journey.routeID,
            stopID: journey.stopID,
            coordinate: journey.coordinate.map(Self.coarsen),
            // A coarsened coordinate is no more accurate than its grid, whatever
            // the receiver's fix was worth.
            horizontalAccuracyMeters: journey.coordinate == nil
                ? nil
                : max(journey.horizontalAccuracyMeters ?? 0, Self.gridMeters),
            observedAt: journey.observedAt,
            routeProgress: journey.routeProgress,
            identityConfidence: journey.identityConfidence,
            sourceRevisionIDs: journey.sourceRevisionIDs,
            consentScope: Self.consentScope
        )
    }

    /// Rounds onto the shared grid. Both surfaces and the digest see this value
    /// and only this value.
    static func coarsen(_ coordinate: GeoCoordinate) -> GeoCoordinate {
        GeoCoordinate(
            latitude: (coordinate.latitude / gridDegrees).rounded() * gridDegrees,
            longitude: (coordinate.longitude / gridDegrees).rounded() * gridDegrees
        )
    }

    func isExpired(at date: Date) -> Bool { date >= expiresAt }

    /// The receipt for one specific request. `receiptID` is a property of the
    /// attachment rather than of the request, so a second send of the same
    /// approved payload presents an already-consumed receipt to
    /// `JourneyUseReceiptStore` instead of a fresh one.
    func receipt(threadID: String, requestID: String) -> JourneyUseReceiptV1 {
        JourneyUseReceiptV1(
            receiptID: receiptID,
            purpose: .chatOneTurn,
            userAction: Self.userAction,
            payloadDigest: payload.payloadDigest(),
            precision: Self.precision,
            threadID: threadID,
            requestID: requestID,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            revoked: false
        )
    }

    // MARK: - What the user is shown

    /// The position as it will be sent, at the grid's own resolution — three
    /// decimals, because a fourth would display precision the payload does not
    /// contain.
    var positionLine: String? {
        guard let coordinate = payload.coordinate else { return nil }
        // Fixed POSIX formatting: this is a number the user compares against a
        // payload, so it must not pick up a locale's own decimal separator.
        let latitude = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            abs(coordinate.latitude)
        )
        let longitude = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            abs(coordinate.longitude)
        )
        let latitudeName = coordinate.latitude < 0
            ? String(localized: "南纬")
            : String(localized: "北纬")
        let longitudeName = coordinate.longitude < 0
            ? String(localized: "西经")
            : String(localized: "东经")
        return String(localized: "大致位置 \(latitudeName) \(latitude)°，\(longitudeName) \(longitude)°")
    }

    var progressLine: String? {
        guard let progress = payload.routeProgress else { return nil }
        return String(localized: "已完成 \(Int((progress * 100).rounded()))%")
    }

    /// Whole minutes remaining, rounded up, so a live countdown never reads zero
    /// while the attachment is still sendable.
    func minutesRemaining(at date: Date) -> Int {
        max(0, Int((expiresAt.timeIntervalSince(date) / 60).rounded(.up)))
    }
}
