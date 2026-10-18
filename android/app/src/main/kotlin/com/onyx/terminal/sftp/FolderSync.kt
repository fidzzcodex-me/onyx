package com.onyx.terminal.sftp

import java.io.File

class FolderSync(private val manager: ConnectionManager, private val queue: TransferQueue) {
    private data class Meta(val size: Long, val modified: Long)

    fun compare(sessionId: String, localDir: File, remoteDir: String): List<Map<String, Any?>> {
        val fs = manager.fs(sessionId)
        val local = LinkedHashMap<String, Meta>()
        val remote = LinkedHashMap<String, Meta>()
        scanLocal(localDir, localDir, local)
        scanRemote(fs, remoteDir, remoteDir, remote)
        val keys = (local.keys + remote.keys).toSortedSet()
        val out = ArrayList<Map<String, Any?>>()
        for (key in keys) {
            val l = local[key]
            val r = remote[key]
            val status = when {
                l != null && r == null -> "only_local"
                l == null && r != null -> "only_remote"
                l != null && r != null -> when {
                    Math.abs(l.modified - r.modified) <= 2000 && l.size == r.size -> "same"
                    l.modified > r.modified + 2000 -> "newer_local"
                    r.modified > l.modified + 2000 -> "newer_remote"
                    else -> "size_diff"
                }
                else -> "same"
            }
            out.add(
                mapOf(
                    "path" to key,
                    "status" to status,
                    "localSize" to (l?.size ?: -1L),
                    "remoteSize" to (r?.size ?: -1L),
                    "localModified" to (l?.modified ?: 0L),
                    "remoteModified" to (r?.modified ?: 0L)
                )
            )
        }
        return out
    }

    fun sync(sessionId: String, localDir: File, remoteDir: String, mode: String): Int {
        val diff = compare(sessionId, localDir, remoteDir)
        var count = 0
        for (item in diff) {
            val status = item["status"] as String
            val relative = item["path"] as String
            val localFile = File(localDir, relative)
            val remotePath = RemotePath.join(remoteDir, relative)
            val up = (mode == "up" || mode == "two") && (status == "only_local" || status == "newer_local")
            val down = (mode == "down" || mode == "two") && (status == "only_remote" || status == "newer_remote")
            if (up) {
                queue.enqueueUpload(sessionId, localFile, remotePath)
                count++
            } else if (down) {
                val size = (item["remoteSize"] as? Long) ?: 0L
                queue.enqueueDownload(sessionId, remotePath, localFile, size)
                count++
            }
        }
        return count
    }

    private fun scanLocal(root: File, dir: File, out: MutableMap<String, Meta>) {
        val children = dir.listFiles() ?: return
        for (child in children) {
            if (child.isDirectory) {
                scanLocal(root, child, out)
            } else if (child.isFile) {
                val relative = child.relativeTo(root).path.replace(File.separatorChar, '/')
                out[relative] = Meta(child.length(), child.lastModified())
            }
        }
    }

    private fun scanRemote(fs: RemoteFs, root: String, dir: String, out: MutableMap<String, Meta>) {
        for (entry in fs.list(dir)) {
            if (entry.isDir) {
                scanRemote(fs, root, entry.path, out)
            } else {
                val relative = entry.path.removePrefix(root).trimStart('/')
                out[relative] = Meta(entry.size, entry.modified)
            }
        }
    }
}
