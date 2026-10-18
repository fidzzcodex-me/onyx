package com.onyx.terminal

import android.view.WindowManager
import com.onyx.terminal.plugins.AuthPlugin
import com.onyx.terminal.plugins.EditorPlugin
import com.onyx.terminal.plugins.FileSystemPlugin
import com.onyx.terminal.plugins.ProcessPlugin
import com.onyx.terminal.plugins.SftpPlugin
import com.onyx.terminal.plugins.SystemPlugin
import com.onyx.terminal.plugins.TerminalPlugin
import com.onyx.terminal.plugins.ViewerPlugin
import com.onyx.terminal.sftp.ConnectionManager
import com.onyx.terminal.terminal.PtyManager
import com.onyx.terminal.util.Channels
import com.onyx.terminal.util.Disposable
import com.onyx.terminal.util.bool
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val plugins = ArrayList<Disposable>()
    private var windowChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        disposePlugins()
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val connections = ConnectionManager(applicationContext)
        plugins.add(AuthPlugin(this, messenger))
        plugins.add(TerminalPlugin(applicationContext, messenger, connections))
        plugins.add(SftpPlugin(applicationContext, messenger, connections))
        plugins.add(FileSystemPlugin(applicationContext, messenger))
        plugins.add(EditorPlugin(applicationContext, messenger))
        plugins.add(ViewerPlugin(applicationContext, messenger))
        plugins.add(SystemPlugin(applicationContext, messenger))
        plugins.add(ProcessPlugin(applicationContext, messenger))
        val channel = MethodChannel(messenger, Channels.WINDOW)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    runOnUiThread {
                        if (call.bool("enabled", false)) {
                            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                }
                "setKeepScreenOn" -> {
                    runOnUiThread {
                        if (call.bool("enabled", false)) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                }
                "moveToBack" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        windowChannel = channel
    }

    override fun onResume() {
        super.onResume()
        PtyManager.appForeground = true
    }

    override fun onPause() {
        PtyManager.appForeground = false
        super.onPause()
    }

    private fun disposePlugins() {
        for (plugin in plugins) {
            try {
                plugin.dispose()
            } catch (_: Exception) {
            }
        }
        plugins.clear()
        windowChannel?.setMethodCallHandler(null)
        windowChannel = null
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        disposePlugins()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        if (isFinishing) disposePlugins()
        super.onDestroy()
    }
}
