#!/system/bin/sh

PAYLOAD_DIR="$MODPATH/payload"
MODULE_SYSCONFIG_DIR="$MODPATH/system/product/etc/sysconfig"
SYSCONFIG_DIR="/product/etc/sysconfig"

ui_print "> Starting Sysconfig Patching"

[ ! -d "$PAYLOAD_DIR" ] && abort "[!] Failed to locate payload directory."

mkdir -p "$MODULE_SYSCONFIG_DIR" \
  || abort "[!] Failed to create directory: $MODULE_SYSCONFIG_DIR"

XML_FILES=$(ls "$PAYLOAD_DIR"/*.xml 2>/dev/null)
[ -z "$XML_FILES" ] && abort "[!] Payloads directory is empty."

for xml_file in $XML_FILES; do
  filename="$(basename "$xml_file")"
  real_file="$SYSCONFIG_DIR/$filename"

  if [ -f "$real_file" ]; then
    ui_print "  > $filename is present, skipping..."
    continue
  fi

  ui_print "  > Adding $filename..."
  cp "$xml_file" "$MODULE_SYSCONFIG_DIR/$filename" \
    || abort "[!] Failed to copy $filename"

  chmod 644 "$MODULE_SYSCONFIG_DIR/$filename"
done

if [ -d "$PAYLOAD_DIR" ] && echo "$PAYLOAD_DIR" | grep -q "^$MODPATH/"; then
  rm -rf "$PAYLOAD_DIR"
fi

ui_print "> Sysconfig patching complete. Ensure mosey apk is installed."
