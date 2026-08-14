package com.joi.mobile.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.joi.mobile.R
import com.joi.mobile.core.CharacterSelection

/**
 * The two-surface shell.
 *
 * Chat and Map are the only primary surfaces; the character library, account,
 * downloads, memory and settings are secondary destinations that do not exist
 * yet. Both surfaces read one snapshot from [CompanionSessionStore] and keep no
 * character state of their own.
 *
 * Everything drawn below is an honest placeholder. There is no renderer, no
 * backend and no map on this platform yet, and the copy says so rather than
 * implying otherwise with a spinner.
 */
@Composable
fun JoiApp(store: CompanionSessionStore) {
    var state by remember { mutableStateOf(store.state) }
    DisposableEffect(store) {
        val cancel = store.observe { state = it }
        onDispose(cancel)
    }

    MaterialTheme {
        Surfaces(state = state, onSelect = store::show)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Surfaces(state: CompanionSessionState, onSelect: (CompanionSurface) -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(title = { Text(state.character.displayName) })
        },
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = state.surface == CompanionSurface.CHAT,
                    onClick = { onSelect(CompanionSurface.CHAT) },
                    icon = {},
                    label = { Text(stringResource(R.string.surface_chat)) },
                )
                NavigationBarItem(
                    selected = state.surface == CompanionSurface.MAP,
                    onClick = { onSelect(CompanionSurface.MAP) },
                    icon = {},
                    label = { Text(stringResource(R.string.surface_map)) },
                )
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (state.surface) {
                CompanionSurface.CHAT -> ChatSurface(state)
                CompanionSurface.MAP -> MapSurface()
            }
        }
    }
}

@Composable
private fun ChatSurface(state: CompanionSessionState) {
    Column(
        Modifier.fillMaxSize().padding(16.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.character_stage_native), style = MaterialTheme.typography.titleMedium)
                Text(stringResource(R.string.stage_placeholder_notice), style = MaterialTheme.typography.bodySmall)
            }
        }

        Text(stringResource(R.string.session_local), style = MaterialTheme.typography.labelLarge)

        if (state.acceptedTranscript.isEmpty()) {
            Text(stringResource(R.string.transcript_empty), style = MaterialTheme.typography.bodyMedium)
        } else {
            state.acceptedTranscript.forEach { line ->
                Text(line.displayText, style = MaterialTheme.typography.bodyMedium)
            }
        }

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.composer_placeholder, state.character.displayName))
                Text(stringResource(R.string.push_to_talk), style = MaterialTheme.typography.labelMedium)
                Text(stringResource(R.string.composer_placeholder_notice), style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun MapSurface() {
    Column(
        Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.Start,
    ) {
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(stringResource(R.string.map_cached_walk), style = MaterialTheme.typography.titleMedium)
                Text(stringResource(R.string.map_offline_available), style = MaterialTheme.typography.bodySmall)
                Text(stringResource(R.string.map_route_preview), style = MaterialTheme.typography.bodyMedium)
                Text(stringResource(R.string.map_view_sources), style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Preview
@Composable
private fun JoiAppPreview() {
    JoiApp(
        CompanionSessionStore(
            CompanionSessionState(
                surface = CompanionSurface.CHAT,
                character = CharacterSelection(characterID = "joi.starter", displayName = "Joi"),
                threadID = "preview.thread",
                sessionID = "preview.session",
                acceptedTranscript = emptyList(),
            )
        )
    )
}
