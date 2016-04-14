
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use16
org 0

jmp short relocate

times 8 - ($-$$) db 0

; El-Torito Boot Information
eltorito_information:
	.primary_volume_descriptor		rd 1
	.boot_file_location			rd 1
	.boot_file_size				rd 1
	.checksum				rd 1
	.reserved:				rb 40

align 64

relocate:
	cli
	cld

	mov ax, 0
	mov ds, ax
	mov ax, 0x7000
	mov es, ax

	mov si, 0x7C00
	mov di, 0x0000
	mov ecx, 2048
	rep movsb

	jmp 0x7000:main

main:
	mov ax, 0x7000
	mov ss, ax
	mov sp, 0
	mov ds, ax
	mov fs, ax
	mov gs, ax

	mov [bootdisk], dl

	mov si, starting_msg
	call print

	mov eax, 16			; read the PVD into memory
	mov ebx, 1
	mov cx, 0x7000
	mov dx, disk_buffer
	call read_sectors
	jc disk_error

	mov eax, dword[disk_buffer+140]	; LBA of path table
	mov ebx, dword[disk_buffer+132]	; size of path table in bytes
	shr ebx, 11			; in sectors
	inc ebx
	mov cx, 0x7000
	mov dx, disk_buffer
	call read_sectors
	jc disk_error

	mov eax, dword[disk_buffer+2]	; read the directory record
	mov ebx, 2
	mov cx, 0x7000
	mov dx, disk_buffer
	call read_sectors
	jc disk_error

search_directory:
	; now search the directory record for the filename
	mov si, disk_buffer
	mov di, filename

.loop:
	cmp si, disk_buffer+4096
	jge file_not_found

	mov [.tmp], si
	mov al, [si]
	mov [.dir_size], al

	add si, 33
	mov cx, 14
	mov di, filename
	rep cmpsb
	je .found_file

	mov si, [.tmp]
	movzx ax, [.dir_size]
	add si, ax
	jmp .loop

.found_file:
	mov si, [.tmp]
	mov eax, [si+2]		; LBA
	mov [.lba], eax
	mov ebx, [si+10]	; size in bytes
	shr ebx, 11		; in sectors
	inc ebx
	mov [.size], ebx

	mov eax, [.lba]
	mov ebx, [.size]
	mov cx, 0x50
	mov dx, 0
	call read_sectors
	jc disk_error

	mov dl, [bootdisk]

	jmp 0:0x500

	jmp $

.tmp					dw 0
.dir_size				db 0
.lba					dd 0
.size					dd 0

file_not_found:
	mov si, fnf_msg
	call print

	jmp $

disk_error:
	mov si, disk_error_msg
	call print

	jmp $

; print:
; Prints a string
; In\	DS:SI = Address of ASCIIZ string
; Out\	Nothing

print:
	lodsb
	cmp al, 0
	je .done
	mov ah, 0xe
	int 0x10
	jmp print

.done:
	ret

; read_sectors:
; Reads sectors
; In\	EAX = LBA
; In\	EBX = Number of sectors
; In\	CX:DX = Segment:Offset to read sectors
; Out\	FLAGS.CF = 0 on success

read_sectors:
	mov [.offset], dx
	mov [.segment], cx
	mov [.lba], eax
	mov [.size], ebx
	add eax, ebx
	mov [.end_lba], eax

.read_block:
	cmp [.size], 16
	jle .small

	cmp [.size], 0
	je .done

	mov eax, [.lba]
	mov [dap.lba], eax
	mov [dap.sectors], 16
	mov ax, [.segment]
	mov [dap.segment], ax
	mov ax, [.offset]
	mov [dap.offset], ax

	mov ah, 0x42
	mov dl, [bootdisk]
	mov si, dap
	int 0x13
	jc .fail

	add [.segment], 0x800
	add [.lba], 16
	sub [.size], 16

	mov eax, [.lba]
	cmp eax, [.end_lba]
	jge .done

	jmp .read_block

.small:
	mov eax, [.lba]
	mov [dap.lba], eax
	mov eax, [.size]
	mov [dap.sectors], ax
	mov ax, [.segment]
	mov [dap.segment], ax
	mov ax, [.offset]
	mov [dap.offset], ax

	mov ah, 0x42
	mov dl, [bootdisk]
	mov si, dap
	int 0x13
	jc .fail
	jmp .done

.fail:
	stc
	ret

.done:
	clc
	ret

.lba				dd 0
.end_lba			dd 0
.size				dd 0
.segment			dw 0
.offset				dw 0

bootdisk			db 0
align 16
dap:
	.size			db 0x10
	.reserved		db 0
	.sectors		dw 1
	.offset			dw 0x7C00
	.segment		dw 0
	.lba			dd 0
				dd 0
starting_msg					db "Starting ExDOS64...",0
disk_error_msg					db 13,10,"Disk I/O error.",10,0
fnf_msg						db 13,10,"File not found.",10,0
filename					db "KERNEL64.SYS;1"

times 2048 - ($ - $$) db 0

disk_buffer:



