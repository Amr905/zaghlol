# Run the backend locally and point the dev app at it

For testing the Android dev APK (backup, sync, Gold) against a backend on your Windows PC, without Google Play.

**Dev only.** The stack uses throwaway signing keys, fake Play verification and an endpoint that grants Gold with no purchase. The API refuses `Dev__FakeStores` and `Dev__KeyEnvFile` in any environment except `Development`, and the app only trusts dev keys and plain-http LAN addresses in non-release builds. Nothing here is a deployment.

## 1. Start the backend (one command)

Needs Docker Desktop (Linux containers). From the repo root, in PowerShell:

```powershell
cd backend
docker compose -f docker-compose.phone-test.yml up --build -d
```

What it does: starts Postgres 17, applies all migrations (the `migrate` job), generates throwaway signing/HMAC keys **inside a Docker volume** (`devkeys`; nothing is written into the repo and nothing is committed), then starts the API on port **8080** with fake store verification. First run builds the image (a few minutes).

Check it:

```powershell
curl http://localhost:8080/v1/health          # {"status":"ok",...}
docker compose -f docker-compose.phone-test.yml logs api --tail 20
```

Stop: `docker compose -f docker-compose.phone-test.yml down` (keeps data and keys). Start from scratch (new keys, empty DB): add `-v`; then re-copy the keys into the app build (step 3).

## 2. Let the phone reach the PC

1. Put the PC and the phone (or an emulator) on the same Wi-Fi.
2. Find the PC's LAN address: `ipconfig` and read the IPv4 address of the Wi-Fi adapter, e.g. `192.168.1.20`.
3. Allow the port through the Windows firewall (admin PowerShell, once):
   `New-NetFirewallRule -DisplayName "Zaghlol dev backend" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow -Profile Private`
   (Set the Wi-Fi network to the Private profile, or drop `-Profile Private`.)
4. From the phone's browser open `http://192.168.1.20:8080/v1/health`. If that fails, it is the firewall, a guest/isolated Wi-Fi network, or a VPN on the PC.

Android emulator on the same PC: use `http://10.0.2.2:8080` instead (no firewall step). iOS simulator: `http://127.0.0.1:8080`.

The app accepts plain `http` only for loopback/emulator hosts and, in non-release builds, private IPv4 literals (`10.x.x.x`, `172.16-31.x.x`, `192.168.x.x`). A host name or a public address is refused. Release builds accept `https` only. (Flutter's `dart:io` client is not subject to Android's cleartext policy, so no manifest change is needed.)

## 3. Build and run the dev app

The app reads two dart-defines, in debug/profile builds only:

- `ZAGHLOL_API_BASE`: the backend address (default `https://api.zaghlol.app`).
- `ZAGHLOL_DEV_KEYS`: the local backend's public signing keys (`kid:x:y,kid:x:y`), so the app can verify the responses. The backend prints the exact string:

```powershell
curl http://localhost:8080/dev/v1/app-keys
```

Then, from `app/`:

```powershell
flutter build apk --debug --flavor devNoSms `
  --dart-define=ZAGHLOL_API_BASE=http://192.168.1.20:8080 `
  --dart-define=ZAGHLOL_DEV_KEYS=<paste the line from /dev/v1/app-keys>
adb install -r build\app\outputs\flutter-apk\app-devNoSms-debug.apk
```

(or `flutter run --flavor devNoSms` with the same defines). A release build ignores `ZAGHLOL_DEV_KEYS` and refuses a plain-http base.

## 4. Test Gold without Play

Open the app once so it registers an install, then grant Gold from the PC:

```powershell
curl -X POST http://localhost:8080/dev/v1/grant-gold                       # yearly, newest install
curl -X POST http://localhost:8080/dev/v1/grant-gold -H "Content-Type: application/json" -d '{"plan":"lifetime"}'
curl -X POST http://localhost:8080/dev/v1/grant-gold -H "Content-Type: application/json" -d '{"plan":"monthly","installId":"<uuid>"}'
```

Plans: `monthly`, `yearly` (default), `lifetime`. The response is `{"installId":...,"plan":...,"status":"active","entitlementIssued":true,"devOnly":true}`. The call runs the real verification, seat and entitlement code against a fake Play answer, so the app's next entitlement fetch (reopen the app; if Gold still shows locked, use the app's restore/refresh action) returns a dev-signed token and Gold unlocks. Real Play tokens are rejected in this mode (fake store only).

## Troubleshooting

| Symptom | Cause |
|---|---|
| App says it cannot reach the server | firewall, wrong Wi-Fi, wrong IP, or `ZAGHLOL_API_BASE` missing the `http://` and port |
| Responses rejected / Gold never unlocks | `ZAGHLOL_DEV_KEYS` is stale (you ran `down -v`) or was not set: re-run `curl .../dev/v1/app-keys` and rebuild |
| `grant-gold` returns 404 "no install" | open the app once with the dev backend configured, then retry |
| api container exits at start | `docker compose -f docker-compose.phone-test.yml logs api` (the startup checks name the setting, never a value) |
