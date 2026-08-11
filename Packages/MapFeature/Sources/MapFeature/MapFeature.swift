import CompanionCore
import Foundation
import OfflinePack

public struct MapExperienceState: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var isOffline: Bool
    public var routeProgress: Double

    public init(
        title: String = "文化步行",
        detail: String = "已缓存路线预览",
        isOffline: Bool = true,
        routeProgress: Double = 0
    ) {
        self.title = title
        self.detail = detail
        self.isOffline = isOffline
        self.routeProgress = routeProgress
    }
}
