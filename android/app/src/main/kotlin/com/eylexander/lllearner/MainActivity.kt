package com.eylexander.lllearner

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Bridge to the Claude app (see lib/coach.dart): opens Claude directly with a
// prefilled message, and receives text shared back from Claude.
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
    }

    private fun sharedText(i: Intent?) =
        if (i?.action == Intent.ACTION_SEND) i.getStringExtra(Intent.EXTRA_TEXT) else null

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
