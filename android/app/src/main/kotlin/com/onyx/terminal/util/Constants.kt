package com.onyx.terminal.util

object Channels {
    const val AUTH = "com.onyx.terminal/auth"
    const val TERMINAL = "com.onyx.terminal/terminal"
    const val TERMINAL_STREAM = "com.onyx.terminal/terminal_stream"
    const val FS = "com.onyx.terminal/fs"
    const val FS_EVENTS = "com.onyx.terminal/fs_events"
    const val WINDOW = "com.onyx.terminal/window"
    const val EDITOR = "com.onyx.terminal/editor"
    const val VIEWER = "com.onyx.terminal/viewer"
    const val SFTP = "com.onyx.terminal/sftp"
    const val SFTP_STREAM = "com.onyx.terminal/sftp_stream"
    const val SYSTEM = "com.onyx.terminal/system"
    const val SYSTEM_STREAM = "com.onyx.terminal/system_stream"
    const val PROCESS = "com.onyx.terminal/process"
    const val PROCESS_STREAM = "com.onyx.terminal/process_stream"
}

object Notif {
    const val CHANNEL_TERMINAL = "onyx_terminal"
    const val CHANNEL_TRANSFER = "onyx_transfer"
    const val CHANNEL_ALERT = "onyx_alert"
    const val ID_TERMINAL = 1001
    const val ID_TRANSFER = 1002
    const val ID_ALERT_BASE = 2000
    const val ACTION_STOP_ALL = "com.onyx.terminal.action.STOP_ALL_SESSIONS"
    const val ACTION_CANCEL_TRANSFERS = "com.onyx.terminal.action.CANCEL_TRANSFERS"
}

object Prefs {
    const val SECURE = "onyx_secure"
    const val NATIVE = "onyx_native"
}

object Limits {
    const val SCROLLBACK_BYTES = 262144
    const val MAX_EDITABLE_BYTES = 10L * 1024L * 1024L
    const val MAX_PREVIEW_BYTES = 1024L * 1024L
    const val MAX_SEARCH_RESULTS = 1000
    const val MAX_SESSION_AGE_PERSIST_MS = 90L * 24L * 60L * 60L * 1000L
    const val MAX_SESSION_AGE_EPHEMERAL_MS = 24L * 60L * 60L * 1000L
    const val PIN_MIN = 4
    const val PIN_MAX = 6
    const val PASSWORD_MIN = 8
    const val OUTPUT_BATCH_MS = 12L
    const val OUTPUT_BATCH_MAX = 65536
}
