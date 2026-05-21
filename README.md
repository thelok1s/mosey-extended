# mosey-extended

KernelSU / Magisk module that enables Google's **mosey AirDrop-style Quick Share transport** on Pixel 8 Pro (husky) and other non-Pixel-10 devices.

On Pixel 10 (blazer), GMS Nearby binds `ExternalSharingService` inside `MoseyApp`, which calls `IMoseyService.start()` on `mosey_server`. Neither binding nor start happens on older hardware by default — this module works around every known blocker.

---

## What It Does

| Step | Action |
|---|---|
| MoseyApp install | Session-API reinstall of MoseyApp v16753 (reverts Play Store auto-update to v20053 which breaks binding) |
| Hibernation exemption | `cmd apphibernation set-inactive` + `am set-standby-bucket active` before and after `pm clear` to survive Android 15 aggressive re-stop |
| Phenotype injection | Stops GMS → patches `phenotype.db` live with `sqlite3_mosey` (static aarch64 binary) to insert `com.google.android.gms.nearby` config_package with 10 flag override candidates for `enableExternalProviders` |
| Pre-patched DB fallback | `phenotype_patch.db` bundled as fallback if live sqlite3 injection fails |
| PACKAGE_ADDED broadcast | Triggers GMS Nearby `SHARING_PROVIDER` scan after Phenotype update |
| mosey_server start | `setprop ctl.start mosey_server` → fallback direct exec |
| SELinux | Full domain transition rules, all required socket classes, binder for GMS/MoseyApp/appdomain |

---

## Module Contents

```
service.sh                              Boot launcher — all logic lives here
sepolicy.rule                           SELinux type declarations + allow rules
customize.sh                            KSU/Magisk install-time permissions
module.prop                             Module metadata
system/
  vendor/
    bin/
      mosey_server                      mosey daemon (Rust, AIDL NDK, aarch64)
      sqlite3_mosey                     Static sqlite3 3.51.1 for live DB patching
    lib64/
      libmosey_daemon_ffi.so            Companion shared library
    etc/
      init/mosey.rc                     Init service descriptor
      vintf/manifest/manifest_mosey.xml VINTF HAL declaration (com.google.pixel.moseyservice v2)
      selinux/vendor_service_contexts   Service context: IMoseyService/default → mosey_service
  product/
    priv-app/MoseyApp/                  MoseyApp v16753 split APKs (base + arm64 + xxhdpi + en)
    etc/
      phenotype_patch.db                Pre-patched Phenotype DB fallback
      permissions/privapp-permissions-mosey.xml
      default-permissions/default-permissions-com.google.android.mosey.xml
      sysconfig/mosey-hiddenapi.xml     Hidden API whitelist + force-queryable-apps
```

---

## Requirements

- KernelSU (Wild KSU / KernelSU-Next) or Magisk
- Android 12+ (tested on Android 15 / Pixel 8 Pro)
- Root access

---

## Installation

1. Flash `mosey-extended.zip` via KSU Manager or Magisk
2. Reboot
3. Check logs at `/data/adb/mosey-extended/service.log`

---

## Known Blockers (as of v3.0)

### `stopped=true` re-applies ~6 seconds after `pm clear`
Android 15 `AppHibernationController` aggressively re-stops apps with `notLaunched=true` after data-clear. Module applies hibernation exemption before and after `pm clear` — partially mitigates this. If it still re-stops, try:
```sh
am startservice --include-stopped-packages -n com.google.android.mosey/.ExternalSharingService
```

### GMS never binds `ExternalSharingService`
GMS has 28 string hits for mosey/ExternalSharing in its DEX but uses `DisabledExternalSharingProvider` stub. The switch is controlled by a Phenotype flag (`FlagSnapshot(enableExternalProviders=...)`). The module injects 10 candidate flag names — exact key unknown until Binary Ninja analysis of GMS `base.apk`.

### `com.google.android.gms.nearby` config_package absent on husky
`phenotype_live.db` from device shows only 7 packages — `com.google.android.gms.nearby` never registered. GMS may have a pre-Phenotype device gate that skips registration on non-Pixel-10 hardware. Module inserts the config_package manually via sqlite3.

---

## Debugging

```sh
# Full service log
adb shell su -c "cat /data/adb/mosey-extended/service.log"

# MoseyApp state
adb shell pm dump com.google.android.mosey | grep -E "versionCode|stopped|notLaunched"

# GMS ExternalSharingService
adb shell pm dump com.google.android.gms | grep ExternalSharingService

# mosey_server process
adb shell ps -A | grep mosey

# Phenotype DB flags
adb shell su -c "sqlite3 /data/user_de/0/com.google.android.gms/databases/phenotype.db \
  'SELECT cp.name, fo.name, fo.value FROM flag_overrides fo \
   JOIN config_packages cp ON fo.config_package_id=cp.config_package_id \
   WHERE cp.name LIKE \"%nearby%\";'"
```

---

## Changelog

### v3.0 (2026-05-21)
- **Phenotype DB injection**: stops GMS, patches live `phenotype.db` via bundled `sqlite3_mosey` with 10 flag override candidates for `enableExternalProviders`
- **Pre-patched DB fallback**: `phenotype_patch.db` bundled for when live injection fails
- **MoseyApp session install**: reverts Play Store v20053 → v16753 via Android 12+ session API
- **Android 15 hibernation exemption**: `cmd apphibernation set-inactive` + standby bucket before/after `pm clear`
- **Wild KSU path fix**: `MODULE_DIR` now correctly set to `/data/adb/modules/${MODID}` instead of `MODDIR`
- **UID detection fix**: `pm list packages -U` instead of fragile `pm dump` grep
- **PACKAGE_ADDED broadcast**: triggers GMS Nearby `SHARING_PROVIDER` rescan after Phenotype update
- **Massively expanded SELinux**: full domain transition, all socket classes (packet, netlink, TUN), binder for appdomain/GMS/MoseyApp
- **New permissions**: privapp-permissions, default-permissions, force-queryable-apps, hidden-api whitelist
- **VINTF manifest**: HAL declaration for `com.google.pixel.moseyservice` v2
- **vendor_service_contexts**: `IMoseyService/default → u:object_r:mosey_service:s0`
- **libmosey_daemon_ffi.so**: companion library bundled

### v2.2
- Updated to latest mosey_server binary
- Minor service.sh fixes

### v2.0
- Initial MoseyApp inclusion
- Basic sepolicy

### v1.0
- Initial release: mosey_server + mosey.rc
