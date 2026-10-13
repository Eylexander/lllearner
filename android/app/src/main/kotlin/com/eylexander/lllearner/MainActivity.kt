package com.eylexander.lllearner

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Bridge to the Claude app (see lib/coach.dart): opens Claude directly with a
// prefilled message, and receives text shared back from Claude. Also opens the
// text-to-speech settings, where the course language's voice is installed, and sets the
// daily reminder (Reminder.kt).
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingShare: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingShare = sharedText(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        sharedText(intent)?.let { channel?.invokeMethod("sharedText", it) }
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "lllearner/claude").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "openClaude" -> result.success(openClaude(call.arguments as String))
                    "takeSharedText" -> result.success(pendingShare).also { pendingShare = null }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "lllearner/android").setMethodCallHandler { call, result ->
            when (call.method) {
                "openTtsSettings" -> result.success(openTtsSettings())
                "setReminder" -> {
                    val on = call.argument<Boolean>("on")!!
                    Reminder.set(this, on, call.argument<Int>("minutes")!!, call.argument<String>("db")!!)
                    if (on && call.argument<Boolean>("ask") == true && Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Android's TTS settings (no public constant), else the engine's voice-data installer. */
    private fun openTtsSettings(): Boolean {
        for (action in listOf("com.android.settings.TTS_SETTINGS", TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA)) {
            try {
                startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (e: ActivityNotFoundException) {
                continue
            }
        }
        return false
    }

    // Not when reopened from recents: Android replays the share that started the task.
    private fun sharedText(i: Intent?) =
        if (i?.action == Intent.ACTION_SEND && (i.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0)
            i.getStringExtra(Intent.EXTRA_TEXT) else null

    private fun openClaude(text: String) = try {
        startActivity(
            Intent(Intent.ACTION_SEND)
                .setType("text/plain")
                .putExtra(Intent.EXTRA_TEXT, text)
                .setPackage("com.anthropic.claude")
        )
        true
    } catch (e: ActivityNotFoundException) {
        false
    }
}
