# everything-panel

One glass control panel for every server provider. Easypanel first; the provider layer is built so
Coolify, Dokploy, Portainer and CapRover can follow. By PT Cipta Dua Saudara
([ciptadusa.com](https://www.ciptadusa.com)). Flutter, Android first.

- **Fleet, Services, System, Settings.** Several servers at once, live CPU / memory / disk, services
  grouped by project (foldable, pinned search), start / stop / restart / deploy, build and deploy
  activity logs.
- **Optional Google sign-in** and **end-to-end encrypted sync** of your servers through your own
  Firestore documents. Keys are derived on the device (PBKDF2-HMAC-SHA256) and entries are sealed with
  AES-256-GCM; Firebase only ever stores ciphertext. Free Spark tier, no billing.
- **Local alerts** when a watched service stops, and FCM push receiving.
- Phone (floating bar) and tablet (side rail) layouts. Liquid-glass design with spring motion.

Everything works without an account; servers and tokens then stay on the device (tokens in the
Android keystore).

## Run it

```sh
flutter pub get
flutter run            # debug build: works without any credentials, Google sign-in stays off
flutter analyze
flutter test           # screen-level end-to-end tests, no network or device needed
```

A plain checkout has no Firebase config, so Google sign-in and push show as "not configured". That is
by design: the source is open, the credentials are not.

## Credentials (not in git)

| File | What it is | Where it lives |
|---|---|---|
| `android/app/google-services.json` | Firebase config for `com.ciptadusa.everything_panel` | GitHub secret `GOOGLE_SERVICES_JSON` (base64) |
| `android/app/release.jks` + `android/key.properties` | Release signing key | GitHub secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` |
| `.env` | Image-generator endpoint and key used to make the brand art | GitHub secret `DOTENV` |

To build with your own Firebase project, put your `google-services.json` in `android/app/`, enable the
Google provider and register your signing SHA-1 / SHA-256 in that project.
`android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) enables a signed
release build; without it, release builds fall back to the debug key.

## Releases

- **Tagged release.** Push a tag and CI builds a signed APK and publishes it as a GitHub release:

  ```sh
  git tag v0.1.0 && git push origin v0.1.0
  ```

- **Nightly.** Every push to `master` replaces the rolling pre-release called `nightly` with a fresh
  signed APK (build number = CI run number, so each one installs over the last).

Both use the same reusable workflow (`.github/workflows/build-apk.yml`), which reads the credentials
from repository secrets. `ci.yml` runs `flutter analyze` and `flutter test` on every push and pull
request.

## Firebase

`firebase/firestore.rules` holds the security rules: each user can only read and write their own
`users/{uid}/...` documents, and only the fixed encrypted fields.

## Layout

```
lib/data       provider layer (PanelBackend), Easypanel backend, models
lib/state      app state, encrypted sync controller
lib/services   Google auth, push, encrypted vault
lib/screens    Fleet, Services, System, Settings, logs, add-server, welcome
lib/ui         glass material, motion, responsive helpers
test           backend, vault and screen-level tests
```

## License

MIT, see `LICENSE`.
