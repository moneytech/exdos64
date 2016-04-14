
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

db "ATA/ATAPI Disk Driver",0

;; Functions:
; ata_detect
; ata_irq
; ata_delay
; ata_identify
; ata_reset
; ata_read
; ata_read_lba28
; atapi_read

pci_ide_bus				db 0
pci_ide_device				db 0
pci_ide_function			db 0

ata_primary_base			dw 0x1F0
ata_secondary_base			dw 0x170
atapi_packet:				times 12 db 0

; Command List
ATA_IDENTIFY				= 0xEC
ATA_READ_LBA28				= 0x20
ATA_PACKET				= 0xA0
ATA_IDENTIFY_PACKET			= 0xA1
ATAPI_READ				= 0xA8

; ata_detect:
; Detects ATA/ATAPI drives

ata_detect:
	mov rsi, .starting_msg
	call kprint

	call disable_interrupts

	; install IRQ handlers
	mov al, 14
	mov rbp, ata_irq
	call install_irq

	mov al, 15
	mov rbp, ata_irq
	call install_irq

	; look for PCI IDE controller
	mov ax, 0x0101
	call pci_get_device_class

	cmp ax, 0xFFFF
	je .no_ata

	mov [pci_ide_bus], al
	mov [pci_ide_device], ah
	mov [pci_ide_function], bl

	mov rsi, .found_msg
	call kprint

	mov al, [pci_ide_bus]
	call hex_byte_to_string
	call kprint
	mov rsi, .colon
	call kprint
	mov al, [pci_ide_device]
	call hex_byte_to_string
	call kprint
	mov rsi, .colon
	call kprint
	mov al, [pci_ide_function]
	call hex_byte_to_string
	call kprint
	mov rsi, newline
	call kprint

.get_primary_io:
	mov al, [pci_ide_bus]
	mov ah, [pci_ide_device]
	mov bl, [pci_ide_function]
	mov bh, 0x14			; BAR0
	call pci_read_dword

	cmp ax, 1
	jle .got_primary

	and ax, 0xFFFC
	mov [ata_primary_base], ax

.got_primary:
	mov rsi, .primary_msg
	call kprint
	mov ax, [ata_primary_base]
	call hex_word_to_string
	call kprint
	mov rsi, newline
	call kprint

.get_secondary_io:
	mov al, [pci_ide_bus]
	mov ah, [pci_ide_device]
	mov bl, [pci_ide_function]
	mov bh, 0x18			; BAR1
	call pci_read_dword

	cmp ax, 1
	jle .got_secondary

	and ax, 0xFFFC
	mov [ata_secondary_base], ax

.got_secondary:
	mov rsi, .secondary_msg
	call kprint
	mov ax, [ata_secondary_base]
	call hex_word_to_string
	call kprint
	mov rsi, newline
	call kprint

.identify_devices:
	; detect and identify the devices
	mov al, [.device]
	mov ah, [.channel]
	mov rdi, ata_identify_data
	call ata_identify
	jc .next_device

	movzx rdi, [number_of_drives]
	shl rdi, 1
	add rdi, list_of_disks
	mov byte[rdi], 0		; tell the storage abstraction layer that we're using ATA
	inc rdi

	mov ah, [.channel]
	mov al, [.device]
	shl ah, 4
	or al, ah			; high nibble: channel; low nibble: device
	shl bl, 7
	or al, bl			; if bit 7 (value 0x80) is set, this is an ATAPI device
	stosb

	inc [number_of_drives]

.next_device:
	inc [.device]
	cmp [.device], 2
	jge .next_channel
	jmp .identify_devices

.next_channel:
	mov [.device], 0
	inc [.channel]
	cmp [.channel], 2
	jge .done
	jmp .identify_devices

.done:
	ret

.no_ata:
	mov rsi, .no_msg
	call kprint

	ret

.starting_msg				db "[ata] detecting ATA/ATAPI drives...",10,0
.no_msg					db "[ata] PCI IDE controller not present.",10,0
.found_msg				db "[ata] found IDE controller at PCI slot ",0
.colon					db ":",0
.primary_msg				db "[ata] primary channel base I/O port is 0x",0
.secondary_msg				db "[ata] secondary channel base I/O port is 0x",0
.channel				db 0
.device					db 0

