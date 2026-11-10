# Releasing Inventra

## 1. App name and IDs

- **Android name**: `android/app/src/main/AndroidManifest.xml` → `android:label="Inventra"`.
- **iOS name**: `ios/Runner/Info.plist` → `CFBundleDisplayName` = `Inventra`.
- **IDs**: `flutter create --org com.inventra` gives `com.inventra.inventra`. Change it before the first upload if you want something else; it can't change afterwards.
- **Version**: `version:` in `pubspec.yaml` (`1.0.0+6` = name `1.0.0`, build `6`). Raise the build number for every upload.

## 2. Android

1. Add the internet permission above `<application` in `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   ```
2. Create an upload key once and keep it safe (losing it means you can't update the app):
   ```bash
   keytool -genkey -v -keystore ~/inventra-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
3. Create `android/key.properties` (never commit it):
   ```properties
   storePassword=...
   keyPassword=...
   keyAlias=upload
   storeFile=/home/you/inventra-upload.jks
   ```
4. In `android/app/build.gradle.kts`, load it and use it for release:
   ```kotlin
   import java.util.Properties
   import java.io.FileInputStream

   val keystoreProperties = Properties().apply {
       val f = rootProject.file("key.properties")
       if (f.exists()) load(FileInputStream(f))
   }

   android {
       signingConfigs {
           create("release") {
               keyAlias = keystoreProperties["keyAlias"] as String
               keyPassword = keystoreProperties["keyPassword"] as String
               storeFile = file(keystoreProperties["storeFile"] as String)
               storePassword = keystoreProperties["storePassword"] as String
           }
       }
       buildTypes {
           release { signingConfig = signingConfigs.getByName("release") }
       }
   }
   ```
5. Build and upload `build/app/outputs/bundle/release/app-release.aab` to Google Play Console:
   ```bash
   flutter build appbundle --release
   ```

## 3. iOS

1. Needs a Mac with Xcode and an Apple Developer account.
2. `ios/Runner/Info.plist`: camera and photo-library usage texts (see SETUP.md). `ios/Podfile`: `platform :ios, '15.5'`.
3. Open `ios/Runner.xcworkspace` → Runner → Signing & Capabilities → choose your team.
4. Build and upload with Xcode Organizer or Transporter:
   ```bash
   flutter build ipa --release
   ```

## 4. Before launch

- [ ] Supabase → Authentication → Email: turn **Confirm email** back on, and set the Site URL / email templates.
- [ ] Supabase: enable leaked-password protection and set a minimum password length.
- [ ] PowerSync: sync rules deployed, instance on a plan that fits your number of users.
- [ ] Check `lib/core/config.dart` points at the production Supabase project and PowerSync instance.
- [ ] Privacy policy URL (both stores require one; the app uses the camera, photos and an email account).
- [ ] Store listing: screenshots, short and full description, icon (`assets/branding/app_icon.png`, 1024×1024).
- [ ] Test on a low-end Android phone with airplane mode on: sell, restock, then reconnect and confirm sync.
- [ ] `flutter test` passes.
