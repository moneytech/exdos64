
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;						;;
;; Extensible Disk Operating System		;;
;; 64-bit Version				;;
;; (C) 2015-2016 by Omar Mohammad		;;
;; All rights reserved.				;;
;;						;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use64

db "ACPI subsystem",0

;; Functions:
; init_acpi
; acpi_do_rsdp_checksum
; show_acpi_tables
; acpi_do_checksum
; acpi_find_table
; enable_acpi
; acpi_detect_batteries
; acpi_irq
; dsdt_find_object
; acpi_read_gas
; acpi_write_gas
; acpi_sleep
; acpi_shutdown
; shutdown
; acpi_reset
; acpi_run_aml

;; 
;; The first part of this file is basic ACPI routines
;; These include ACPI table functions, ACPI reset and ACPI sleeping code
;; Later in this file is an ACPI Machine Language Virtual Machine
;; 


struc acpi_gas address_space, bit_width, bit_offset, access_size, address
{
	.address_space		db address_space
	.bit_width		db bit_width
	.bit_offset		db bit_offset
	.access_size		db access_size
	.address		dq address
}


rsdp					dq 0
acpi_root				dq 0
acpi_version				db 0
acpi_bst_package			dq 0
acpi_bif_package			dq 0
acpi_sleeping				db 0

acpi_bif:
	.power_unit			dd 0
	.design_capacity		dd 0
	.full_charge_capacity		dd 0
	.battery_technology		dd 0
	.design_voltage			dd 0
	.design_warning			dd 0
	.design_low			dd 0
	.granularity1			dd 0
	.granularity2			dd 0
	.model:				times 16 db 0
	.serial_number:			times 16 db 0
	.battery_type:			times 16 db 0
	.oem_information:		times 16 db 0

acpi_bst:
	.state				dd 0
	.present_state			dd 0
	.remaining_capacity		dd 0
	.present_voltage		dd 0

acpi_battery				db 0		; 0 not present, 1 SBST, 2 standard ACPI AML battery
battery_percentage			dq 0

ACPI_SDT_SIZE				= 36	; size of ACPI SDT header

; init_acpi:
; Initializes the ACPI subsystem

init_acpi:
	mov rsi, .starting_msg
	call kprint

	movzx rsi, word[0x40E]		; there *may* be a real mode segment pointer to the RSD PTR at 0x40E
	shl rsi, 4
	push rsi
	mov rdi, .rsd_ptr
	mov rcx, 8
	rep cmpsb
	je .found_rsdp

	pop rsi

	; first, search the EBDA for the RSDP
	mov rsi, [ebda_base]

.search_ebda_loop:
	push rsi
	mov rdi, .rsd_ptr
	mov rcx, 8
	rep cmpsb
	je .found_rsdp
	pop rsi

	inc rsi
	mov rdi, [ebda_base]
	add rdi, 1024
	cmp rsi, rdi
	jge .search_rom
	jmp .search_ebda_loop

.search_rom:
	mov rsi, 0xE0000

.find_rsdp_loop:
	push rsi
	mov rdi, .rsd_ptr
	mov rcx, 8
	rep cmpsb
	je .found_rsdp
	pop rsi

	add rsi, 0x10
	cmp rsi, 0xFFFFF
	jge .no_acpi
	jmp .find_rsdp_loop

.found_rsdp:
	pop rsi
	mov [rsdp], rsi

	call acpi_do_rsdp_checksum

	mov rsi, [rsdp]
	mov al, [rsi+15]
	inc al
	mov [acpi_version], al

	mov rsi, .found_acpi
	call kprint

	mov rax, [rsdp]
	call hex_dword_to_string
	call kprint

	mov rsi, .found_acpi2
	call kprint

	mov rax, 0
	mov al, [acpi_version]
	call int_to_string
	call kprint

	mov rsi, newline
	call kprint

	cmp [acpi_version], 2
	jl .show_warning
	jmp .show_all_tables

.show_warning:
	mov rsi, .old_acpi_warning
	call kprint
	jmp .show_all_tables

.no_acpi:
	mov rsi, .no_acpi_msg
	call kprint

	mov rsi, .no_acpi_msg
	call boot_error_early

	jmp $

.show_all_tables:
	cmp [acpi_version], 2
	jl .use_rsdt

