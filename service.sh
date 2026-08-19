#!/system/bin/sh
# Late-boot launcher for mosey_server (KernelSU/Magisk service.d style)

MODDIR="${0%/*}"
MODULE_DIR="/data/adb/modules/${MODID:-mosey-extended}"
LOGDIR="/data/adb/mosey-extended"
LOGFILE="$LOGDIR/service.log"
RUNLOG="$LOGDIR/mosey_server.log"
PIDFILE="$LOGDIR/mosey_server.pid"

mkdir -p "$LOGDIR" 2>/dev/null
chmod 0700 "$LOGDIR" 2>/dev/null

ts() { /system/bin/date '+%Y-%m-%d %H:%M:%S%z' 2>/dev/null || echo "no-date"; }
log() { echo "$(ts) [mosey-extended] $*" >>"$LOGFILE"; }

BIN="/vendor/bin/mosey_server"
[ -x "$BIN" ] || BIN="/system/vendor/bin/mosey_server"
[ -x "$BIN" ] || BIN="$MODULE_DIR/system/vendor/bin/mosey_server"

SQLITE3="$MODULE_DIR/system/vendor/bin/sqlite3_mosey"
[ -x "$SQLITE3" ] || SQLITE3=""

DEV_CODENAME="$(getprop ro.product.device 2>/dev/null)"
DEV_MODEL="$(getprop ro.product.model 2>/dev/null)"
log "service.sh invoked (MODDIR=$MODDIR, MODULE_DIR=$MODULE_DIR, BIN=$BIN, sqlite3=${SQLITE3:-none}, device=${DEV_CODENAME:-unknown}/${DEV_MODEL:-unknown})"

# Wait for Android boot to complete (and for KSU mounts to settle)
i=0
while [ "$i" -lt 180 ]; do
  bc="$(getprop sys.boot_completed 2>/dev/null)"
  [ "$bc" = "1" ] && break
  i=$((i+1))
  [ $((i % 10)) -eq 0 ] && log "waiting for sys.boot_completed=1 (elapsed=${i}s)"
  /system/bin/sleep 1
done

log "boot_completed=$(getprop sys.boot_completed 2>/dev/null)"

# ── MoseyApp version guard ─────────────────────────────────────────────────
# Play Store auto-updates MoseyApp to v20053 (stopped=true), breaking GMS binding.
# Session-based reinstall of v16753, then pm clear to reset stopped=false.
MOSEY_APK_DIR="$MODULE_DIR/system/product/priv-app/MoseyApp"

mosey_vc="$(pm dump com.google.android.mosey 2>/dev/null | grep versionCode | head -1 | grep -oE '[0-9]+' | head -1)"
mosey_state="$(pm dump com.google.android.mosey 2>/dev/null | grep 'stopped=' | head -1)"
log "MoseyApp: versionCode=$mosey_vc state: $mosey_state"

