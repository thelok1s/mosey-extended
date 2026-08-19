build_wonder() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  OUT_DIR="$REPO_ROOT/out/module"
  MODULE_SYS_DIR="$REPO_ROOT/system/vendor/lib/modules"
  MODULE_BIN_DIR="$REPO_ROOT/system/vendor/bin"
  mkdir -p "$OUT_DIR" "$MODULE_SYS_DIR" "$MODULE_BIN_DIR"

  echo "[+] Building rename_phy binary (aarch64 static)..."
  if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
      aarch64-linux-gnu-gcc -O2 -static "$SCRIPT_DIR/rename_phy.c" -o "$MODULE_BIN_DIR/rename_phy"
      echo "[+] rename_phy built: $MODULE_BIN_DIR/rename_phy"
  else
      echo "[-] aarch64-linux-gnu-gcc not found, skipping rename_phy cross-compilation"
  fi

  echo "[+] Checking wonder_mosey_wild.ko module..."
  if [ -n "${KDIR:-}" ] && [ -d "$KDIR" ]; then
      echo "[+] Compiling kernel module against KDIR=$KDIR..."
      make -C "$KDIR" M="$SCRIPT_DIR" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules || true
      [ -f "$SCRIPT_DIR/wonder_mosey_wild.ko" ] && cp -f "$SCRIPT_DIR/wonder_mosey_wild.ko" "$OUT_DIR/wonder_mosey_wild.ko"
  fi

  if [ ! -s "$MODULE_SYS_DIR/wonder_mosey_wild.ko" ] && command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
      echo "[+] Cross-compiling wonder_mosey_wild.ko for ARM64..."
      aarch64-linux-gnu-gcc -O2 -c -fno-pic "$SCRIPT_DIR/wonder_mosey_wild.c" -o "$MODULE_SYS_DIR/wonder_mosey_wild.ko"
  fi

  if [ -f "$MODULE_SYS_DIR/wonder_mosey_wild.ko" ]; then
      cp -f "$MODULE_SYS_DIR/wonder_mosey_wild.ko" "$OUT_DIR/wonder_mosey_wild.ko"
  fi

  echo "[+] Module status: $MODULE_SYS_DIR/wonder_mosey_wild.ko ($(wc -c < "$MODULE_SYS_DIR/wonder_mosey_wild.ko" 2>/dev/null || echo 0) bytes)"
}
