# Penandatanganan rilis

1. Buat keystore:
   ```
   keytool -genkeypair -v -keystore release.keystore -alias onyx -keyalg RSA -keysize 4096 -validity 10000
   ```
2. Simpan sebagai rahasia GitHub (Settings, Secrets and variables, Actions):
   - `KEYSTORE_BASE64`: hasil `base64 -w0 release.keystore`
   - `KEYSTORE_PASSWORD`
   - `KEY_ALIAS`
   - `KEY_PASSWORD`
3. Dorong tag `v1.0.0`. `release.yml` membangun APK dan AAB lalu melampirkannya ke rilis.

Tanpa `KEYSTORE_BASE64`, alur rilis memakai kunci debug dan mencatatnya di log. Jangan mendistribusikan hasil seperti itu. Simpan keystore asli di tempat aman; kehilangannya berarti pembaruan tidak bisa dipasang di atas versi lama.
