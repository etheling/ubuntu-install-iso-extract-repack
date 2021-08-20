#!/bin/bash
VERSION="0.9"
set -e

###
## Tested with: Ubuntu Live Server DVD .iso: 18.04.5, 20.04.2, 21.04

### Build Based on information fragments of below documents. Kudos!
## https://github.com/office-itou/Linux/blob/master/installer/source/dist_remaster_dvd.sh
## https://gist.github.com/s3rj1k/55b10cd20f31542046018fcce32f103e#file-howto-L54
## https://unix.stackexchange.com/questions/487895/how-to-create-a-freebsd-iso-with-mkisofs-that-will-boot-in-virtualbox-under-uefi

### Helpful debug command lines
# xorriso -indev out.iso -report_el_torito plain -report_system_area plain
# xorriso -report_about warning -indev ubuntu-21.04-live-server-amd64.iso -report_system_area as_mkisofs

### TODO:
## - extract to /tmp/.....
## - set output name via VAR

echo "Ubuntu Install DVD .iso Extract, Modify and Repackage to .iso v${VERSION}"
if [ "$#" -lt 1 ]; then

    echo "Usage: $0 <ubuntu-input.iso> [ 1..n <add-mod-shellscript> ]"    
    echo " "
    echo "ERROR: no .iso name given"
    echo " "
    exit 1
fi

ISO_NAME=$1
EFI_NAME=efi.img
MBR_NAME=mbr.img
ELT_BOOTCAT=$(xorriso -indev "${ISO_NAME}" -report_el_torito plain -report_system_area plain 2> /dev/null | grep "El Torito cat path" | cut -d":" -f2 | tr -d ' ')
VOLUME_ID=$(xorriso -indev "${ISO_NAME}" -report_el_torito plain -report_system_area plain 2>&1  | grep "Volume id" | cut -d":" -f2 | xargs)
FILETYPE=$(file -b --mime-type "${ISO_NAME}")
XORRISOVER="1.5.2" ; # known working version(s)
OSX=$(uname -s)
SLEEP=2 ; # delay between 'tasks'

##
if [ ! "${FILETYPE}" = "application/x-iso9660-image" ]; then
    echo "ERROR: ${ISO_NAME} doesn't appear to be valid ISO 9660 image. Aborting."
    echo ""
    exit 1
fi

##
if [ "${OSX}" = "Darwin" ]; then
    echo "ERROR: This utility doesn't run on OSX (we need a working fdisk). Use Linux. Aborting."
    echo ""
    exit 1
fi

##
echo "==> Developed and tested with xorriso version(s): ${XORRISOVER}. Installed version is:"
xorriso --version 2>/dev/null | grep "xorriso version"

##
echo "==> Extracting .ISO (${ISO_NAME})"
if [ -d ./iso ]; then
    echo "WARNING: ABOUT TO ERASE DIRECTORY ./iso. CTRL+C now to abort."
    sleep 5
    rm -rf ./iso/
fi
xorriso -osirrox on -indev "${ISO_NAME}" -extract / iso && chmod -R +w iso

##
echo " "
echo "==> Extracting EFI image to ./${EFI_NAME}"
sleep "${SLEEP}"
ISO_SKIPS=$(fdisk -l "./${ISO_NAME}" | awk '/EFI/ {print $2;}')
ISO_COUNT=$(fdisk -l "./${ISO_NAME}" | awk '/EFI/ {print $4;}')
echo "==> Skipping ${ISO_SKIPS} 512b blocks and extracting ${ISO_COUNT} blocks"
dd if="./${ISO_NAME}" of="./${EFI_NAME}" bs=512 skip="${ISO_SKIPS}" count="${ISO_COUNT}" status=none
file "./${EFI_NAME}"

##
echo " "
echo "==> Extract 446b ISO boot sector to ./${MBR_NAME}"
sleep "${SLEEP}"
dd if="./${ISO_NAME}" bs=1 count=446 of="./${MBR_NAME}"
file ./${MBR_NAME}


##
echo ""
echo "==> Begin .iso modification..."
if [ "$#" -gt 1 ]; then
    for i in $(seq 2 1 $#); do
	echo "==> Executing ${!i} .iso modification script..."
	source "${!i}"
	echo " "
    done    
else
    echo ""
    echo "WARNING: NO ISO MODIFICATION SHELL SCRIPTS PROVIDED. PROCEEDING TO REPACKAGE."
    echo ""
fi

echo " "
echo "==> Build .iso..."
sleep "${SLEEP}"

if [ -f iso/isolinux/isolinux.bin ]; then
    echo "==> Found isolinux/isolinux.bin on iso/ - asusming _< Ubuntu 20.04 variant"
    xorriso -as mkisofs -r \
	    -V "${VOLUME_ID}" \
	    -o output.iso \
	    -J -l -b isolinux/isolinux.bin -c "${ELT_BOOTCAT}" -no-emul-boot \
	    -boot-load-size 4 -boot-info-table \
	    -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
	    -isohybrid-gpt-basdat -isohybrid-apm-hfsplus \
	    -isohybrid-mbr ./${MBR_NAME}  \
	    iso
    
elif [ -f iso/boot/grub/i386-pc/eltorito.img ]; then
     echo "==> Found boot/grub/i386-pc/eltorito.img on iso/ - asusming _> Ubuntu 21.04 variant"
     xorriso -as mkisofs -r \
	     -V "${VOLUME_ID}" \
	     -o output.iso \
	     -J -l -b /boot/grub/i386-pc/eltorito.img -c "${ELT_BOOTCAT}" -no-emul-boot \
	     -boot-load-size 4 -boot-info-table \
	     -eltorito-alt-boot \
	     -append_partition 2 0xef ./efi.img \
	     -e '--interval:appended_partition_2:all::' \
	     -no-emul-boot \
	     -isohybrid-gpt-basdat \
	     -isohybrid-mbr ./mbr.img  \
	     iso

     ## NOTE: removed iso/boot from both
fi


echo " "
echo "==> Comparing output and original ISO:"
echo ":input"
xorriso -indev "./${ISO_NAME}" -report_el_torito plain -report_system_area plain
echo " "
echo ":ouput"
xorriso -indev ./output.iso -report_el_torito plain -report_system_area plain
echo " "


echo "==> Done. If you have qemu installed, run following to test image:"
echo "    qemu-system-x86_64 -boot d -m 4096 -cdrom output.iso"
echo " "
echo "==> Image: output.iso -- use following command to write to USB stick"
echo "    dd if=./output.iso bs=1M of=<DEVICE> ; sync ; sync ; sync"
echo " "
