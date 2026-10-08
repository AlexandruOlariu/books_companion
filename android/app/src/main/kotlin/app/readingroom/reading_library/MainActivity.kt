package app.readingroom.reading_library

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "reading_library/updates")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installed" -> {
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageInfo(packageName, 0)
                        @Suppress("DEPRECATION")
                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                        result.success(mapOf(
                            "version" to info.versionName,
                            "buildNumber" to code,
                            "applicationId" to packageName
                        ))
                    }
                    "download" -> {
                        val uri = (call.arguments as? String)?.let { Uri.parse(it) }
                        if (uri == null || uri.scheme != "https" || uri.host != "github.com" ||
                            !uri.path.orEmpty().startsWith("/AlexandruOlariu/books_companion/releases/download/") ||
                            !uri.path.orEmpty().endsWith("/reading-library.apk")) {
                            result.error("invalid_url", "Invalid update address", null)
                        } else {
                            try {
                                startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
                                result.success(null)
                            } catch (e: android.content.ActivityNotFoundException) {
                                result.error("no_browser", "No browser is available", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
