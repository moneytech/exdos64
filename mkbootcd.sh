#!/bin/sh

mkdir isofs

# Assemble bootloader
fasm boot/boot_cd.asm boot_cd.sys

# Assemble kernel
fasm os/kernel.asm isofs/kernel64.sys

# Put useful things on the CD
cp boot_cd.sys isofs/boot_cd.sys
cp wallpaper2.bmp isofs/bg.bmp

# Make the CD
mkisofs -no-emul-boot -boot-load-size 4 -b boot_cd.sys -o exdos.iso -V "ExDOS64" isofs/

# Cleanup..
rm isofs/*
rmdir isofs
rm boot_cd.sys


