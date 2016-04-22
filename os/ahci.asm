
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

db "Advanced Host Controller Interface Driver",0

;; Functions:
; ahci_detect
; ahci_detect_ports
; ahci_check_port
; ahci_get_port_base

use64
ahci_available_ports		db 0
ahci_ports			dd 0
ahci_base_phys			dq 0
ahci_pci_bus			db 0
ahci_pci_device			db 0
ahci_pci_function		db 0
ahci_base			dq AHCI_BASE
AHCI_BASE			= 0x300000000

; AHCI Types of FIS

AHCI_FIS_H2D			= 0x27

; AHCI Port Structure

ahci_port:
	.command_list		= 0x00
	.fis			= 0x08
	.interrupt_status	= 0x10
	.interrupt_enable	= 0x14
	.command		= 0x18
	.reserved0		= 0x1C
	.task_file		= 0x20
	.sata_status		= 0x28
	.sata_control		= 0x2C
	.sata_error		= 0x30
	.sata_active		= 0x34
	.command_issue		= 0x38
	.sata_notification	= 0x3C
	.fbs			= 0x40

; ahci_detect:
; Detects AHCI devices

ahci_detect:
	mov rsi, .starting_msg
	call kprint

	mov ax, 0x106
	call pci_get_device_class		; search for PCI AHCI controller
	cmp ax, 0xFFFF
	je .no_ahci

	mov [ahci_pci_bus], al
	mov [ahci_pci_device], ah
	mov [ahci_pci_function], bl

	mov rsi, .found_msg
	call kprint
	mov al, [ahci_pci_bus]
	call hex_byte_to_string
	call kprint
	mov rsi, .colon
	call kprint
	mov al, [ahci_pci_device]
	call hex_byte_to_string
	call kprint
	mov rsi, .colon
	call kprint
	mov al, [ahci_pci_function]
	call hex_byte_to_string
	call kprint
	mov rsi, newline
	call kprint

	mov al, [ahci_pci_bus]
	mov ah, [ahci_pci_device]
	mov bl, [ahci_pci_function]
	mov bh, 0x24				; BAR5
	call pci_read_dword
	and eax, 0xFFFFFFF0
	mov dword[ahci_base_phys], eax

	; now map the AHCI base memory to the virtual address space
	mov rax, [ahci_base_phys]
	and eax, 0xFFE00000
	mov rbx, AHCI_BASE
	mov rcx, 2
	mov dl, 3
	call vmm_map_memory

	mov rax, [ahci_base_phys]
	mov rbx, 0x200000
	call round_backward

	mov rbx, [ahci_base_phys]
	sub rbx, rax
	add [ahci_base], rbx

	mov rsi, .base_msg
	call kprint
	mov rax, [ahci_base_phys]
	call hex_dword_to_string
	call kprint
	mov rsi, .base_msg2
	call kprint
	mov rax, [ahci_base]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint

	call ahci_detect_ports

	; enable PCI bus master DMA
	mov al, [ahci_pci_bus]
	mov ah, [ahci_pci_device]
	mov bl, [ahci_pci_function]
	mov bh, 4
	call pci_read_dword
	mov edx, eax
	or edx, 4
	mov al, [ahci_pci_bus]
	mov ah, [ahci_pci_device]
	mov bl, [ahci_pci_function]
	mov bh, 4
	call pci_write_dword

	ret

.no_ahci:
	mov rsi, .no_msg
	call kprint
	ret

.starting_msg			db "[ahci] looking for PCI AHCI controller...",10,0
.no_msg				db "[ahci] AHCI controller not found.",10,0
.found_msg			db "[ahci] found AHCI controller at PCI slot ",0
.base_msg			db "[ahci] base memory is at physical 0x",0
.base_msg2			db ", virtual 0x",0
.colon				db ":",0

; ahci_detect_ports:
; Detects available AHCI ports

ahci_detect_ports:
	mov rsi, [ahci_base]
	add rsi, 0x0C
	mov eax, [rsi]
	mov [ahci_ports], eax

	mov cl, 0

.loop:
	cmp cl, 32
	jge .done

	call ahci_check_port
	jc .no_port

	inc [ahci_available_ports]
	inc cl
	jmp .loop

.no_port:
	inc cl
	jmp .loop

.done:
	mov rsi, .msg
	call kprint
	movzx rax, [ahci_available_ports]
	call int_to_string
	call kprint
	mov rsi, .msg2
	call kprint

	ret

.msg				db "[ahci] total of ",0
.msg2				db " ports available.",10,0

; ahci_check_port:
; Checks if an AHCI port is present
; In\	CL = Port number (0 => 31)
; Out\	RFLAGS.CF = Clear if port is present

ahci_check_port:
	mov eax, 1
	shl eax, cl
	test [ahci_ports], eax
	jz .no

	clc
	ret

.no:
	stc
	ret

; ahci_get_port_base:
; Returns address of an AHCI port within the AHCI base memory
; In\	CL = Port number (0 => 31)
; Out\	RAX = Virtual address of AHCI port data

