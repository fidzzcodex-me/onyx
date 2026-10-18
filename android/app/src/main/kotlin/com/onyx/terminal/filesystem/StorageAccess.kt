package com.onyx.terminal.filesystem

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import androidx.core.content.ContextCompat
import java.io.File

class StorageAccess(private val context: Context) {
    fun hasAllFilesAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                context, android.Manifest.permission.READ_EXTERNAL_STORAGE
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        }
    }

    fun openAllFilesSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:${context.packageName}"))
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
            fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(fallback)
        }
    }

    fun roots(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val seen = HashSet<String>()
        fun add(id: String, title: String, kind: String, file: File?) {
            if (file == null || !file.exists()) return
            val canonical = try {
                file.canonicalPath
            } catch (_: Exception) {
                file.absolutePath
            }
            if (!seen.add(canonical)) return
            out.add(
                mapOf(
                    "id" to id,
                    "title" to title,
                    "kind" to kind,
                    "path" to file.absolutePath,
                    "total" to totalSpace(file),
                    "free" to freeSpace(file),
                    "readable" to file.canRead()
                )
            )
        }
        add("home", "Beranda Onyx", "home", File(context.filesDir, "home"))
        add("internal", "Penyimpanan internal", "internal", Environment.getExternalStorageDirectory())
        val externals = context.getExternalFilesDirs(null)
        for ((index, dir) in externals.withIndex()) {
            if (dir == null || index == 0) continue
            val marker = dir.absolutePath.indexOf("/Android/")
            val root = if (marker > 0) File(dir.absolutePath.substring(0, marker)) else dir
            add("sd$index", "Kartu SD $index", "sd", if (root.canRead()) root else dir)
        }
        add("downloads", "Unduhan", "folder", Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS))
        add("dcim", "Kamera", "folder", Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM))
        add("documents", "Dokumen", "folder", Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS))
        add("app_files", "Data aplikasi", "app", context.filesDir)
        add("app_external", "Data aplikasi (eksternal)", "app", context.getExternalFilesDir(null))
        add("cache", "Cache aplikasi", "app", context.cacheDir)
        add("system", "Root sistem", "system", File("/"))
        return out
    }

    private fun totalSpace(file: File): Long = try {
        StatFs(file.absolutePath).totalBytes
    } catch (_: Exception) {
        0L
    }

    private fun freeSpace(file: File): Long = try {
        StatFs(file.absolutePath).availableBytes
    } catch (_: Exception) {
        0L
    }

    fun usage(path: String): Map<String, Any?> {
        val file = File(path)
        return mapOf("total" to totalSpace(file), "free" to freeSpace(file))
    }
}