MOSEY_INSTALLED=0
if [ "$mosey_vc" != "16753" ] || echo "$mosey_state" | grep -q "stopped=true"; then
  if [ -f "$MOSEY_APK_DIR/base.apk" ]; then
    TMPDIR="/data/local/tmp/mosey_install"
    mkdir -p "$TMPDIR" 2>/dev/null
    for f in base.apk split_config.arm64_v8a.apk split_config.xxhdpi.apk split_config.en.apk; do
      cp "$MOSEY_APK_DIR/$f" "$TMPDIR/$f" 2>>"$LOGFILE" && chmod 644 "$TMPDIR/$f" 2>/dev/null
    done

    log "reinstalling MoseyApp v16753 via session install"
    SESSION="$(pm install-create -r -d --user 0 2>&1 | grep -oE '[0-9]+')"
    if [ -z "$SESSION" ]; then
      log "ERROR: pm install-create failed"
      install_rc=1
    else
      log "session: $SESSION"
      install_rc=0
      for apk_name in base split_config.arm64_v8a split_config.xxhdpi split_config.en; do
        apk_path="$TMPDIR/${apk_name}.apk"
        apk_sz="$(wc -c < "$apk_path" 2>/dev/null)"
        out="$(pm install-write -S "$apk_sz" "$SESSION" "$apk_name" "$apk_path" 2>&1)"
        rc=$?; log "write $apk_name (rc=$rc): $out"
        [ "$rc" != "0" ] && install_rc=$rc
      done
      out="$(pm install-commit "$SESSION" 2>&1)"
      rc=$?; log "commit (rc=$rc): $out"
      [ "$rc" != "0" ] && install_rc=$rc
    fi
    rm -rf "$TMPDIR" 2>/dev/null

    if [ "$install_rc" = "0" ]; then
      MOSEY_INSTALLED=1

      # Exempt from Android 15 hibernation immediately after install-commit.
      # Android re-stops notLaunched=true apps aggressively; set standby bucket
      # to ACTIVE (10) before pm clear so the clear result sticks.
      cmd apphibernation set-inactive com.google.android.mosey false >>"$LOGFILE" 2>&1
      am set-standby-bucket com.google.android.mosey active >>"$LOGFILE" 2>&1
      log "hibernation exemption applied (pre-clear)"

      /system/bin/sleep 1
      clear_out="$(pm clear com.google.android.mosey 2>&1)"
      log "pm clear: $clear_out"

      # Re-apply after clear — pm clear resets some standby state
      cmd apphibernation set-inactive com.google.android.mosey false >>"$LOGFILE" 2>&1
      am set-standby-bucket com.google.android.mosey active >>"$LOGFILE" 2>&1
      cmd deviceidle whitelist +com.google.android.mosey >>"$LOGFILE" 2>&1
      log "hibernation exemption re-applied (post-clear)"
    else
      log "install failed — MoseyApp still v$mosey_vc"
    fi
  else
    log "ERROR: APK not found at $MOSEY_APK_DIR — MODID=${MODID} MODULE_DIR=$MODULE_DIR"
  fi
fi

mosey_final_vc="$(pm dump com.google.android.mosey 2>/dev/null | grep versionCode | head -1 | grep -oE '[0-9]+' | head -1)"
mosey_final_state="$(pm dump com.google.android.mosey 2>/dev/null | grep 'stopped=' | head -1)"
log "MoseyApp final: versionCode=$mosey_final_vc state: $mosey_final_state"

# ── Force-stop GMS FIRST, then patch Phenotype DB ─────────────────────────
# GMS holds phenotype.db open (WAL mode). Must stop GMS before sqlite3 can
# write to it. GMS auto-restarts and reads the patched DB on next launch.
phenotype_db=""
for candidate in \
  "/data/user_de/0/com.google.android.gms/databases/phenotype.db" \
  "/data/data/com.google.android.gms/databases/phenotype.db"; do
  [ -f "$candidate" ] && phenotype_db="$candidate" && break
done

log "force-stopping GMS to unlock phenotype.db for injection"
am force-stop com.google.android.gms 2>/dev/null
log "GMS stopped — waiting 3s for DB file lock release"
/system/bin/sleep 3