; ata_irq:
; ATA IRQ handler

ata_irq:
	mov [.happened], 1
	call send_eoi
	iretq

align 32
.happened				db 0

; ata_delay:
; Creates a delay

ata_delay:
	pushaq

	mov dx, [ata_primary_base]
	add dx, 7
	in al, dx
	in al, dx
	in al, dx
	in al, dx

	mov dx, [ata_secondary_base]
	add dx, 7
	in al, dx
	in al, dx
	in al, dx
	in al, dx

	popaq
	ret

; ata_identify:
; Identifies an ATA device
; In\	AH = Channel
; In\	AL = Device
; In\	RDI = Location to store identify data
; Out\	RFLAGS.CF = 0 if device is present
; Out\	BL = 0 if device is an HDD, 1 if it is an ATAPI device

ata_identify:
	mov [.channel], ah
	mov [.device], al
	mov [.data], rdi

	mov rsi, .starting_msg
	call kprint
	movzx rax, [.device]
	call int_to_string
	call kprint
	mov rsi, .starting_msg2
	call kprint
	movzx rax, [.channel]
	call int_to_string
	call kprint
	mov rsi, newline
	call kprint

	test [.channel], 1
	jnz .secondary

	mov ax, [ata_primary_base]
	mov [.io], ax

	jmp .start

.secondary:
	mov ax, [ata_secondary_base]
	mov [.io], ax

.start:
	call ata_reset

	; first, let's select the drive
	mov al, 0xA0
	mov bl, [.device]
	shl bl, 4
	or al, bl
	mov dx, [.io]
	add dx, 6			; drive select port
	out dx, al
	call ata_delay

	;mov dx, [.io]
	;add dx, 4
	;in al, dx
	;cmp al, 0x14
	;jne .is_ata

	;cmp al, 0xEB
	;jne .is_ata

	;jmp .is_atapi

.is_ata:
	; set features register to 0
	mov dx, [.io]
	add dx, 1
	mov al, 0
	out dx, al

	inc dx				; 0x1F2
	out dx, al

	inc dx				; 0x1F3
	out dx, al

	inc dx				; 0x1F4
	out dx, al

	inc dx				; 0x1F5
	out dx, al

	; send identify command
	mov al, ATA_IDENTIFY
	mov dx, [.io]
	add dx, 7
	out dx, al

	in al, dx
	cmp al, 0
	je .no

.wait_for_ready:
	;in al, dx
	;test al, 0x80
	;jnz .wait_for_ready

.check_for_atapi:
	mov dx, [.io]
	add dx, 4
	in al, dx
	cmp al, 0x14
	jne .wait_for_drq

	inc dx
	in al, dx
	cmp al, 0xEB
	jne .wait_for_drq

	jmp .is_atapi

.wait_for_drq:
	mov rsi, .ata_msg
	call kprint

	clc
	mov bl, 0
	ret

.is_atapi:
	mov rsi, .atapi_msg
	call kprint

	clc
	mov bl, 1
	ret

.no:
	mov rsi, .no_msg
	call kprint

	stc
	ret

.channel				db 0
.device					db 0
.data					dq 0
.io					dw 0
.starting_msg				db "[ata] identifying device ",0
.starting_msg2				db " on channel ",0
.atapi_msg				db "[ata] found ATAPI drive.",10,0
.ata_msg				db "[ata] found ATA drive.",10,0
.no_msg					db "[ata] no device found.",10,0

; ata_reset:
; Resets the ATA primary and secondary channels

ata_reset:
	pushaq

	mov dx, [ata_primary_base]
	add dx, 0x206
	mov al, 4
	out dx, al
	call iowait

	mov dx, [ata_primary_base]
	add dx, 0x206
	mov al, 0
	out dx, al

	mov dx, [ata_secondary_base]
	add dx, 0x206
	mov al, 4
	out dx, al
	call iowait

	mov dx, [ata_secondary_base]
	add dx, 0x206
	mov al, 0
	out dx, al

	popaq
	ret

