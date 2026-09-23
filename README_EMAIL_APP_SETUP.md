# Email App — Setup Guide

A Gmail-like email client built in Flutter (Android Studio), using
`liquid_glass_widgets` for UI, `skeletonizer` for loading states, a PHP/MySQL
backend hosted on Hostinger, and PHP `mail()` for actual email delivery.
Deployed to iOS via Codemagic (no Mac required).

## 1. What's in this folder

```
lib/                    Flutter app source
  main.dart             App entry point (no material.dart used)
  config.dart           <-- SET YOUR BACKEND URL HERE
  models/                EmailMessage, AppUser
  services/              api_service.dart (all HTTP calls), session_store.dart
  screens/               auth, inbox, compose, email detail
  theme/glass_setup.dart Liquid Glass engine init

backend/                PHP backend to upload to Hostinger
  config/db.php         <-- SET YOUR DATABASE CREDENTIALS HERE
  config/helpers.php    Shared JSON/auth helpers
  api/*.php             register, login, logout, inbox, view, send, delete
  schema.sql            Import this into your Hostinger MySQL database

codemagic.yaml          CI/CD config to build an unsigned iOS app without a Mac (AltStore signs it)
pubspec.yaml            Flutter dependencies (already updated)
```

## 2. Backend setup (Hostinger)

1. In hPanel, go to **Databases > MySQL Databases** and create a database +
   user. Note the database name, username, password (host is almost always
   `localhost`).
2. Open **phpMyAdmin** for that database and run the contents of
   `backend/schema.sql` to create the `users` and `emails` tables.
3. Edit `backend/config/db.php` and fill in `DB_NAME`, `DB_USER`, `DB_PASS`
   with the values from step 1.
4. Upload the whole `backend/` folder to your Hostinger `public_html/`
   (e.g. via File Manager or FTP), so it's reachable at
   `https://yourdomain.com/backend/api/...`.
5. **Important for `mail()` to actually deliver:** Hostinger shared hosting
   generally requires the "From" address to be a real mailbox on your
   domain (set up in hPanel > Emails) for `mail()` to work reliably and
   avoid being marked as spam. Update `APP_MAIL_DOMAIN` in `db.php` and
   consider creating a no-reply@yourdomain.com mailbox.
6. Test each endpoint with a tool like Postman before wiring up the app:
   - `POST /api/register.php` — `{full_name, email, password}`
   - `POST /api/login.php` — `{email, password}`
   - `GET  /api/inbox.php?folder=inbox` (or `sent`) — needs `Authorization: Bearer <token>`
   - `GET  /api/view.php?id=1` — needs auth header
   - `POST /api/send.php` — `{recipient_email, subject, body}` — needs auth header
   - `POST /api/delete.php` — `{id}` — needs auth header

## 3. Point the Flutter app at your backend

Edit `lib/config.dart`:

```dart
const String kApiBaseUrl = 'https://yourdomain.com/backend/api';
```

## 4. Run `flutter pub get`

In Android Studio (or a terminal in the project folder), run:

```
flutter pub get
```

This pulls in `http`, `liquid_glass_widgets`, `skeletonizer`,
`shared_preferences`, and `intl`.

### ⚠️ Important note on `liquid_glass_widgets`

This package is still in active pre-1.0 development (current version
`0.2.x`/`0.3.0-dev`). The widget names and constructors used in this app
(`GlassPage`, `GlassCard`, `GlassButton`, `GlassIconButton`, `GlassTextField`,
`GlassPasswordField`, `GlassTextArea`, `GlassListTile`, `GlassTabBar.bottom`,
`GlassTab`, `LiquidGlassWidgets.initialize()`, `LiquidGlassWidgets.wrap()`)
were confirmed against the package's published documentation, but **because
it's a fast-moving dev package, do a `flutter pub get` and let Android
Studio's analyzer flag anything that's since changed** — a pre-1.0 package
can rename or restructure its API between versions. If any widget name has
changed, the fix is usually a 1-for-1 rename; the app's structure and logic
stay the same.

