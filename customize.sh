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

  # Late-boot launcher (KernelSU/Magisk service.d style)
  # Note: service.sh runs from /data/adb/... so we mainly need it executable.
  # File context will be determined by its location under /data/adb.
  set_perm $MODPATH/service.sh 0 0 0755
}

##########################################################################################
# MMT Extended Logic - Don't modify anything after this
##########################################################################################

SKIPUNZIP=1
unzip -qjo "$ZIPFILE" 'common/functions.sh' -d $TMPDIR >&2
. $TMPDIR/functions.sh
