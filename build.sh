#!/bin/sh
fasm os/kernel.asm isofs/kernel64.sys
#fasm boot/boot_cd.asm boot_cd.sys
#cp boot_cd.sys isofs/
dd if=isofs/kernel64.sys conv=notrunc bs=512 seek=200 of=disk.img
mkisofs -no-emul-boot -b boot_cd.sys -boot-load-size 4 -o exdos.iso isofs/
#rm boot_cd.sys


