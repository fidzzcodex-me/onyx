package com.onyx.terminal.viewer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.pdf.PdfRenderer
import android.media.MediaMetadataRetriever
import android.os.ParcelFileDescriptor
import com.onyx.terminal.util.OnyxException
import java.io.ByteArrayOutputStream
import java.io.File

class ImageViewer {
    fun info(path: String): Map<String, Any?> {
        val file = requireFile(path)
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, options)
        return mapOf(
            "width" to options.outWidth,
            "height" to options.outHeight,
            "mime" to options.outMimeType,
            "size" to file.length(),
            "modified" to file.lastModified()
        )
    }

    fun thumbnail(path: String, maxSide: Int): ByteArray {
        val file = requireFile(path)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw OnyxException("decode_failed", "Gambar tidak dapat dibaca")
        }
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= maxSide && bounds.outHeight / (sample * 2) >= maxSide) sample *= 2
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.RGB_565
        }
        val bitmap = BitmapFactory.decodeFile(file.absolutePath, options)
            ?: throw OnyxException("decode_failed", "Gambar tidak dapat didekode")
        return compress(bitmap, 82)
    }
}

class VideoViewer {
    fun info(path: String): Map<String, Any?> {
        val file = requireFile(path)
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            fun meta(key: Int): String? = retriever.extractMetadata(key)
            return mapOf(
                "durationMs" to (meta(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L),
                "width" to (meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0),
                "height" to (meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0),
                "rotation" to (meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0),
                "bitrate" to (meta(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull() ?: 0L),
                "mime" to meta(MediaMetadataRetriever.METADATA_KEY_MIMETYPE),
                "size" to file.length()
            )
        } catch (error: Exception) {
            throw OnyxException("decode_failed", "Metadata video tidak dapat dibaca: ${error.message}", error)
        } finally {
            retriever.release()
        }
    }

    fun thumbnail(path: String, positionMs: Long, maxSide: Int): ByteArray {
        val file = requireFile(path)
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            val frame = retriever.getFrameAtTime(positionMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: throw OnyxException("decode_failed", "Frame video tidak tersedia")
            val longest = maxOf(frame.width, frame.height).coerceAtLeast(1)
            val scaled = if (longest > maxSide) {
                val ratio = maxSide.toFloat() / longest
                Bitmap.createScaledBitmap(frame, (frame.width * ratio).toInt().coerceAtLeast(1), (frame.height * ratio).toInt().coerceAtLeast(1), true)
            } else {
                frame
            }
            return compress(scaled, 80)
        } catch (error: OnyxException) {
            throw error
        } catch (error: Exception) {
            throw OnyxException("decode_failed", "Thumbnail video gagal: ${error.message}", error)
        } finally {
            retriever.release()
        }
    }
}

class AudioViewer {
    fun info(path: String): Map<String, Any?> {
        val file = requireFile(path)
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(file.absolutePath)
            fun meta(key: Int): String? = retriever.extractMetadata(key)?.takeIf { it.isNotBlank() }
            val art = retriever.embeddedPicture
            return mapOf(
                "title" to meta(MediaMetadataRetriever.METADATA_KEY_TITLE),
                "artist" to meta(MediaMetadataRetriever.METADATA_KEY_ARTIST),
                "album" to meta(MediaMetadataRetriever.METADATA_KEY_ALBUM),
                "year" to meta(MediaMetadataRetriever.METADATA_KEY_YEAR),
                "genre" to meta(MediaMetadataRetriever.METADATA_KEY_GENRE),
                "track" to meta(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER),
                "durationMs" to (meta(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L),
                "bitrate" to (meta(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull() ?: 0L),
                "cover" to art,
                "size" to file.length()
            )
        } catch (error: Exception) {
            throw OnyxException("decode_failed", "Metadata audio tidak dapat dibaca: ${error.message}", error)
        } finally {
            retriever.release()
        }
    }
}

class PdfViewer {
    fun info(path: String): Map<String, Any?> {
        val file = requireFile(path)
        return open(file) { renderer ->
            val first = renderer.openPage(0)
            val width = first.width
            val height = first.height
            first.close()
            mapOf("pages" to renderer.pageCount, "width" to width, "height" to height, "size" to file.length())
        }
    }

    fun renderPage(path: String, index: Int, targetWidth: Int): Map<String, Any?> {
        val file = requireFile(path)
        return open(file) { renderer ->
            if (index < 0 || index >= renderer.pageCount) {
                throw OnyxException("bad_page", "Halaman $index di luar rentang 0..${renderer.pageCount - 1}")
            }
            val page = renderer.openPage(index)
            try {
                val width = targetWidth.coerceIn(200, 2400)
                val height = (width.toFloat() * page.height / page.width).toInt().coerceAtLeast(1)
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                bitmap.eraseColor(0xFFFFFFFF.toInt())
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                mapOf("png" to compressPng(bitmap), "width" to width, "height" to height)
            } finally {
                page.close()
            }
        }
    }

    private fun <T> open(file: File, block: (PdfRenderer) -> T): T {
        val descriptor = try {
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        } catch (error: Exception) {
            throw OnyxException("denied", "PDF tidak dapat dibuka: ${error.message}", error)
        }
        val renderer = try {
            PdfRenderer(descriptor)
        } catch (error: Exception) {
            descriptor.close()
            throw OnyxException("pdf_invalid", "PDF rusak atau dilindungi kata sandi", error)
        }
        try {
            if (renderer.pageCount == 0) throw OnyxException("pdf_empty", "PDF tidak memiliki halaman")
            return block(renderer)
        } finally {
            renderer.close()
            descriptor.close()
        }
    }
}

internal fun requireFile(path: String): File {
    val file = File(path)
    if (!file.exists()) throw OnyxException("not_found", "Berkas tidak ditemukan")
    if (!file.isFile) throw OnyxException("not_file", "Bukan berkas")
    if (!file.canRead()) throw OnyxException("denied", "Tidak ada izin membaca berkas")
    return file
}

internal fun compress(bitmap: Bitmap, quality: Int): ByteArray {
    val out = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
    bitmap.recycle()
    return out.toByteArray()
}

internal fun compressPng(bitmap: Bitmap): ByteArray {
    val out = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
    bitmap.recycle()
    return out.toByteArray()
}
