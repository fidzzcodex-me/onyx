package com.onyx.terminal.plugins

import android.content.Context
import com.onyx.terminal.util.Channels
import com.onyx.terminal.util.Disposable
import com.onyx.terminal.util.hexToBytes
import com.onyx.terminal.util.int
import com.onyx.terminal.util.long
import com.onyx.terminal.util.reply
import com.onyx.terminal.util.requireStr
import com.onyx.terminal.viewer.AudioViewer
import com.onyx.terminal.viewer.DocumentViewer
import com.onyx.terminal.viewer.HexViewer
import com.onyx.terminal.viewer.ImageViewer
import com.onyx.terminal.viewer.PdfViewer
import com.onyx.terminal.viewer.VideoViewer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

class ViewerPlugin(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, Disposable {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val channel = MethodChannel(messenger, Channels.VIEWER)
    private val image = ImageViewer()
    private val video = VideoViewer()
    private val audio = AudioViewer()
    private val pdf = PdfViewer()
    private val hex = HexViewer()
    private val documents = DocumentViewer()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "imageInfo" -> scope.reply(result) { image.info(call.requireStr("path")) }
            "imageThumb" -> scope.reply(result) {
                image.thumbnail(call.requireStr("path"), call.int("size", 256))
            }
            "videoInfo" -> scope.reply(result) { video.info(call.requireStr("path")) }
            "videoThumb" -> scope.reply(result) {
                video.thumbnail(call.requireStr("path"), call.long("positionMs", 0L), call.int("size", 320))
            }
            "audioInfo" -> scope.reply(result) { audio.info(call.requireStr("path")) }
            "pdfInfo" -> scope.reply(result) { pdf.info(call.requireStr("path")) }
            "pdfPage" -> scope.reply(result) {
                pdf.renderPage(call.requireStr("path"), call.int("index", 0), call.int("width", 1080))
            }
            "hexRead" -> scope.reply(result) {
                hex.read(call.requireStr("path"), call.long("offset", 0L), call.int("length", 4096))
            }
            "hexFind" -> scope.reply(result) {
                hex.find(call.requireStr("path"), hexToBytes(call.requireStr("hex")), call.long("from", 0L))
            }
            "textFind" -> scope.reply(result) {
                hex.find(call.requireStr("path"), call.requireStr("text").toByteArray(Charsets.UTF_8), call.long("from", 0L))
            }
            "json" -> scope.reply(result) { documents.json(call.requireStr("path")) }
            "csv" -> scope.reply(result) { documents.csv(call.requireStr("path"), call.int("maxRows", 2000)) }
            "plain" -> scope.reply(result) { documents.plain(call.requireStr("path")) }
            else -> result.notImplemented()
        }
    }

    override fun dispose() {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }
}