.use_xsdt:
	mov rsi, [rsdp]
	mov rax, [rsi+24]
	mov [acpi_root], rax

	mov rsi, .found_xsdt
	call kprint
	mov rax, [acpi_root]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint
	jmp .show_tables

.use_rsdt:
	mov rsi, [rsdp]
	mov rax, 0
	mov eax, [rsi+16]
	mov [acpi_root], rax

	mov rsi, .found_rsdt
	call kprint
	mov rax, [acpi_root]
	call hex_dword_to_string
	call kprint
	mov rsi, newline
	call kprint

.show_tables:
	call show_acpi_tables
	ret

.starting_msg			db "[acpi] initializing ACPI...",10,0
.no_acpi_msg			db "[acpi] system doesn't support ACPI...",10,0
.found_acpi			db "[acpi] found RSDP at 0x",0
.found_acpi2			db ", ACPI version ",0
.checksum_error_msg		db "[acpi] checksum error.",10,0
.old_acpi_warning		db "[acpi] warning: ACPI 2.0+ was not found, using 32-bit RSDT instead of XSDT...",10,0
.rsd_ptr			db "RSD PTR "
.found_rsdt			db "[acpi] found RSDT at 0x",0
.found_xsdt			db "[acpi] found XSDT at 0x",0

; acpi_do_rsdp_checksum:
; Does the RSDP checksum

acpi_do_rsdp_checksum:
	; verify the checksum of the first part of the RSDP
	mov rsi, [rsdp]
	mov rdi, rsi
	add rdi, 20
	mov rax, 0
	mov rbx, 0

.rsdp1_loop:
	cmp rsi, rdi
	jge .rsdp1_done
	lodsb
	add bl, al
	jmp .rsdp1_loop

.rsdp1_done:
	cmp bl, 0
	jne .error

	mov rsi, [rsdp]
	cmp byte[rsi+15], 1		; ACPI v2+
	jge .do_rsdp2

	ret

.do_rsdp2:
	mov rsi, [rsdp]
	mov rax, 0
	mov eax, [rsi+20]
	mov rdi, rsi
	add rdi, rax

	mov rax, 0
	mov rbx, 0

.rsdp2_loop:
	cmp rsi, rdi
	jge .rsdp2_done
	lodsb
	add bl, al
	jmp .rsdp2_loop

.rsdp2_done:
	cmp bl, 0
	jne .error

	ret

.error:
	mov rsi, [rsdp]
	mov al, [rsi+8]
	call hex_byte_to_string
	mov rdi, .error_msg2
	movsw

	mov rsi, .error_msg
	call kprint
	mov rsi, .error_msg
	call boot_error_early

	jmp $

.error_msg			db "[acpi] checksum error: table 'RSD PTR ', checksum 0x"
.error_msg2			db "00",10,0

; show_acpi_tables:
; Shows ACPI tables

show_acpi_tables:
	; first, show the XSDT/RSDT
	mov rsi, .prefix
	call kprint

	cmp [acpi_version], 2
	jl .show_rsdt

.show_xsdt:
	mov rsi, .xsdt
	call kprint

	mov rsi, .version
	call kprint

	mov rsi, [acpi_root]
	mov rax, 0
	mov al, [rsi+8]			; version
	call int_to_string
	call kprint

	mov rsi, [acpi_root]
	add rsi, 10
	mov rdi, .oem
	mov rcx, 6
	rep movsb

	mov rsi, .oem_str
	call kprint
	mov rsi, .oem
	call kprint

	mov rsi, .address
	call kprint

	mov rax, [acpi_root]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint

	jmp .start_tables

.show_rsdt:
	mov rsi, .rsdt
	call kprint

	mov rsi, .version
	call kprint

	mov rsi, [acpi_root]
	mov rax, 0
	mov al, [rsi+8]			; version
	call int_to_string
	call kprint

	mov rsi, [acpi_root]
	add rsi, 10
	mov rdi, .oem
	mov rcx, 6
	rep movsb

	mov rsi, .oem_str
	call kprint
	mov rsi, .oem
	call kprint

	mov rsi, .address
	call kprint

	mov rax, [acpi_root]
	call hex_qword_to_string
	call kprint
	mov rsi, newline
	call kprint

.start_tables:
	mov rsi, [acpi_root]
	add rsi, ACPI_SDT_SIZE
	mov [.root], rsi

	mov rsi, [acpi_root]
	mov rax, 0
	mov eax, [rsi+4]
	mov [.end_root], rax
	mov rax, [acpi_root]
	add [.end_root], rax

	cmp [acpi_version], 2
	jl .use_rsdt

