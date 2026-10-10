package io.ld2t.ai_cleaner

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is required by local_auth (biometric prompt).
class MainActivity : FlutterFragmentActivity() {
    private var bridge: NativeBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NativeBridge.CHANNEL)
        bridge = NativeBridge(this).also { channel.setMethodCallHandler(it) }
    }

    override fun onDestroy() {
        bridge?.dispose()
        super.onDestroy()
    }
}
