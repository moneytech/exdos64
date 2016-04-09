
;;
;; Macros for calling driver functions
;;

exit_driver			= 0x00
kprint				= 0x01
outportb			= 0x02
outportw			= 0x03
outportd			= 0x04
inportb				= 0x05
inportw				= 0x06
inportd				= 0x07
pci_read_dword			= 0x08
pci_write_dword			= 0x09
pci_get_device_class		= 0x0A
pci_get_device_vendor		= 0x0B
pci_get_buses			= 0x0C
kmalloc				= 0x0D
kfree				= 0x0E
hex_byte_to_string		= 0x0F
hex_word_to_string		= 0x10
hex_dword_to_string		= 0x11
hex_qword_to_string		= 0x12
sleep				= 0x13
install_driver_irq		= 0x14	; just stub, doesn't work
read_sectors			= 0x15
write_sectors			= 0x16	; just stub, doesn't work
open				= 0x17
close				= 0x18
seek				= 0x19
read				= 0x1A
write				= 0x1B	; just stub, doesn't work
register_driver			= 0x1C	; just stub, doesn't work
vmm_get_physical_address	= 0x1D

macro driver_api function {
	mov r15, function
	syscall
}



