##########################################################################################
#
# MMT Extended Config Script
#
##########################################################################################

##########################################################################################
# Replace list
##########################################################################################

# List all directories you want to directly replace in the system
# We are strictly ADD-ONLY, so this must remain empty to avoid deleting existing files.
REPLACE="
"

##########################################################################################
# Permissions
##########################################################################################

set_permissions() {
  # Mosey native service binary + init rc (vendor)
  # /vendor/bin/mosey_server
  set_perm $MODPATH/system/vendor/bin/mosey_server 0 0 0755 u:object_r:mosey_server_exec:s0

  # /vendor/etc/init/mosey.rc
  set_perm $MODPATH/system/vendor/etc/init/mosey.rc 0 0 0644 u:object_r:vendor_configs_file:s0

  # /vendor/lib/modules/wonder_mosey_wild.ko
  [ -f "$MODPATH/system/vendor/lib/modules/wonder_mosey_wild.ko" ] && set_perm "$MODPATH/system/vendor/lib/modules/wonder_mosey_wild.ko" 0 0 0644 u:object_r:vendor_file:s0

  # Late-boot launcher (KernelSU/Magisk service.d style)
  # Note: service.sh runs from /data/adb/... so we mainly need it executable.
  # File context will be determined by its location under /data/adb.
  set_perm $MODPATH/service.sh 0 0 0755

  # Pixel 8a (akita) target check
  if device_check -d "akita" || [ "$(getprop ro.product.device 2>/dev/null)" = "akita" ]; then
    ui_print "  > Pixel 8a (akita) target detected"
  fi
}

check_kmod_compat() {
  local kver="$(uname -r 2>/dev/null)"
  local ko_file="$MODPATH/system/vendor/lib/modules/wonder_mosey_wild.ko"

  [ -f "$ko_file" ] || return 0

  ui_print "- Checking kernel module compatibility ($kver)"

  local compat=true
  if [ -n "$kver" ]; then
    case "$kver" in
      6.1.*|5.15.*|5.10.*)
        ui_print "  > Kernel $kver compatible with GKI virtual phy module"
        ;;
      *)
        compat=false
        ;;
    esac
  fi

  if ! $compat; then
    ui_print "  [!] WARNING: wonder_mosey_wild.ko is not compatible with kernel $kver!"
    ui_print "  [!] Removing kernel module. Mosey AirDrop transport may not function without virtual phy."
    rm -f "$ko_file" 2>/dev/null
  fi
}

check_kmod_compat

##########################################################################################
# MMT Extended Logic - Don't modify anything after this
##########################################################################################

SKIPUNZIP=1
unzip -qjo "$ZIPFILE" 'common/functions.sh' -d $TMPDIR >&2
. $TMPDIR/functions.sh
