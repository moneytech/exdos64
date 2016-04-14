
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "Generic storage abstraction layer",0

;; Functions:
; init_storage
; get_drive_type
; read_sectors

MAX_DISKS		= 40				; OS can handle up to 40 physical drives

list_of_disks:		times MAX_DISKS dw 0xFFFF
number_of_drives	db 0
bootcd			db 0		; this flag is set to one when we boot from a CD

; init_storage:
; Detects mass storage drives

init_storage:
	mov rsi, .msg
	call kprint

	call memdisk_detect		; detect MEMDISK memory-mapped drives
	call ata_detect			; detect ATA/ATAPI drives
	;call ahci_detect		; detect AHCI devices
	;call nvme_detect		; detect NVMe devices -- will be implemented after I have PCI-E driver

	mov rsi, .done_msg
	call kprint
	movzx rax, [number_of_drives]
	call int_to_string
	call kprint
	mov rsi, .done_msg2
	call kprint

	cmp [number_of_drives], 0
	je .no_bootdrive

	cmp [memdisk_phys], 0
	jne .memdisk

	cmp [bootdisk], 0xE0
	je .cd

.hdd:
	mov [.drive], 0

.check_hdd:
	mov al, [.drive]
	cmp al, MAX_DISKS-1
	jg .no_bootdrive

	call get_drive_type
	cmp rax, 0
	jne .next_hdd

	mov al, [.drive]
	mov rbx, 0
	mov rcx, 1
	mov rdi, mbr_tmp
	call read_sectors
	jc .next_hdd

	;mov rsi, bootdrive_mbr
	;mov rdi, mbr_tmp
	;mov rcx, 512
	;rep cmpsb
	;je .found_hdd

.next_hdd:
	;inc [.drive]
	;jmp .check_hdd

.found_hdd:
	mov rsi, .found_msg
	call kprint
	mov rsi, .ata_msg
	call kprint

	mov al, [.drive]
	mov [bootdisk], al

	jmp .done

.cd:
	mov rsi, list_of_disks

.check_cd:
	cmp byte[rsi], 0xFF
	je .no_bootdrive

	test word[rsi], 0x8000
	jz .next_cd

	sub rsi, list_of_disks
	shr rsi, 1
	mov rax, rsi
	mov [bootdisk], al
	mov rsi, .found_msg
	call kprint
	mov rsi, .atapi_msg
	call kprint

	jmp .done

.next_cd:
	add rsi, 2
	jmp .check_cd

.memdisk:
	mov rsi, .found_msg
	call kprint
	mov rsi, .memdisk_msg
	call kprint

	mov [bootdisk], 0
	jmp .done

.done:
	ret

.no_bootdrive:
	mov rsi, .no_msg
	call kprint

	mov rsi, .no_msg
	call start_debugging

	cli
	hlt

.msg				db "[storage] detecting storage devices...",10,0
.done_msg			db "[storage] total of ",0
.done_msg2			db " drives onboard.",10,0
.no_msg				db "[storage] unable to access the boot drive.",10,0
.found_msg			db "[storage] found boot drive: ",0
.memdisk_msg			db "memory-mapped MEMDISK drive.",10,0
.ata_msg			db "ATA hard disk.",10,0
.atapi_msg			db "ATAPI CD/DVD drive.",10,0
.drive				db 0

; get_drive_type:
; Returns information for a specified drive
; In\	AL = Logical disk number
; Out\	RAX = 0 for ATA, 1 for ATAPI, 2 for MEMDISK, -1 if not present

get_drive_type:
	cmp al, MAX_DISKS-1
	jg .no

	and rax, 0xFF
	shl rax, 1
	add rax, list_of_disks

	cmp byte[rax], 0xFF
	je .no
	test word[rax], 0x8000
	jnz .atapi

	cmp byte[rax], 0
	je .ata

	cmp byte[rax], 2
	je .memdisk

	jmp .no

.ata:
	mov rax, 0
	ret

.atapi:
	mov rax, 1
	ret

.memdisk:
	mov rax, 2
	ret

.no:
	mov rax, -1
	ret

; read_sectors:
; Generic read sectors from any type of disk
; In\	AL = Logical disk number
; In\	RDI = Buffer to read sectors to
; In\	RBX = LBA sector
; In\	RCX = Number of sectors to read
; Out\	RFLAGS = Carry flag set on error

read_sectors:
	mov [.buffer], rdi
	mov [.lba], rbx
	mov [.count], rcx

	cmp al, MAX_DISKS-1
	jg .error

	movzx rax, al
	shl rax, 1		; quick multiply by 2
	add rax, list_of_disks

	mov dl, [rax+1]
	mov [.drive], dl

	cmp byte[rax], 0
	je .ata

	cmp byte[rax], 1
	je .ahci

	cmp byte[rax], 2
	je .memdisk

	jmp .error		; for now, because there's still no ATAPI, USB, or NVMe support

.ata:
	test word[rax], 0x8000
	jnz .atapi_sector

.ata_sector:
	mov [.sector_size], 512
	jmp .ata_start

.atapi_sector:
	mov [.sector_size], 2048		; default sector size of CDs

.ata_start:
	cmp [.count], 0
	je .ata_done

	cmp [.count], 255
	jg .ata_big

	mov al, [.drive]
	mov rdi, [.buffer]
	mov rbx, [.lba]
	mov rcx, [.count]
	call ata_read
	jc .error

.ata_done:
	clc
	ret

.ata_big:
	mov al, [.drive]
	mov rdi, [.buffer]
	mov rbx, [.lba]
	mov rcx, 255
	call ata_read
	jc .error

	mov rax, [.sector_size]
	mov rbx, 255
	mul rbx
	add [.buffer], rax
	add [.lba], 255
	sub [.count], 255
	jmp .ata_start

.ahci:
	;mov dl, [rax+1]	; AHCI port
	;mov al, dl
	;call ahci_read
	;jc .error
	jmp .error

.memdisk:
	mov rdi, [.buffer]
	mov rbx, [.lba]
	mov rcx, [.count]
	call memdisk_read
	jc .error

	clc
	ret

.error:
	stc
	ret

.drive				db 0
.lba				dq 0
.count				dq 0
.buffer				dq 0
.sector_size			dq 0