.use_xsdt:
	mov rsi, [.root]
	cmp rsi, [.end_root]
	jge .done
	add [.root], 8

	mov rax, [rsi]
	mov [.table], rax
	jmp .parse_table

.use_rsdt:
	mov rsi, [.root]
	cmp rsi, [.end_root]
	jge .done
	add [.root], 4

	mov rax, 0
	mov eax, [rsi]
	mov [.table], rax

.parse_table:
	mov rsi, [.table]
	mov rdi, .signature
	mov rcx, 4
	rep movsb

	mov rsi, .prefix
	call kprint

	mov rsi, .signature
	call kprint

	mov rsi, .version
	call kprint

	mov rsi, [.table]
	mov rax, 0
	mov al, [rsi+8]
	call int_to_string
	call kprint

	mov rsi, .oem_str
	call kprint

	mov rsi, [.table]
	add rsi, 10
	mov rdi, .oem
	mov rcx, 6
	rep movsb

	mov rsi, .oem
	call kprint

	mov rsi, .address
	call kprint

	mov rax, [.table]
	call hex_qword_to_string
	call kprint

	mov rsi, newline
	call kprint

	cmp [acpi_version], 2
	jl .use_rsdt

	jmp .use_xsdt

.done:
	ret

.prefix				db "[acpi] ",0
.xsdt				db "XSDT",0
.rsdt				db "RSDT",0
.version			db " version ",0
.oem_str			db " OEM '",0
.address			db "' address 0x",0
.oem:				times 7 db 0
.table				dq 0
.root				dq 0
.end_root			dq 0
.signature:			times 5 db 0

; acpi_do_checksum:
; Does a checksum on an ACPI table
; In\	RSI = Address of table
; Out\	RFLAGS.CF = 0 on success

acpi_do_checksum:
	mov [.table], rsi
	mov rax, 0
	mov eax, [rsi+4]
	add rsi, rax
	mov [.end_table], rsi

	; now add all the bytes in the table
	mov rsi, [.table]
	mov rax, 0
	mov rbx, 0

.loop:
	cmp rsi, [.end_table]
	jge .done
	lodsb
	add bl, al
	jmp .loop

.done:
	cmp bl, 0
	je .yes

.no:
	mov rsi, .error_msg
	call kprint
	mov rsi, [.table]
	mov rdi, .signature
	movsd
	mov rsi, .signature
	call kprint
	mov rsi, .error_msg2
	call kprint
	mov rsi, [.table]
	mov al, [rsi+9]
	call hex_byte_to_string
	call kprint
	mov rsi, newline
	call kprint

	stc
	ret

.yes:
	clc
	ret

.table				dq 0
.end_table			dq 0
.signature:			times 5 db 0
.error_msg			db "[acpi] checksum error: table '",0
.error_msg2			db "', checksum 0x",0

; acpi_find_table:
; Returns address of an ACPI table
; In\	RSI = Signature
; Out\	RSI = Table address (0 if not found)

acpi_find_table:
	mov rdi, .signature
	mov rcx, 4
	rep movsb

	mov rax, [acpi_root]
	add rax, ACPI_SDT_SIZE
	mov [.root], rax

	mov rsi, [acpi_root]
	mov rax, 0
	mov eax, [rsi+4]
	add rsi, rax
	mov [.end_root], rsi

	cmp [acpi_version], 2
	jl .use_rsdt

.use_xsdt:
	mov rax, [.root]
	cmp rax, [.end_root]
	jge .no_table
	mov rsi, [rax]
	add [.root], 8
	jmp .check_table

.use_rsdt:
	mov rax, [.root]
	cmp rax, [.end_root]
	jge .no_table
	mov rsi, 0
	mov esi, [rax]
	add [.root], 4

.check_table:
	mov rdi, .signature
	mov rcx, 4
	rep cmpsb
	je .found_table

	cmp [acpi_version], 2
	jl .use_rsdt
	jmp .use_xsdt

.found_table:
	sub rsi, 4
	mov [.table], rsi

	; verify the table's checksum
	mov rsi, [.table]
	call acpi_do_checksum
	jc .no_table

	mov rsi, [.table]
	ret

.no_table:
	mov rsi, 0
	ret

.signature:			times 4 db 0
.root				dq 0
.end_root			dq 0
.table				dq 0

; enable_acpi:
; Enables ACPI hardware mode

enable_acpi:
	mov rsi, .facp
	call acpi_find_table
	cmp rsi, 0
	je .no_fadt

	mov rdi, acpi_fadt
	mov rcx, acpi_fadt_size
	rep movsb

	; install ACPI IRQ handler
	mov rsi, .irq_msg
	call kprint
	movzx rax, [acpi_fadt.sci_interrupt]
	call int_to_string
	call kprint
	mov rsi, newline
	call kprint

	mov ax, [acpi_fadt.sci_interrupt]
	mov rbp, acpi_irq
	call install_irq

	mov rsi, .acpi_event
	call kprint
	movzx rax, [acpi_fadt.pm1_event_length]
	shr rax, 1
	call int_to_string
	call kprint
	mov rsi, .acpi_event2
	call kprint

	mov rsi, .starting_msg
	call kprint

	mov edx, [acpi_fadt.pm1a_control_block]
	in ax, dx
	test ax, 1			; if ACPI is enabled --
	jnz .already_enabled		; -- we don't need to do anything with the SMI command IO port

	cmp [acpi_fadt.smi_command_port], 0
	je .no_smi

	mov edx, [acpi_fadt.smi_command_port]
	mov al, [acpi_fadt.acpi_enable]
	out dx, al		; enable ACPI

	call iowait		; give the hardware some time to change into ACPI mode

	mov al, 0
	out 0x70, al
	call iowait
	in al, 0x71
	mov [.cmos_sec], al

.wait_for_enable:
	mov edx, [acpi_fadt.pm1a_control_block]
	in ax, dx
	test ax, 1			; now poll the ACPI status...
	jnz .done_enabled

	mov al, 0
	out 0x70, al
	call iowait
	in al, 0x71
	cmp al, [.cmos_sec]
	jg .enable_error
	jmp .wait_for_enable

.already_enabled:
	mov rsi, .already_msg
	call kprint

	ret

.done_enabled:
	mov rsi, .done_msg
	call kprint

	ret

.no_smi:
	mov rsi, .no_smi_msg
	call kprint

	mov rsi, .no_smi_msg
	call boot_error_early

	jmp $

.enable_error:
	mov rsi, .enable_error_msg
	call kprint

	mov rsi, .enable_error_msg
	call boot_error_early

	jmp $

.no_fadt:
	mov rsi, .no_fadt_msg
	call kprint
	mov rsi, .no_fadt_msg
	call boot_error_early

	ret	

.facp				db "FACP"
.starting_msg			db "[acpi] enabling ACPI hardware mode...",10,0
.already_msg			db "[acpi] system is already in ACPI mode.",10,0
.done_msg			db "[acpi] system is now in ACPI mode.",10,0
.irq_msg			db "[acpi] ACPI using IRQ ",0
.no_fadt_msg			db "[acpi] FACP table is not present or corrupt, will not be able to manage power.",10,0
.acpi_event			db "[acpi] ACPI event register size is ",0
.acpi_event2			db " bytes.",10,0
.enable_error_msg		db "[acpi] ACPI hardware is not responding.",10,0
.no_smi_msg			db "[acpi] ACPI is not enabled and SMI command port is not present.",10,0
.cmos_sec			db 0

ACPI_EVENT_TIMER		= 1
ACPI_EVENT_BUSMASTER		= 0x10
ACPI_EVENT_GBL			= 0x20
ACPI_EVENT_POWERBUTTON		= 0x100
ACPI_EVENT_SLEEPBUTTON		= 0x200
ACPI_EVENT_RTC			= 0x400
ACPI_EVENT_PCIE_WAKE		= 0x4000
ACPI_EVENT_WAKE			= 0x8000

; acpi_irq:
; ACPI IRQ handler

acpi_irq:
	pushaq

	mov rsi, .msg
	call kprint

	mov rdx, 0
	mov edx, [acpi_fadt.pm1a_event_block]
	in ax, dx

	mov [.event], rax
	call hex_word_to_string
	call kprint

	mov rsi, newline
	call kprint

	mov rax, [.event]
	test rax, ACPI_EVENT_POWERBUTTON	; if the power button is pressed, shut down
	jnz shutdown

.end:
	call send_eoi
	popaq
	iretq

.msg				db "[acpi] SCI interrupt; event block data is: 0x",0
.event				dq 0

; acpi_detect_batteries:
; Detects ACPI-compatible batteries

acpi_detect_batteries:
	; This is stubbed for now, will be done when I have an AML interpreter ..
	ret

; dsdt_find_object:
; Finds an object within the ACPI DSDT
; In\	RSI = Object name
; Out\	RSI = Pointer to object, 0 on error

dsdt_find_object:
	pushaq
	mov [.object], rsi

	mov rax, 0
	mov eax, [acpi_fadt.dsdt]
	mov [.dsdt], rax
	mov [.end_dsdt], rax
	mov rax, 0x100000
	add [.end_dsdt], rax

	mov rax, [.dsdt]
	and eax, 0xFFE00000
	mov rbx, rax
	mov rcx, 4
	mov dl, 3
	call vmm_map_memory

	mov rsi, [.object]
	call get_string_size
	mov [.size], rax

	mov rsi, [.dsdt]
	add rsi, ACPI_SDT_SIZE
	mov rdi, [.object]

.loop:
	cmp rsi, [.end_dsdt]
	jge .no
	pushaq
	mov rcx, [.size]
	rep cmpsb
	je .found
	popaq
	inc rsi
	jmp .loop

.found:
	popaq
	mov [.object], rsi
	popaq
	mov rsi, [.object]
	ret

.no:
	popaq
	mov rsi, 0
	ret

.size				dq 0
.dsdt				dq 0
.end_dsdt			dq 0
.object				dq 0

; acpi_read_gas:
; Reads from an ACPI Generic Address Structure
; In\	RDX = Pointer to Generic Address Structure
; Out\	RAX = Data from GAS, -1 on error

acpi_read_gas:
	cmp byte[rdx], 0
	je .mem

	cmp byte[rdx], 1
	je .io

	;cmp byte[rdx], 2	; not yet implemented
	;je .pci

.bad:
	mov rax, -1
	ret

.mem:
	cmp byte[rdx+3], 0
	je .bad
	cmp byte[rdx+3], 1
	je .mem_byte
	cmp byte[rdx+3], 2
	je .mem_word
	cmp byte[rdx+3], 3
	je .mem_dword
	cmp byte[rdx+3], 4
	je .mem_qword
	jmp .bad

.mem_byte:
	mov rdx, [rdx+4]
	movzx rax, byte[rdx]
	ret

.mem_word:
	mov rdx, [rdx+4]
	movzx rax, word[rdx]
	ret

.mem_dword:
	mov rdx, [rdx+4]
	mov rax, 0
	mov eax, [rdx]
	ret

.mem_qword:
	mov rdx, [rdx+4]
	mov rax, [rdx]
	ret

.io:
	mov rax, 0
	cmp byte[rdx+3], 0
	je .bad
	cmp byte[rdx+3], 1
	je .io_byte
	cmp byte[rdx+3], 2
	je .io_word
	cmp byte[rdx+3], 3
	je .io_dword
	jmp .bad

.io_byte:
	mov rdx, [rdx+4]
	in al, dx
	ret

.io_word:
	mov rdx, [rdx+4]
	in ax, dx
	ret

.io_dword:
	mov rdx, [rdx+4]
	in eax, dx
	ret

; acpi_write_gas:
; Writes to an ACPI Generic Address Structure
; In\	RDX = Pointer to Generic Address Structure
; In\	RAX = Data to write
; Out\	RAX = -1 on success

acpi_write_gas:
	mov [.data], rax

	cmp byte[rdx], 0
	je .mem

	cmp byte[rdx], 1
	je .io

	;cmp byte[rdx], 2	; not yet implemented
	;je .pci

.bad:
	mov rax, -1
	ret

.mem:
	cmp byte[rdx+3], 0
	je .bad
	cmp byte[rdx+3], 1
	je .mem_byte
	cmp byte[rdx+3], 2
	je .mem_word
	cmp byte[rdx+3], 3
	je .mem_dword
	cmp byte[rdx+3], 4
	je .mem_qword
	jmp .bad

.mem_byte:
	mov rdx, [rdx+4]
	mov rax, [.data]
	mov [rdx], al
	wbinvd
	ret

.mem_word:
	mov rdx, [rdx+4]
	mov rax, [.data]
	mov [rdx], ax
	wbinvd
	ret