ahci_get_port_base:
	movzx rax, cl
	shl rax, 7		; mul 128
	add rax, 0x100
	add rax, [ahci_base]
	ret

; ahci_create_fis:
; Creates a command FIS
; In\	RAX = LBA
; In\	RCX = Sector count
; In\	DL = Command byte
; In\	RDI = Physical address of DMA transfer
; Out\	RAX = Address of FIS

ahci_create_fis:
	pushaq

	mov rdi, ahci_command_fis
	mov rcx, ahci_command_fis_size
	mov rax, 0
	rep stosb

	mov byte[ahci_command_fis.type], AHCI_FIS_H2D
	mov byte[ahci_command_fis.is_command], 0x80	; tell ahci controller this is a command FIS and not a control FIS

	popaq
	mov [ahci_command_fis.command], dl		; command byte
	mov [ahci_command_fis.count], cx		; sector count
	mov [ahci_prdt.base], rdi
	mov [ahci_prdt.reserved], 0
	shl rcx, 9
	mov [ahci_prdt.byte_count], ecx			; bytecount of DMA transfer

	mov [ahci_command_fis.lba0], al			; Lba sector
	shr rax, 8
	mov [ahci_command_fis.lba1], al
	shr rax, 8
	mov [ahci_command_fis.lba2], al
	shr rax, 8
	mov [ahci_command_fis.lba3], al
	shr rax, 8
	mov [ahci_command_fis.lba4], al
	shr rax, 8
	mov [ahci_command_fis.lba5], al

	mov rax, ahci_command_fis
	ret

; ahci_command_fis:
; Name says it^^
align 128			; AHCI probably wants this aligned
ahci_command_fis:
	.type			db AHCI_FIS_H2D
	.is_command		db 0x80			; bit 7 set to tell AHCI controller this is a command

	.command		db 0		; command byte
	.feature_low		db 0

	.lba0			db 0
	.lba1			db 0
	.lba2			db 0
	.device_select		db 0

	.lba3			db 0
	.lba4			db 0
	.lba5			db 0
	.feature_high		db 0

	.count			dw 0
	.icc			db 0
	.control		db 0

	.reserved:		times 4 db 0

	times 128 - ($-ahci_command_fis) db 0

ahci_prdt:
	.base			dq 0
	.reserved		dd 0
	.byte_count		dd 0

ahci_command_fis_size		= $ - ahci_command_fis

; ahci_send_command:
; Sends a command to an AHCI device
; In\	AL = Port number
; In\	RBX = LBA sector
; In\	RCX = Sector count
; In\	RDI = Virtual buffer address
; In\	DL = Command byte
; Out\	RFLAGS.CF = 0 on success

ahci_send_command:
	mov [.port], al
	mov [.lba], rbx
	mov [.sector], rcx
	mov [.buffer], rdi
	mov [.command], dl

	; AHCI is a PCI bus master DMA device, and so we must use physical address
	mov rax, [.buffer]
	call vmm_get_physical_address
	cmp rax, 0			; is there a page with no memory mapped in it?
	je .error			; yep -- don't send the command because this will overwrite the kernel
	mov [.buffer_phys], rax

	; now construct the command FIS
	mov rax, [.lba]
	mov rcx, [.sector]
	mov dl, [.command]
	mov rdi, [.buffer_phys]
	call ahci_create_fis

	; construct the command list and header
	mov rdi, ahci_command_list
	mov rcx, ahci_command_list_size
	mov rax, 0
	rep stosb

	mov [ahci_command_list.fis_length], 0x10	; length of the command FIS in DWORDs
	mov [ahci_command_list.reset], 0		; don't reset the drive
	mov [ahci_command_list.prdt_length], 1		; only 1 PRDT entry

	mov rax, [.sector]
	shl rax, 9
	mov [ahci_command_list.prdt_bytes], eax		; size of the DMA transfer in bytes

	mov [ahci_command_list.command_table], ahci_command_fis	; command FIS and PRDT

	; now get the port base
	mov cl, [.port]
	call ahci_get_port_base

	; tell the controller about the command
	mov qword[rax+ahci_port.command_list], ahci_command_list

	; tell the controller to send the command to the SATA device
	mov dword[rax+ahci_port.command_issue], 1

	call flush_caches

	; TODO: Continue work here!!!

.error:
	stc
	ret

.port				db 0
.lba				dq 0
.sector				dq 0
.buffer				dq 0
.command			db 0
.buffer_phys			dq 0

; ahci_command_list:
; AHCI Command List
align 128
ahci_command_list:
	; command header 0
	.fis_length		db 0x10
	.reset			db 0

	.prdt_length		dw 1
	.prdt_bytes		dd 0

	.command_table		dq ahci_command_fis

	.reserved:		times 4 dd 0

	times 0x400 - ($-ahci_command_list) db 0		; we only use one command header
ahci_command_list_size		= $ - ahci_command_list





