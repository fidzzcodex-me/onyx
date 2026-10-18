package com.onyx.terminal.filesystem

import android.os.FileObserver
import com.onyx.terminal.util.MainThread

class FileWatcher(private val onChange: (String) -> Unit) {
    private var observer: FileObserver? = null
    private var watched: String? = null
    private val pending = Runnable { watched?.let(onChange) }

    fun watch(path: String?) {
        stop()
        if (path == null) return
        watched = path
        val mask = FileObserver.CREATE or FileObserver.DELETE or FileObserver.MOVED_FROM or
            FileObserver.MOVED_TO or FileObserver.MODIFY or FileObserver.CLOSE_WRITE or
            FileObserver.DELETE_SELF or FileObserver.MOVE_SELF
        val created = object : FileObserver(path, mask) {
            override fun onEvent(event: Int, name: String?) {
                MainThread.cancel(pending)
                MainThread.postDelayed(250L, pending)
            }
        }
        created.startWatching()
        observer = created
    }

    fun stop() {
        MainThread.cancel(pending)
        observer?.stopWatching()
        observer = null
        watched = null
    }
}
