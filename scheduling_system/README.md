# scheduling_system

A new Flutter project.

## Testing saved settings in Chrome

Profile and company settings are saved locally with `shared_preferences`.
On the web this uses browser local storage, which belongs to a particular
browser profile and origin (scheme, hostname, and port). These details are
not currently saved to the backend account.

`web_dev_config.yaml` fixes the development address at `http://localhost:7357`
for Flutter versions that support that file (including this project's SDK).
The Android Studio `main.dart` run configuration also sets the same address.
To check or recreate that configuration, open
**Run → Edit Configurations → main.dart** and use these additional run arguments:

```text
--dart-define-from-file=config/render.json --web-hostname=localhost --web-port=7357
```

Select Chrome and run the app. The equivalent terminal command is:

```sh
flutter run -d chrome --dart-define-from-file=config/render.json --web-hostname=localhost --web-port=7357
```

The fixed port prevents the browser address from changing, but Flutter also
uses a temporary Chrome debugging profile. Its attempt to cache that profile
under `.dart_tool/chrome-device` did not reliably preserve local storage in
the Windows restart check. A fixed port alone does not address a discarded
browser profile.

For repeatable persistence testing, run the following from Android Studio's
Terminal in the `scheduling_system` directory:

```sh
flutter run -d web-server --dart-define-from-file=config/render.json --web-hostname=localhost --web-port=7357
```

Open `http://localhost:7357` manually in your normal Chrome window (not an
Incognito window). Save the administrator's full name in
**Settings → Profile Settings** and wait for the success message. Stop the
server with `q`, run the same command again, and refresh the same browser tab.
This keeps the browser profile independent of the Flutter process.

A name saved at a previous random port or in Flutter's temporary profile will
not appear in this browser profile, so save it once at the new address.
Clearing browser data or switching browser profiles will still remove or
separate these local settings; they do not sync between devices or accounts.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