.mem_dword:
	mov rdx, [rdx+4]
	mov rax, [.data]
	mov [rdx], eax
	wbinvd
	ret

.mem_qword:
	mov rdx, [rdx+4]
	mov rax, [.data]
	mov [rdx], rax
	wbinvd
	ret

.io:
	mov rax, [.data]
	cmp byte[rdx+3], 0
	je .bad
	cmp byte[rdx+3], 1
	je .io_byte
	cmp byte[rdx+3], 2
	je .io_word
	cmp byte[rdx+3], 3
	je .io_dword
	jmp .bad

.io_byte:
	mov rdx, [rdx+4]
	out dx, al
	call iowait
	ret

.io_word:
	mov rdx, [rdx+4]
	out dx, ax
	call iowait
	ret

.io_dword:
	mov rdx, [rdx+4]
	out dx, eax
	call iowait
	ret

.data				dq 0

; acpi_sleep:
; Sets an ACPI sleep state
; In\	AL = Sleep state
; Out\	Nothing

acpi_sleep:
	pushaq
	mov [.sleep_state], al

	mov rsi, .starting_msg
	call kprint
	movzx rax, [.sleep_state]
	call int_to_string
	call kprint
	mov rsi, .starting_msg2
	call kprint

	mov al, [.sleep_state]
	add al, '0'
	mov byte[.sx_object+2], al

	mov rsi, .sx_object
	call dsdt_find_object
	cmp rsi, 0
	je .fail
	mov [.sx], rsi

	mov rsi, [.sx]
	add rsi, 7

.do_a:
	lodsb
	cmp al, AML_OPCODE_BYTEPREFIX		; AML byteprefix
	je .byteprefix_a
	mov [.sleep_type_a], al

	jmp .do_b

.byteprefix_a:
	lodsb
	mov [.sleep_type_a], al

.do_b:
	lodsb
	cmp al, AML_OPCODE_BYTEPREFIX
	je .byteprefix_b
	mov [.sleep_type_b], al

	jmp .start_sleeping

.byteprefix_b:
	lodsb
	mov [.sleep_type_b], al

.start_sleeping:
	call disable_interrupts		; prevent interrupts happening at the wrong time
	mov [acpi_sleeping], 1
	mov edx, [acpi_fadt.pm1a_control_block]
	in ax, dx
	movzx bx, [.sleep_type_a]
	and bx, 7
	shl bx, 10
	and ax, 0xE3FF
	or ax, bx
	or ax, 0x2000			; enable sleep
	out dx, ax

	mov edx, [acpi_fadt.pm1b_control_block]
	cmp edx, 0
	je .done
	in ax, dx
	movzx bx, [.sleep_type_b]
	and bx, 7
	shl bx, 10
	and ax, 0xE3FF
	or ax, bx
	or ax, 0x2000
	out dx, ax
	call iowait

.done:
	call iowait
	call iowait

	mov [acpi_sleeping], 0
	popaq
	ret

.fail:
	mov [acpi_sleeping], 0
	mov rsi, .fail_msg
	call kprint
	popaq
	ret

.sleep_state			db 0
.starting_msg			db "[acpi] entering sleep state S",0
.starting_msg2			db "...",10,0
.sx_object			db "_Sx_",0x12,0
.fail_msg			db "[acpi] warning: error while entering sleep state.",10,0
.sx				dq 0
.dsdt				dq 0
.end_dsdt			dq 0
.sleep_type_a			db 0
.sleep_type_b			db 0

; acpi_shutdown:
; Shuts down the system using ACPI

acpi_shutdown:
	mov rsi, .starting_msg
	call kprint

	mov al, 5		; ACPI sleep state S5
	call acpi_sleep

	mov rsi, .fail_msg
	call kprint

	ret

.starting_msg			db "[acpi] attempting ACPI shutdown...",10,0
.fail_msg			db "[acpi] warning: failed to shut down!",10,0

; acpi_reset:
; Resets the system

acpi_reset:
	mov rsi, .starting_msg
	call kprint

	call disable_interrupts

	cmp [acpi_fadt.revision], 2		; only exists in version 2+ of the FADT
	jl .bad
	test [acpi_fadt.flags], 0x400		; reset register is an optional feature -- make sure it's supported
	jz .bad

	; simply write to the reset register
	movzx rax, [acpi_reset_value]
	mov rdx, acpi_fadt.reset_register
	call acpi_write_gas

