#!/bin/bash
build_mosey() {

 set -e
 
 FILES="out/module/wonder_mosey_wild.ko customize.sh module.prop sepolicy.rule service.sh uninstall.sh"
 FOLDERS="common META-INF payload system"
 if [ ! -z out/zip ]; then
  echo "Creating zip out folder"
  mkdir -p out/zip
 fi
  for i in $FILES; do
    if [ ! -f "$i" ]; then
      if [ "$i" == "out/module/wonder_mosey_wild.ko" ] && [ -f "system/vendor/lib/modules/wonder_mosey_wild.ko" ]; then
        mkdir -p out/module
        cp -f system/vendor/lib/modules/wonder_mosey_wild.ko out/module/wonder_mosey_wild.ko
      else
        echo "$i not found, exiting"
        exit 255
      fi
    fi
    cp -f "$i" out/zip/
  done
  for i in $FOLDERS; do
   cp $i out/zip
  done
}
zip_files() {
  set -e
  if command -v zip >/dev/null 2>&1; then
      (cd out/zip && zip -r ../../mosey-extended.zip .)
  else
      python3 -c "
import zipfile, os
out_path = 'mosey-extended.zip'
src_dir = 'out/zip'
with zipfile.ZipFile(out_path, 'w', zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk(src_dir):
        for f in files:
            fp = os.path.join(root, f)
            zf.write(fp, os.path.relpath(fp, src_dir))
print(f'Built {out_path} ({os.path.getsize(out_path)} bytes)')
"
  fi
}
# The function executes only if calling the script from terminal, in case of sourcing it from other script it doesnt execute at start
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    . wonder/build_wonder.sh
    echo "Building wonder"
    build_wonder || true
    if [ ! -f out/module/wonder_mosey_wild.ko ] && [ -f system/vendor/lib/modules/wonder_mosey_wild.ko ]; then
        mkdir -p out/module
        cp -f system/vendor/lib/modules/wonder_mosey_wild.ko out/module/wonder_mosey_wild.ko
    fi
    if [ -f out/module/wonder_mosey_wild.ko ]; then
        echo "Building mosey"
        build_mosey
        echo "Zipping files"
        zip_files
        echo "Finished building: mosey-extended.zip"
    else
        echo "Error: wonder_mosey_wild.ko missing"
        exit 1
    fi
fi