if [ -n "$phenotype_db" ]; then
  if [ -n "$SQLITE3" ]; then
    log "PHENOTYPE: using bundled sqlite3 at $SQLITE3"

    gms_ap_id="$("$SQLITE3" "$phenotype_db" \
      "SELECT android_package_id FROM android_packages WHERE name='com.google.android.gms';" 2>/dev/null)"
    log "PHENOTYPE GMS android_package_id: ${gms_ap_id:-not found}"

    if [ -z "$gms_ap_id" ]; then
      "$SQLITE3" "$phenotype_db" \
        "INSERT OR IGNORE INTO android_packages(name) VALUES('com.google.android.gms');" 2>/dev/null
      gms_ap_id="$("$SQLITE3" "$phenotype_db" \
        "SELECT android_package_id FROM android_packages WHERE name='com.google.android.gms';" 2>/dev/null)"
      log "PHENOTYPE: inserted GMS android_packages id=$gms_ap_id"
    fi

    if [ -n "$gms_ap_id" ]; then
      nearby_id="$("$SQLITE3" "$phenotype_db" \
        "SELECT config_package_id FROM config_packages WHERE name='com.google.android.gms.nearby';" 2>/dev/null)"
      if [ -z "$nearby_id" ]; then
        "$SQLITE3" "$phenotype_db" \
          "INSERT OR IGNORE INTO config_packages(name, android_package_id, experiment_state_id, server_token, serving_version) \
           VALUES('com.google.android.gms.nearby', $gms_ap_id, 0, '', 0);" 2>/dev/null
        nearby_id="$("$SQLITE3" "$phenotype_db" \
          "SELECT config_package_id FROM config_packages WHERE name='com.google.android.gms.nearby';" 2>/dev/null)"
        log "PHENOTYPE: created nearby config_package id=$nearby_id"
      else
        log "PHENOTYPE: nearby config_package exists id=$nearby_id"
      fi
    fi

    if [ -n "$nearby_id" ]; then
      # All known flag name candidates for enableExternalProviders.
      # DEX string "FlagSnapshot(enableExternalProviders=" confirmed in base.apk.
      # Try every plausible Phenotype key format; wrong ones are ignored by GMS.
      for flag_name in \
        "enable_external_providers" \
        "enableExternalProviders" \
        "NearbySharing__enableExternalProviders" \
        "NearbySharing__enable_external_providers" \
        "NearbySharing__enable_external_sharing_provider" \
        "NearbySharing__external_sharing_provider_enabled" \
        "NearbySharing__enable_mosey_transport" \
        "NearbySharing__enable_mosey" \
        "NearbySharing__enable_akita_mosey" \
        "MoseyTransport__enable_mosey" \
        "ExternalSharingProvider__enabled"; do
        "$SQLITE3" "$phenotype_db" \
          "INSERT OR REPLACE INTO flag_overrides(config_package_id,name,value,type) \
           VALUES($nearby_id,'$flag_name','1',0);" 2>/dev/null
      done
      injected="$("$SQLITE3" "$phenotype_db" \
        "SELECT name,value FROM flag_overrides WHERE config_package_id=$nearby_id;" 2>/dev/null)"
      log "PHENOTYPE flags injected: $injected"
      rm -f "${phenotype_db}-wal" "${phenotype_db}-shm" 2>/dev/null
    fi
  else
    PHENOTYPE_PATCH="$MODULE_DIR/system/product/etc/phenotype_patch.db"
    if [ -f "$PHENOTYPE_PATCH" ]; then
      cp "$PHENOTYPE_PATCH" "$phenotype_db" 2>/dev/null && \
        log "PHENOTYPE: pre-patched DB installed" || \
        log "PHENOTYPE: pre-patched DB write failed"
      rm -f "${phenotype_db}-wal" "${phenotype_db}-shm" 2>/dev/null
    else
      log "PHENOTYPE: no sqlite3 and no patch DB — skipping"
    fi
  fi
else
  log "PHENOTYPE: live DB not found"
fi

# GMS auto-restarts after force-stop. Wait for it to fully load the patched DB.
log "waiting 8s for GMS to restart with patched Phenotype DB"
/system/bin/sleep 8

# After GMS restarts, trigger SHARING_PROVIDER scan via PACKAGE_ADDED broadcast.
# uid detection: pm list packages -U is more reliable than pm dump grep
mosey_uid="$(pm list packages -U com.google.android.mosey 2>/dev/null | grep -oE 'uid:[0-9]+' | grep -oE '[0-9]+')"
[ -z "$mosey_uid" ] && \
  mosey_uid="$(pm dump com.google.android.mosey 2>/dev/null | grep -E 'userId=[0-9]' | grep -oE '[0-9]+' | head -1)"
log "MoseyApp uid=$mosey_uid"
am broadcast \
  -a android.intent.action.PACKAGE_ADDED \
  -d package:com.google.android.mosey \
  --ei android.intent.extra.UID "${mosey_uid:-0}" \
  --ez android.intent.extra.REPLACING false \
  2>>"$LOGFILE"
log "PACKAGE_ADDED broadcast sent"