.bad:
	mov rsi, .fail_msg
	call kprint

	mov al, 0xFE		; try ps/2 method
	out 0x64, al

	mov al, 3		; still not? try quick reset method
	out 0x92, al

	; If still not reset, triple fault the CPU
	lidt [.idtr]
	int 0
	hlt

.idtr:				dw 0
				dq 0
.starting_msg			db "[acpi] attempting ACPI reset...",10,0
.fail_msg			db "[acpi] warning: failed, falling back to traditional reset...",10,0

; shutdown:
; Shuts down the PC

shutdown:
	mov ax, 0x30
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax

	call wm_kill_all			; destroy all windows

	mov rax, [vbe_screen.width]
	mov rbx, [vbe_screen.height]
	shr rax, 1
	shr rbx, 1

	sub rax, 175
	sub rbx, 64

	; TO-DO: Make this window say "It's now safe to power off your PC."
	mov si, 350
	mov di, 128
	mov r10, .win_title
	mov rdx, .event
	call wm_create_window

	call acpi_shutdown
	call send_eoi		; send the EOI of ACPI's SCI IRQ -- let mouse and keyboard IRQs happen
				; so that users can drag around the "It's now safe to power off your PC." window.

.hang:
	sti
	jmp .hang

.event:
	ret

.win_title			db "System",0
.win_msg			db "It's now safe to power off your PC.",0

align 16
acpi_fadt:
	; ACPI SDT header
	.signature		rb 4
	.length			rd 1
	.revision		rb 1
	.checksum		rb 1
	.oemid			rb 6
	.oem_table_id		rb 8
	.oem_revision		rd 1
	.creator_id		rd 1
	.creator_revision	rd 1

	; FADT table itself
	.firmware_control	rd 1
	.dsdt			rd 1
	.reserved		rb 1

	.preffered_profile	rb 1
	.sci_interrupt		rw 1
	.smi_command_port	rd 1
	.acpi_enable		rb 1
	.acpi_disable		rb 1
	.s4bios_req		rb 1
	.pstate_control		rb 1
	.pm1a_event_block	rd 1
	.pm1b_event_block	rd 1
	.pm1a_control_block	rd 1
	.pm1b_control_block	rd 1
	.pm2_control_block	rd 1
	.pm_timer_block		rd 1
	.gpe0_block		rd 1
	.gpe1_block		rd 1
	.pm1_event_length	rb 1
	.pm1_control_length	rb 1
	.pm2_control_length	rb 1
	.pm_timer_length	rb 1
	.gpe0_length		rb 1
	.gpe1_length		rb 1
	.gpe1_base		rb 1
	.cstate_control		rb 1
	.worst_c2_latency	rw 1
	.worst_c3_latency	rw 1
	.flush_size		rw 1
	.flush_stride		rw 1
	.duty_offset		rb 1
	.duty_width		rb 1
	.day_alarm		rb 1
	.month_alarm		rb 1
	.century		rb 1

	.boot_arch_flags	rw 1
	.reserved2		rb 1
	.flags			rd 1

	.reset_register:	some acpi_gas 0,0,0,0,0

	acpi_reset_value	rb 1

end_of_acpi_fadt:
acpi_fadt_size			= end_of_acpi_fadt - acpi_fadt


;; 
;; This part of the file is the core of ACPI Machine Language Virtual Machine
;; It is in very early stages of development and may cause undefined opcode errors on real hardware 
;; 

; acpi_run_aml:
; Runs ACPI AML code
; In\	RAX = Address of AML code
; Out\	RAX = Information returned by code, -1 if none

acpi_run_aml:
	mov [.original_stack], rsp	; save the stack
	mov [.threads], 0

.aml_execute:
	inc [.threads]

	mov rsi, rax
	add rsi, 5

.execute_loop:
	push rsi

	cmp byte[rsi], AML_OPCODE_ZERO
	je aml_noop

	cmp byte[rsi], AML_OPCODE_ONE
	je aml_noop

	cmp byte[rsi], AML_OPCODE_ONES
	je aml_noop

	cmp byte[rsi], AML_OPCODE_NAME
	je aml_name

	cmp byte[rsi], AML_OPCODE_PACKAGE
	je aml_package

	cmp byte[rsi], AML_OPCODE_RETURN
	je aml_return

	jmp aml_opcode_error


.threads			dq 0
.original_stack			dq 0

;; 
;; AML INTERPRETER CORE
;;

