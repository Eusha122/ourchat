# Android in-app updates

The app checks `GET /app-version` once on every Android launch. It shows an
update dialog only when the server's `versionCode` is greater than the APK's
Flutter build number (`version` after `+` in `pubspec.yaml`).

## Publish a release

1. Increase the app build number, for example `version: 1.0.1+2`.
2. Build the APK using the live VPS API URL:

   ```powershell
   F:\flutter\bin\flutter.bat build apk --release --dart-define=API_BASE_URL=https://api.your-domain.example
   ```

3. Upload `build\app\outputs\flutter-apk\app-release.apk` to a stable HTTPS
   URL such as `https://api.your-domain.example/downloads/ourchat.apk`.
4. On the VPS, set these backend environment variables and restart the backend:

   ```env
   APP_VERSION_CODE=2
   APP_DOWNLOAD_URL="https://api.your-domain.example/downloads/ourchat.apk"
   APP_RELEASE_NOTES="What's new in this release."
   ```

Android opens the download in the system browser and asks the user to approve
the installation. The replacement APK must use the same application ID and
signing key as the installed version.
