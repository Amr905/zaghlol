package app.zaghlol

import app.zaghlol.platform.keys.SecretStoreRegistration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // T-015: the database key store. The T-008 headless engine must register
    // it too (every engine that opens the database).
    SecretStoreRegistration.register(flutterEngine.dartExecutor.binaryMessenger, this)
  }
}
