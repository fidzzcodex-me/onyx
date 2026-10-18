# Onyx build fixes

Copy these files over your onyx tree (paths relative to repo root).

## Files

- android/app/build.gradle.kts  (eddsa dep + compileSdk 36)
- android/settings.gradle.kts   (Kotlin 2.1.10 already)
- android/app/src/main/kotlin/com/onyx/terminal/plugins/ProcessPlugin.kt
- android/app/src/main/kotlin/com/onyx/terminal/plugins/SystemPlugin.kt
- android/app/src/main/kotlin/com/onyx/terminal/sftp/FtpClient.kt
- android/app/src/main/kotlin/com/onyx/terminal/terminal/SshShellSession.kt

KeyManager.kt does not need code changes if eddsa dependency is present.

## Apply

```bash
cd onyx
unzip -o onyx-build-fixes.zip
git add -A
git commit -m "fix: kotlin compile errors for CI build"
git push
```

Then re-run the Build workflow.