aml_opcode_error:
	mov rsi, .msg
	call kprint

	pop rsi
	mov al, [rsi]
	call hex_byte_to_string
	call kprint

	mov rsi, .msg2
	call kprint

	mov rax, -1
	mov rsp, [acpi_run_aml.original_stack]
	ret	

.msg				db "[acpi] undefined opcode 0x",0
.msg2				db ", aborting...",10,0

aml_noop:
	pop rsi
	inc rsi
	jmp acpi_run_aml.execute_loop

aml_name:
	pop rsi
	add rsi, 5		; all names are 4 bytes, and add 1 byte for the name prefix
	jmp acpi_run_aml.execute_loop

aml_return:
	pop rsi
	inc rsi

	cmp byte[rsi], AML_OPCODE_ZERO
	je .zero

	cmp byte[rsi], AML_OPCODE_ONE
	je .one

	cmp byte[rsi], AML_OPCODE_ONES
	je .ones

	cmp byte[rsi], AML_OPCODE_BYTEPREFIX
	je .byte

	cmp byte[rsi], AML_OPCODE_WORDPREFIX
	je .word

	cmp byte[rsi], AML_OPCODE_DWORDPREFIX
	je .dword

	cmp byte[rsi], AML_OPCODE_QWORDPREFIX
	je .qword

	; assume it's returning another method...
	

.zero:
	mov rax, 0
	mov rsp, [acpi_run_aml.original_stack]
	ret

.one:
	mov rax, 0
	mov rsp, [acpi_run_aml.original_stack]
	ret

.ones:
	mov rax, 0xFF
	mov rsp, [acpi_run_aml.original_stack]
	ret

.byte:
	movzx rax, byte[rsi+1]
	mov rsp, [acpi_run_aml.original_stack]
	ret

.word:
	movzx rax, word[rsi+1]
	mov rsp, [acpi_run_aml.original_stack]
	ret

.dword:
	mov rax, 0
	mov eax, [rsi+1]
	mov rsp, [acpi_run_aml.original_stack]
	ret

.qword:
	mov rax, [rsi+1]
	mov rsp, [acpi_run_aml.original_stack]
	ret

aml_package:
	pop rsi
	add rsi, 2
	movzx rax, byte[rsi]		; package size
	mov [.package_size], rax
	mov [.current_size], 0

	inc rsi

.parse_package:
	mov rax, [.package_size]
	cmp [.current_size], rax
	jge .done

	cmp byte[rsi], AML_OPCODE_BYTEPREFIX
	je .byte

	cmp byte[rsi], AML_OPCODE_WORDPREFIX
	je .word

	cmp byte[rsi], AML_OPCODE_DWORDPREFIX
	je .dword

	cmp byte[rsi], AML_OPCODE_QWORDPREFIX
	je .qword

	cmp byte[rsi], AML_OPCODE_STRINGPREFIX
	je .string

	; for ZERO, ONE and ONES, which don't take prefixes
	inc rsi
	inc [.current_size]
	jmp .parse_package

.byte:
	add rsi, 2
	inc [.current_size]
	jmp .parse_package

.word:
	add rsi, 3
	inc [.current_size]
	jmp .parse_package

.dword:
	add rsi, 5
	inc [.current_size]
	jmp .parse_package

.qword:
	add rsi, 9
	inc [.current_size]
	jmp .parse_package

.string:
	inc rsi
	push rsi
	call get_string_size
	pop rsi
	add rsi,rax
	inc rsi
	inc [.current_size]
	jmp .parse_package

.done:
	jmp acpi_run_aml.execute_loop

.package_size			dq 0
.current_size			dq 0

;;
;; AML OPCODE LOOKUP
;;

AML_OPCODE_ZERO			= 0x00
AML_OPCODE_ONE			= 0x01
AML_OPCODE_ALIAS		= 0x06
AML_OPCODE_NAME			= 0x08
AML_OPCODE_BYTEPREFIX		= 0x0A
AML_OPCODE_WORDPREFIX		= 0x0B
AML_OPCODE_DWORDPREFIX		= 0x0C
AML_OPCODE_STRINGPREFIX		= 0x0D
AML_OPCODE_QWORDPREFIX		= 0x0E

AML_OPCODE_PACKAGE		= 0x12
AML_OPCODE_RETURN		= 0xA4
AML_OPCODE_ONES			= 0xFF




