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
  set_perm_recursive $MODPATH/system/product/etc/sysconfig 0 0 0755 0644
}

##########################################################################################
# MMT Extended Logic - Don't modify anything after this
##########################################################################################

SKIPUNZIP=1
unzip -qjo "$ZIPFILE" 'common/functions.sh' -d $TMPDIR >&2
. $TMPDIR/functions.sh
