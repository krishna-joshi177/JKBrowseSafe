# SafeBrowse – a Flutter browser for Windows and Android

## Build with GitHub (no local setup needed)
1. Push this folder to the `main` branch of a GitHub repository.
2. Open the repository's **Actions** tab and wait for the **Build SafeBrowse** workflow to finish.
   You can also start it by hand: Actions > Build SafeBrowse > Run workflow.
3. Open the finished run. Under **Artifacts**, download:
   - `SafeBrowse-Android-APK`: unzip it and install `app-release.apk` on your phone.
   - `SafeBrowse-Windows`: unzip it and run `safe_browser.exe`. Keep all the files in the same folder.

The APK uses Flutter's debug signing key. That's fine for testing, but you need your own signing key before publishing to the Play Store.

## Build on your own computer
    flutter create --platforms=windows,android .
    flutter pub get
    flutter run -d windows
    flutter build apk --release
