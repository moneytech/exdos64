entries				dd 511			; number of entries in directory
							; 511 and not 512 because the first entry is always reserved for hierarchy support
				times 32 - ($-$$) db 0

filename			db "kernel64sys"		; 0
reserved1			db 0				; 11
lba_sector			dd 200				; 12
size_sectors			dd 400				; 16
size_bytes			dd 400*512			; 20
time				db 0
				db 0
date				db 5
				db 1
				dw 2016
reserved2			dw 0


wallpaper:
.filename			db "bg      bmp"		; 0
.reserved1			db 0				; 11
.lba_sector			dd 8000				; 12
.size_sectors			dd 2813				; 16
.size_bytes			dd 1440054			; 20
.time				db 0
				db 0
.date				db 5
				db 1
				dw 2016
.reserved2			dw 0

kconfig:
.filename			db "kernel  cfg"		; 0
.reserved1			db 0				; 11
.lba_sector			dd 2000				; 12
.size_sectors			dd 1				; 16
.size_bytes			dd 1*512			; 20
.time				db 0
				db 0
.date				db 5
				db 1
				dw 2016
.reserved2			dw 0

test_driver:
.filename			db "test    sys"		; 0
.reserved1			db 0				; 11
.lba_sector			dd 2001				; 12
.size_sectors			dd 2				; 16
.size_bytes			dd 2*512			; 20
.time				db 0
				db 0
.date				db 5
				db 1
				dw 2016
.reserved2			dw 0



