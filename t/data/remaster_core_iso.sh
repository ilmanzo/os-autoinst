#!/bin/bash
set -e

VANILLA_ISO=$1
OUTPUT_ISO=$2

if [[ -z $VANILLA_ISO || -z $OUTPUT_ISO ]]; then
    echo "Usage: $0 <vanilla_iso> <output_iso>"
    exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Unpack ISO
mkdir -p "$WORK_DIR/iso"
mounted=0
if mount -o loop,ro "$VANILLA_ISO" "$WORK_DIR/iso"; then
    mounted=1
else
    # If mount fails (e.g. no root), try extracting with xorriso.
    echo "Failed to mount ISO. Trying extraction with xorriso..."
    if command -v xorriso > /dev/null 2>&1; then
        xorriso -osirrox on -indev "$VANILLA_ISO" -extract / "$WORK_DIR/iso_content"
    else
        echo "xorriso not found. Cannot extract ISO without root/mount."
        exit 1
    fi
fi

if [[ $mounted -eq 1 ]]; then
    shopt -s nullglob
    iso_files=("$WORK_DIR/iso"/*)
    if [[ ${#iso_files[@]} -gt 0 ]]; then
        mkdir -p "$WORK_DIR/iso_content"
        cp -a "$WORK_DIR/iso/"* "$WORK_DIR/iso_content/"
    fi
    shopt -u nullglob
    umount "$WORK_DIR/iso"
fi
chmod -R u+w "$WORK_DIR/iso_content"

# Prepare extensions
mkdir -p "$WORK_DIR/ext_merged"
for ext in bash.tcz readline.tcz ncurses.tcz; do
    if [[ ! -f t/data/$ext ]]; then
        # Try ncursesw if ncurses not found
        if [[ $ext == ncurses.tcz && -f t/data/ncursesw.tcz ]]; then
            ext="ncursesw.tcz"
        else
            echo "Extension $ext not found in t/data/"
            exit 1
        fi
    fi
    unsquashfs -d "$WORK_DIR/ext_merged" -f -n "t/data/$ext"
done

# Unpack core.gz
mkdir -p "$WORK_DIR/core"
zcat "$WORK_DIR/iso_content/boot/core.gz" | (cd "$WORK_DIR/core" && fakeroot cpio -id)

# Merge extensions into core
cp -a "$WORK_DIR/ext_merged/"* "$WORK_DIR/core/"

# Set default shell to bash for 'tc' user
sed -i 's|tc:x:1001:50:Linux User,,,:/home/tc:/bin/sh|tc:x:1001:50:Linux User,,,:/home/tc:/usr/local/bin/bash|' "$WORK_DIR/core/etc/passwd"

# Repack core.gz
(cd "$WORK_DIR/core" && find . | fakeroot cpio -o -H newc | gzip -9) > "$WORK_DIR/iso_content/boot/core.gz"

# Create new ISO
mkisofs -l -J -R -V "Core-remastered" \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -b boot/isolinux/isolinux.bin -c boot/isolinux/boot.cat \
    -o "$OUTPUT_ISO" "$WORK_DIR/iso_content"

echo "Remastered ISO created at $OUTPUT_ISO"