If you'd rather not depend on a dev-tagged package for a graded thesis
deliverable, an alternative is pinning the exact version you tested against
in `pubspec.yaml` (e.g. `liquid_glass_widgets: 0.2.1-dev.8` instead of `^`),
so nothing shifts under you later.

This app does **not** import `material.dart` anywhere — it's built on
`flutter/widgets.dart` + `flutter/cupertino.dart` (for icons only) +
`liquid_glass_widgets`. Swipe-to-delete and pull styling were hand-built
since `Dismissible`/`RefreshIndicator`/`CircleAvatar` are Material widgets.

## 5. Run on Android (works immediately, no extra setup)

```
flutter run
```

## 6. Deploy to iOS without a Mac (Codemagic + AltStore)

Since you're using a **free Apple Developer account** (not the paid $99/yr
Program) and already have **AltStore** installed, the simplest and most
reliable path skips code signing in Codemagic entirely and lets AltStore
handle it, which is exactly what it's designed for.

**Why:** a free Apple ID can't use TestFlight, App Store Connect, or
Codemagic's automatic signing integrations (those require a paid Program
membership). AltStore's whole purpose is to re-sign an app with your free
Apple ID and install it via AltServer running on your PC — so having
Codemagic also try to sign the build would be redundant and just adds more
ways for bundle-ID/profile mismatches to break the build.

**Steps:**

1. Push this project to a **Git repository** (GitHub/GitLab/Bitbucket) —
   Codemagic builds from a repo, not a local folder.
2. Create a free account at https://codemagic.io and connect your repo.
3. Codemagic auto-detects `codemagic.yaml` in the repo root. The
   `ios-workflow` in it runs `flutter build ios --release --no-codesign`,
   then zips the unsigned `Runner.app` into `EmailApp-unsigned.ipa` — no
   certificates, provisioning profiles, or Apple Developer Program needed
   for this step at all.
4. Trigger a build (push to `main`, or "Start new build" for
   `ios-workflow`). Codemagic compiles it on their cloud Mac infrastructure
   — your Windows machine is never involved.
5. Download `EmailApp-unsigned.ipa` from the build's artifacts.
6. Open **AltServer** on your PC (make sure your iPhone is connected via
   USB or on the same Wi-Fi network with AltServer's Wi-Fi sync enabled),
   then in **AltStore** on your iPhone: go to **My Apps > + (top left)**,
   pick the downloaded `.ipa`. AltStore signs it on the fly with your free
   Apple ID and installs it.
7. Remember: apps signed this way via a free Apple ID **expire after 7
   days** — AltStore will auto-refresh the signature in the background as
   long as AltServer on your PC is reachable (same Wi-Fi) periodically, or
   you can manually refresh from the AltStore app.

The `android-workflow` in the same file builds a plain `.apk` in the cloud
too, in case you want a CI-built Android artifact alongside it.

## 7. Feature checklist against your requirements

| # | Requirement | Where it's implemented |
|---|---|---|
| 1 | HTTP services for all | `lib/services/api_service.dart` — every backend call uses `package:http` |
| 2 | Skeletonizer + ListView.generate | `lib/screens/inbox_screen.dart` — `_placeholderEmails` via `List.generate`, wrapped in `Skeletonizer` |
| 3 | Hostinger backend | `backend/` folder, PHP + MySQL |
| 4 | iOS deployment | `codemagic.yaml`, see section 6 |
| 5 | liquid_glass_widgets as main UI (no material.dart) | All screens under `lib/screens/`, `lib/main.dart` |
| 6 | CRUD | Create = send.php/ComposeScreen, Read = inbox.php+view.php/InboxScreen+EmailDetailScreen, Delete = delete.php |
| 7 | PHP mail() | `backend/api/send.php` |
| 8 | Receive/send/delete | InboxScreen (receive/view), ComposeScreen (send), swipe or detail-view delete |
