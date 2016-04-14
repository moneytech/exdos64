
;;
;; Test Driver for ExDOS64
;; Just to demonstrate capability of running a driver in userspace
;; And proof that ExDOS64 is a hybrid kernel
;;

use64
org 0x4000000			; drivers are loaded at 64 MB

application_header:
	.signature		db "ExDOS64"	; tell the kernel we are a valid program
	.version		db 1		; I only made one version of this
	.type			db 2		; tell the kernel we are a driver, not an application
	.entry_point		dq main		; entry point
	.program_size		dq end_of_file - application_header
	.program_name		dq program_name	; name of program
	.driver_hardware	dq hardware	; name of driver hardware
	.reserved		dq 0
				dq 0

program_name			db "test.sys",0
hardware			db "Test Userspace Driver for ExDOS64",0

include				"drivers/drivers.asm"		; Driver API macros

; main:
; Driver entry point
; The kernel passes some information to the driver
; RSI		= Driver file name
; RAX		= Function code (as of now, function 0 is defined to initialize a device)

main:
	; Let's try changing the Bochs Graphics Adapter resolution, waiting for 5 seconds, and restoring it

	; First, show signs of life
	mov rsi, starting_msg
	driver_api kprint

	; Comment out this line to show a driver demo
	driver_api exit_driver

	; Detect the BGA
	mov cx, 0
	call bga_read_register

	cmp ax, 0xB0C0
	jl old_bga

	cmp ax, 0xFFFF
	je no_bga

	mov rsi, found_msg
	driver_api kprint

	; Disable BGA
	mov cx, 4
	mov ax, 0
	call bga_write_register

	; Set resolution 1024x768x16
	mov cx, 1
	mov ax, 1024
	call bga_write_register

	mov cx, 2
	mov ax, 768
	call bga_write_register

	mov cx, 3
	mov ax, 16
	call bga_write_register

	; Enable BGA
	mov cx, 4
	mov ax, 0x41
	call bga_write_register

	mov rsi, waiting_msg
	driver_api kprint

	; Make the system sleep for 5 seconds
	mov rax, 5000			; system heartbeat runs at 1000 Hz
	driver_api sleep

	; Restore the previous BGA state
	mov cx, 4
	mov ax, 0
	call bga_write_register

	; Set resolution 800x600x32 (the default system resolution)
	mov cx, 1
	mov ax, 800
	call bga_write_register

	mov cx, 2
	mov ax, 600
	call bga_write_register

	mov cx, 3
	mov ax, 32
	call bga_write_register

	; Enable BGA
	mov cx, 4
	mov ax, 0x41
	call bga_write_register

	mov rsi, done_msg
	driver_api kprint

	driver_api exit_driver

old_bga:
	mov rsi, old_msg
	driver_api kprint

	driver_api exit_driver		; return to the kernel

; bga_write_register:
; Writes a BGA register
; In\	CX = Register
; In\	AX = Value to write
; Out\	Nothing

bga_write_register:
	mov [.value], ax
	mov [.register], cx

	; select the register
	mov dx, 0x1CE
	mov ax, [.register]
	driver_api outportw		; tell the kernel to do OUT DX, AX

	; write the value to the register
	mov dx, 0x1CF
	mov ax, [.value]
	driver_api outportw

	ret

.value			dw 0
.register		dw 0

; bga_read_register:
; Read a BGA register
; In\	CX = Register
; Out\	AX = Value from register

bga_read_register:
	; select the register
	mov dx, 0x1CE
	mov ax, cx
	driver_api outportw		; tell the kernel to do OUT DX, AX

	mov dx, 0x1CF
	driver_api inportw		; IN AX, DX

	ret

starting_msg			db "[test.sys] Test Driver up and running from Userspace!",10,0
no_bga				db "[test.sys] BGA not present, quitting.",10,0
old_msg				db "[test.sys] Old version of BGA present.",10,0
found_msg			db "[test.sys] Found BGA.",10,0
waiting_msg			db "[test.sys] Programmed BGA from userspace; waiting 5 seconds to test PIT also from userspace...",10,0
done_msg			db "[test.sys] Testing driver done!",10,0

end_of_file:


