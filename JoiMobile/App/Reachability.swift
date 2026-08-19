import Foundation
import Network
import OSLog

private let networkLog = Logger(subsystem: "com.joi.mobile", category: "network")

/// What the device's network interfaces report.
///
/// Three cases rather than a `Bool`, because "we have not looked yet" and "we
/// looked and there is nothing" must not behave the same way: `NWPathMonitor`
/// delivers its first path asynchronously, and refusing a send in that window
/// would make every cold launch look offline.
enum NetworkReachability: Equatable, Sendable {
    case unknown
    /// At least one interface can carry a request. This proves nothing about
    /// whether Joi's backend answers.
    case interfaceAvailable
    /// No interface can carry a request.
    case unreachable
}

/// Whether a chat turn may be attempted at all (`FAIL-024`, `G2-J5G`).
///
/// The asymmetry is the whole point of this type, and it is worth stating
/// plainly rather than leaving in the shape of the code: **a network that says
/// it is there proves nothing.** The proxy may be down, a captive portal may be
/// answering for it, the route may be black-holed. A network that says it is
/// *not* there is the one report worth acting on, because it cannot be wrong in
/// the direction that matters.
///
/// So this only ever refuses. It never promises, and it does not replace
/// `G2-J5C`'s stall timeout — that watchdog remains the only thing that can
/// prove a live-looking connection is dead.
enum SendPrecondition {

    /// `false` only when the device is certain nothing can be sent.
    static func mayAttemptTurn(_ reachability: NetworkReachability) -> Bool {
        reachability != .unreachable
    }
}

/// Watches the device's network interfaces.
///
/// Deliberately reports one fact and derives no policy: `isExpensive` and
/// `isConstrained` are read from the path and deliberately *not* acted on. A
/// chat turn is something the user just asked for, not discretionary background
/// work, so Low Data Mode is not a reason to refuse it — and refusing on
/// cellular would be a data-saving promise this product has never made.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var reachability: NetworkReachability = .unknown
    /// Recorded for diagnostics only; nothing branches on it. See the note above.
    private(set) var isExpensive = false
    private(set) var isConstrained = false

    @ObservationIgnored private let monitor: NWPathMonitor?

    /// - Parameter monitor: `nil` leaves this inert at `.unknown`, which is what
    ///   a test wants: a suite that started a real monitor would report whatever
    ///   the build machine's Wi-Fi happened to be doing.
    init(monitor: NWPathMonitor? = NWPathMonitor()) {
        self.monitor = monitor
        guard let monitor else { return }
        monitor.pathUpdateHandler = { path in
            // `NWPath` is not Sendable, so the three facts are read here on the
            // monitor's own queue and only plain values cross to the actor.
            let status = path.status
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            Task { @MainActor [weak self] in
                self?.apply(status: status, expensive: expensive, constrained: constrained)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.joi.mobile.network"))
    }

    deinit { monitor?.cancel() }

    /// Applies one path report. Internal so a test can drive the same path the
    /// system drives without a network interface.
    func apply(status: NWPath.Status, expensive: Bool, constrained: Bool) {
        isExpensive = expensive
        isConstrained = constrained
        let next: NetworkReachability
        switch status {
        case .satisfied:
            next = .interfaceAvailable
        case .unsatisfied:
            next = .unreachable
        case .requiresConnection:
            // A connection would have to be brought up first, so nothing can be
            // sent right now. Read as unreachable rather than as "probably fine".
            next = .unreachable
        @unknown default:
            // An unknown status is not evidence of absence, and refusing on it
            // would ground the app on a future OS for no reason.
            next = .interfaceAvailable
        }
        guard next != reachability else { return }
        reachability = next
        networkLog.notice("network reachability: \(String(describing: next), privacy: .public)")
    }
}