# ── Load virtual wonder kernel module ─────────────────────────────────────
KO_PATH="/vendor/lib/modules/wonder_mosey_wild.ko"
[ -f "$KO_PATH" ] || KO_PATH="/system/vendor/lib/modules/wonder_mosey_wild.ko"
[ -f "$KO_PATH" ] || KO_PATH="$MODULE_DIR/system/vendor/lib/modules/wonder_mosey_wild.ko"

if [ -f "$KO_PATH" ]; then
  if [ ! -d /sys/module/wonder_mosey_wild ]; then
    log "loading kernel module via insmod $KO_PATH"
    ins_out="$(insmod "$KO_PATH" 2>&1)"
    rc=$?
    log "insmod rc=$rc: ${ins_out:-success}"
  else
    log "kernel module wonder_mosey_wild already loaded"
  fi

  RENAME_BIN="/vendor/bin/rename_phy"
  [ -x "$RENAME_BIN" ] || RENAME_BIN="/system/vendor/bin/rename_phy"
  [ -x "$RENAME_BIN" ] || RENAME_BIN="$MODULE_DIR/system/vendor/bin/rename_phy"
  if [ -x "$RENAME_BIN" ]; then
    phy_idx="$(cat /sys/module/wonder_mosey_wild/parameters/phy_index 2>/dev/null)"
    [ -z "$phy_idx" ] && phy_idx="0"
    log "invoking rename_phy $phy_idx wonder"
    "$RENAME_BIN" "$phy_idx" wonder >>"$LOGFILE" 2>&1
  fi
else
  log "wonder_mosey_wild.ko not found"
fi

# ── Start mosey_server ─────────────────────────────────────────────────────
if [ -f "$PIDFILE" ]; then
  oldpid="$(cat "$PIDFILE" 2>/dev/null)"
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    log "already running (pid=$oldpid), exiting"
    exit 0
  fi
fi

if [ ! -e "$BIN" ]; then
  log "ERROR: binary not found at $BIN"
  exit 1
fi

ls -lZ "$BIN" >>"$LOGFILE" 2>/dev/null

log "attempting: setprop ctl.start mosey_server"
setprop ctl.start mosey_server 2>/dev/null
/system/bin/sleep 1
svc_state="$(getprop init.svc.mosey_server 2>/dev/null)"
if [ -n "$svc_state" ]; then
  log "init.svc.mosey_server=$svc_state"
  [ "$svc_state" = "running" ] && log "init-managed service started; done" && exit 0
else
  log "init.svc.mosey_server empty — using fallback"
fi

log "fallback: launching $BIN directly (su domain)"
/system/bin/sh -c "\"$BIN\" >>\"$RUNLOG\" 2>&1 & echo \$! >\"$PIDFILE\"" 2>>"$LOGFILE"

pid="$(cat "$PIDFILE" 2>/dev/null)"
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
  log "mosey_server started (pid=$pid)"
else
  log "ERROR: failed to start mosey_server"
  [ -f "$RUNLOG" ] && tail -n 80 "$RUNLOG" >>"$LOGFILE" 2>/dev/null
  exit 1
fi

log "post-start ctx=$(cat /proc/$pid/attr/current 2>/dev/null)"
/system/bin/sleep 2

if ! kill -0 "$pid" 2>/dev/null; then
  log "process exited quickly"
  [ -f "$RUNLOG" ] && tail -n 120 "$RUNLOG" >>"$LOGFILE" 2>/dev/null
  exit 1
fi

log "mosey_server alive (pid=$pid)"

# ── Diagnostics ────────────────────────────────────────────────────────────
[ -f "/vendor/etc/vintf/manifest/manifest_mosey.xml" ] && \
  log "VINTF: manifest_mosey.xml PRESENT" || \
  log "VINTF: manifest_mosey.xml MISSING"

sp="$(pm dump com.google.android.gms 2>/dev/null | grep -E 'ExternalSharingService|SHARING_PROVIDER' | head -5)"
log "GMS ExternalSharingService: ${sp:-not found in pm dump}"

exit 0