; ata_read:
; Reads from ATA device
; In\	AL = Device select bitfield
;		Bit 0: Master/slave device
;		Bit 4: Primary/secondary channel
;		Bit 7: Is an ATAPI device
; In\	RDI = Buffer to read sectors into
; In\	RBX = LBA sector to read
; In\	RCX = Number of sectors to read
; Out\	RFLAGS.CF = 0 on success

ata_read:
	call enable_interrupts

	test al, 0x80		; is ATAPI?
	jnz atapi_read

	;cmp rbx, 0xFFFFFFF-0x100		; use LBA48 only when nescessary --
	;jge ata_read_lba48			; -- because LBA28 is faster and uses less IO bandwidth

	jmp ata_read_lba28

; ata_read_lba28:
; Reads from ATA hard disk using LBA28

ata_read_lba28:
	mov [.buffer], rdi
	mov [.sectors], rcx
	mov [.lba], rbx
	mov [.device], al
	mov [.count], 0

	mov rsi, .starting_msg
	call kprint

	mov al, [.device]
	test al, 0x10		; secondary channel?
	jnz .secondary

.primary:
	mov dx, [ata_primary_base]
	mov [.io], dx
	jmp .start

.secondary:
	mov dx, [ata_secondary_base]
	mov [.io], dx

.start:
	call ata_reset		; reset the ATA bus
	mov al, [.device]
	and al, 1
	shl al, 4
	mov rbx, [.lba]
	shr rbx, 24
	or al, bl
	or al, 0xE0
	mov dx, [.io]
	add dx, 6
	out dx, al		; select device and highest 4 bits of LBA
	call ata_delay

	mov al, 0
	mov dx, [.io]
	inc dx
	out dx, al		; select PIO mode

	mov rax, [.sectors]
	mov dx, [.io]
	add dx, 2
	out dx, al		; sector count

	mov rax, [.lba]
	mov dx, [.io]
	add dx, 3
	out dx, al		; LBA low

	mov rax, [.lba]
	shr rax, 8
	mov dx, [.io]
	add dx, 4
	out dx, al		; LBA middle

	mov rax, [.lba]
	shr rax, 16
	mov dx, [.io]
	add dx, 5
	out dx, al		; LBA high

	mov al, ATA_READ_LBA28
	mov dx, [.io]
	add dx, 7
	out dx, al		; command byte

.wait_for_ready:
	mov dx, [.io]
	add dx, 7
	in al, dx
	cmp al, 0
	je .error
	;test al, 0x80
	;jnz .wait_for_ready

.check_for_error:
	in al, dx
	test al, 1
	jnz .error

	test al, 0x20
	jnz .error

	test al, 8
	jnz .start_reading
	jmp .check_for_error

.start_reading:
	mov rdi, [.buffer]
	mov rcx, 256
	mov dx, [.io]
	rep insw

	add [.buffer], 512
	inc [.count]

	mov rax, [.sectors]
	cmp [.count], rax
	jge .done

	call ata_delay

	jmp .wait_for_ready

.done:
	mov rsi, .done_msg
	call kprint
	clc
	ret

.error:
	mov rsi, .err_msg
	call kprint
	stc
	ret

.io			dw 0
.device			db 0
.buffer			dq 0
.lba			dq 0
.sectors		dq 0
.count			dq 0
.starting_msg		db "[ata] attempting to read from ATA device...",10,0
.done_msg		db "[ata] done.",10,0
.err_msg		db "[ata] disk I/O error.",10,0

; atapi_read:
; Reads from ATAPI device

atapi_read:
	mov [.device], al
	mov [.lba], rbx
	mov [.sectors], rcx
	mov [.buffer], rdi
	mov [.count], 0

	mov rsi, .starting_msg
	call kprint

	mov al, [.device]
	test al, 0x10		; secondary channel?
	jnz .secondary

.primary:
	mov dx, [ata_primary_base]
	mov [.io], dx
	jmp .start

.secondary:
	mov dx, [ata_secondary_base]
	mov [.io], dx

