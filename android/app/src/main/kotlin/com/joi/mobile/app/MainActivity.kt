package com.joi.mobile.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.joi.mobile.core.CharacterSelection

/**
 * The composition root, and the only place that constructs the state owner.
 *
 * The store is held by the activity rather than created inside a composable so a
 * configuration change redraws the surfaces without inventing a second companion
 * session — the same reason iOS keeps it out of the view layer.
 */
class MainActivity : ComponentActivity() {

    private val store by lazy {
        CompanionSessionStore(
            CompanionSessionState(
                surface = CompanionSurface.CHAT,
                // No character is installed on this platform yet, and no
                // installer is wired. This is the bundled static identity, not a
                // package, and nothing here should be read as one.
                character = CharacterSelection(characterID = "joi.starter", displayName = "Joi"),
                threadID = "local.thread",
                sessionID = "local.session",
                acceptedTranscript = emptyList(),
            )
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { JoiApp(store) }
    }
}
