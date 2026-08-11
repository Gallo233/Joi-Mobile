import CompanionCore
import Observation

enum PrimarySurface: String, CaseIterable, Sendable {
    case chat
    case map
}

@MainActor
@Observable
final class AppModel {
    var selectedSurface: PrimarySurface = .chat
    var currentCharacterName = "Joi"
    var threadLabel = "本地会话"

    let companionSession = CompanionSessionStore(
        characterID: "joi.starter",
        threadID: "thread.local",
        sessionID: "session.local"
    )
    let journeyContext = JourneyContextStore()
    let speechCoordinator = SpeechCoordinator()

    func select(_ surface: PrimarySurface) {
        selectedSurface = surface
    }
}