.start:
	; create a SCSI command packet
	mov rdi, atapi_packet
	mov al, 0
	mov rcx, 12
	rep stosb

	mov byte[atapi_packet], ATAPI_READ	; command byte

	mov rax, [.sectors]
	mov byte[atapi_packet+9], al		; number of sectors

	mov rax, [.lba]				; LBA sector
	mov byte[atapi_packet+5], al
	shr rax, 8
	mov byte[atapi_packet+4], al
	shr rax, 8
	mov byte[atapi_packet+3], al
	shr rax, 8
	mov byte[atapi_packet+2], al

	; Reset the ATA bus
	call ata_reset

	; select the drive
	mov al, [.device]
	and al, 1
	shl al, 4
	mov dx, [.io]
	add dx, 6
	out dx, al
	call ata_delay			; standard 400ns delay

	mov al, 0
	mov dx, [.io]
	add dx, 1
	out dx, al			; tell the controller we're using PIO

	mov rax, [.sectors]
	shl rax, 11
	mov dx, [.io]
	add dx, 2
	out dx, al			; number of bytes we expect, low word

	inc dx
	shr rax, 8
	out dx, al			; high word ^^

	; now, send the ATAPI PACKET command
	mov al, ATA_PACKET
	mov dx, [.io]
	add dx, 7
	out dx, al

	; check if the drive is present
	in al, dx
	in al, dx
	cmp al, 0
	je .error

.wait_send_packet:
	; wait for DRQ to set so we can send the packet
	in al, dx
	test al, 8
	jnz .send_packet

	test al, 1		; ERR?
	jnz .error

	test al, 0x20		; DF?
	jnz .error
	jmp .wait_send_packet

.send_packet:
	mov dx, [.io]
	mov rsi, atapi_packet
	mov rcx, 6
	rep outsw			; send ATAPI packet to device

	call ata_delay			; wait for device to get ready

	; ask the drive for the size of data it will send
	mov dx, [.io]
	add dx, 2
	in al, dx
	mov byte[.size], al
	inc dx
	in al, dx
	mov byte[.size+1], al

.wait_for_error:
	mov dx, [.io]
	add dx, 7
	in al, dx
	test al, 8
	jnz .start_reading
	test al, 1
	jnz .error
	test al, 0x20
	jnz .error
	jmp .wait_for_error

.start_reading:
	; now read the data
	mov dx, [.io]
	mov rdi, [.buffer]
	movzx rcx, [.size]
	shr rcx, 1
	rep insw

	; wait for the command to finish
	call ata_delay

.wait_for_command_finish:
	;mov dx, [.io]
	;add dx, 7
	;in al, dx
	;test al, 0x88		; wait for BSY and DRQ to clear
	;jz .done
	;jmp .wait_for_command_finish

.done:
	mov rsi, .done_msg
	call kprint

	clc
	ret

.error:
	mov rsi, .err_msg
	call kprint

	stc
	ret

.io			dw 0
.device			db 0
.buffer			dq 0
.lba			dq 0
.sectors		dq 0
.count			dq 0
.size			dw 0
.starting_msg		db "[atapi] attempting to read from ATAPI device...",10,0
.done_msg		db "[atapi] done.",10,0
.err_msg		db "[atapi] disk I/O error.",10,0

; ata_identify_data:
; Data returned from the ATA/ATAPI IDENTIFY command
align 16
ata_identify_data:
	.device_type		dw 0		; 0

	.cylinders		dw 0		; 1
	.reserved_word2		dw 0		; 2
	.heads			dw 0		; 3
				dd 0		; 4
	.sectors_per_track	dw 0		; 6
	.vendor_unique:		times 3 dw 0	; 7
	.serial_number:		times 20 db 0	; 10
				dd 0		; 11
	.obsolete1		dw 0		; 13
	.firmware_revision:	times 8 db 0	; 14
	.model:			times 40 db 0	; 18
	.maximum_block_transfer	db 0
				db 0
				dw 0

				db 0
	.dma_support		db 0
	.lba_support		db 0
	.iordy_disable		db 0
	.iordy_support		db 0
				db 0
	.standyby_timer_support	db 0
				db 0
				dw 0

				dd 0
	.translation_fields	dw 0
				dw 0
	.current_cylinders	dw 0
	.current_heads		dw 0
	.current_spt		dw 0
	.current_sectors	dd 0
				db 0
				db 0
				db 0
	.user_addressable_secs	dd 0
				dw 0
	times 512 - ($-ata_identify_data) db 0


