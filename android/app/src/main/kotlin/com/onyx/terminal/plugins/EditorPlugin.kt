package com.onyx.terminal.plugins

import android.content.Context
import com.onyx.terminal.editor.EncodingDetector
import com.onyx.terminal.editor.TextEditor
import com.onyx.terminal.util.Channels
import com.onyx.terminal.util.Disposable
import com.onyx.terminal.util.bool
import com.onyx.terminal.util.long
import com.onyx.terminal.util.reply
import com.onyx.terminal.util.requireStr
import com.onyx.terminal.util.str
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import java.io.File

class EditorPlugin(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, Disposable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val channel = MethodChannel(messenger, Channels.EDITOR)
    private val editor = TextEditor()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "read" -> scope.reply(result) { editor.read(call.requireStr("path"), call.str("encoding")) }
            "write" -> scope.reply(result) {
                val expected = call.long("expectedModified", 0L)
                editor.write(
                    call.requireStr("path"),
                    call.requireStr("text"),
                    call.str("encoding") ?: "UTF-8",
                    call.str("lineEnding") ?: "lf",
                    call.bool("bom", false),
                    call.bool("backup", false),
                    if (expected > 0) expected else null
                )
            }
            "language" -> result.success(editor.languageOf(File(call.requireStr("path"))))
            "encodings" -> result.success(EncodingDetector.available())
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }
}
