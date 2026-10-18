Ganti file ini di repo onyx:

android/app/src/main/kotlin/com/onyx/terminal/terminal/SshShellSession.kt

Perubahan: shell SSH interaktif di SSHJ tidak punya exitStatus
(hanya ada di Session.Command). Exit normal = 0, error = 255.
