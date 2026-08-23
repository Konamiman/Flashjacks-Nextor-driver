	; Device-based driver for the FLASHJACKS SD interface for Nextor
	;
	; By Aquijacks v3.0.1 2026

	; Nestor80 / Nextor 3 includes
	INCLUDE asm/macros/undoc.inc
	INCLUDE asm/constants/driver_result_codes.inc

	module DRIVER_QUERY
	INCLUDE asm/constants/driver_driver_queries.inc
	endmod

	module DEVICE_QUERY
	INCLUDE asm/constants/driver_device_queries.inc
	endmod

	org		4000h

	ds		256, 0FFh		; 256 dummy bytes


DRV_START:

TESTADD	equ	0F3F5h

;-----------------------------------------------------------------------------
;
; Driver configuration constants
;

DEBUG		equ	0	;Set to 1 for debugging, 0 to normal operation

;Driver version

VER_MAIN	equ	3
VER_SEC		equ	0
VER_REV		equ	1

;This is a very barebones driver. It has important limitations:
;- CHS mode not supported, disks must support LBA mode.
;- 48 bit addresses are not supported
;  (do the Sunrise IDE hardware support them anyway?)
;- ATAPI devices not supported, only ATA disks.


;-----------------------------------------------------------------------------
;
; IDE registers and bit definitions

IDE_BANK	equ	4104h	;bit 0: enable (1) or disable (0) IDE registers
				;bits 5-7: select 16K ROM bank
IDE_DATA	equ	7C00h	;Data registers, this is a 512 byte area
IDE_ERROR	equ	7E01h	;Error register
IDE_FEAT	equ	7E01h	;Feature register
IDE_SECCNT	equ	7E02h	;Sector count
IDE_SECNUM	equ	7E03h	;Sector number (CHS mode)
IDE_LBALOW	equ	7E03h	;Logical sector low (LBA mode)
IDE_CYLOW	equ	7E04h	;Cylinder low (CHS mode)
IDE_LBAMID	equ	7E04h	;Logical sector mid (LBA mode)
IDE_CYHIGH	equ	7E05h	;Cylinder high (CHS mode)
IDE_LBAHIGH	equ	7E05h	;Logical sector high (LBA mode)
IDE_HEAD	equ	7E06h	;bits 0-3: Head (CHS mode), logical sector higher (LBA mode)
IDE_STATUS	equ	7E07h	;Status register
IDE_CMD		equ	7E07h	;Command register
IDE_FLASHJACKS	equ	7E09h	;FlashJacks register
IDE_IDIOMA	equ	7E0Ah	;Selected language
IDE_RAM1	equ	7E0Bh	;Free-use RAM byte 1
IDE_RAM2	equ	7E0Ch	;Free-use RAM byte 2
IDE_DEVCTRL	equ	7E0Eh	;Device control register

; Bits in the error register

WP	equ	6	;Write protected
MC	equ	5	;Media Changed
IDNF	equ	4	;ID Not Found
MCR	equ	3	;Media Change Requested
ABRT	equ	2	;Aborted Command
NM	equ	1	;No media

; Bits in the head register

DEV	equ	4	;Device select: 0=master, 1=slave
LBA	equ	6	;0=use CHS mode, 1=use LBA mode

M_DEV	equ	(1 SHL DEV)
M_LBA	equ	(1 SHL LBA)

; Bits in the status register

BSY	equ	7	;Busy
DRDY	equ	6	;Device ready
DF	equ	5	;Device fault
DRQ	equ	3	;Data request
ERR	equ	0	;Error

M_BSY	equ	(1 SHL BSY)
M_DRDY	equ	(1 SHL DRDY)
M_DF	equ	(1 SHL DF)
M_DRQ	equ	(1 SHL DRQ)
M_ERR	equ	(1 SHL ERR)

; Bits in the device control register register

SRST	equ	2	;Software reset

M_SRST	equ	(1 SHL SRST)

; Routine to Bypass the HB-F1, HB-F1II and HB-F9P/S Firmware

H_STKE	equ	0FEDAh
H_TIMI	equ	0FD9Fh
RDSLT	equ	0000Ch		; Read a byte in a slot
WRSLT	equ	00014h		; Write a byte in a slot

;-----------------------------------------------------------------------------
;
; Standard BIOS and work area entries

; CHPUT is provided by DRIVER_CHPUT below
CHGET	equ	009Fh
CLS	equ	00C3h
MSXVER	equ	002Dh

;-----------------------------------------------------------------------------
;
; Keyboard interception variables.

; CRITICAL MEMORY ADDRESSES:
NEWKEY      equ  0FBE5h  ; Current keyboard matrix (11 bytes)
OLDKEY      equ  0FBF0h  ; Previous keyboard matrix (11 bytes - KEYBUF in BIOS)
KEYBUF      equ  0FBF0h  ; Circular keyboard buffer (40 bytes)
PUTPNT      equ  0F3F8h  ; Buffer write pointer
GETPNT      equ  0F3FAh  ; Buffer read pointer
COUNTER_REP equ  0FD9Eh  ; Keyboard repeat counter. Stored in RAM. It's the last byte of H.KEYI. I don't think it's ever used.
REPCNT      equ  0F3F7h  ; Interval until repeat (BIOS)

; CONFIGURATION CONSTANTS
DELAY_INICIAL   equ  18  ; Initial delay before repeat (300ms @ 60Hz)
INTERVALO_REP   equ  2   ; Interval between repeats (33ms @ 60Hz)

; Bit masks to identify modifier keys
; Row 6: F3,F2,F1,CODE,CAPS,GRAPH,CTRL,SHIFT (bits 0-4)
MASK_MODIFIERS  equ  00010111b  ; Bits 0-4 are modifiers

; ============================================================================
; MSX SYSTEM CONSTANTS FOR SHADOWING
; ============================================================================
PSLOT_PORT      EQU     0A8H    ; Primary slot selection register port
ENASLT          EQU     0024H   ; BIOS: enable slot in a specific page
EXPTBL          EQU     0FCC1H  ; Expanded slots table (8 bytes)
SLTTBL          EQU     0FCC5H  ; Secondary slots table (4 bytes)
SLOT_PRIMARY    EQU     00H     ; Slot 0 (BIOS ROM)
SLOT_RAM        EQU     03H     ; Slot 3 (Internal RAM - MSX assumption)
START_ADDRESS   EQU     0000H   ; Start of BIOS (0000h)
BIOS_SIZE       EQU     4000H   ; Full 16 KB of BIOS (16384 bytes)

; ============================================================================
; RAM VARIABLES FOR SHADOW BIOS (from 0F5D0H onward)
; ============================================================================
SHADOW_SAVED_SLOTS  EQU 0F5D0H  ; 1 byte: original configuration of port A8h
SHADOW_BIOS_SLOT    EQU 0F5D1H  ; 1 byte: slot ID of the BIOS ROM
SHADOW_RAM_SLOT     EQU 0F5D2H  ; 1 byte: slot ID of the destination RAM
SHADOW_SUCCESS      EQU 0F5D3H  ; 1 byte: success flag (1=OK, 0=Error)
SHADOW_PATCH_COUNT  EQU 0F5D4H  ; 1 byte: counter of applied patches (debug)


;-----------------------------------------------------------------------------
; Macros:

;-----------------------------------------------------------------------------
;
; Copies from HL to DE and increments both pointers.
; Memory copy.
ldi_1 macro
	;ld a,(hl)
	;ld (de),a
	;inc hl
	;inc de
	ldi
endm

ldi_10 macro
	ldi_1
	ldi_1
	ldi_1
	ldi_1
	ldi_1
	ldi_1
	ldi_1
	ldi_1
	ldi_1
	ldi_1
endm

ldi_100 macro
	ldi_10
	ldi_10
	ldi_10
	ldi_10
	ldi_10
	ldi_10
	ldi_10
	ldi_10
	ldi_10
	ldi_10
endm

ldi_512 macro
	ldi_100
	ldi_100
	ldi_100
	ldi_100
	ldi_100
	ldi_10
	ldi_1
	ldi_1
endm

;-----------------------------------------------------------------------------
;
; End of macros.
;
;------------------------------------------------------------------------------

;-----------------------------------------------------------------------------
;
; Work area definition
;
;+0: Device and logical units types for master device
;    bits 0,1: Device type
;              00: No device connected
;              01: ATA hard disk, CHS only
;              10: ATA hard disk, LBA supported
;              11: ATAPI device
;    bits 2,3: Device type for LUN 1 on master device
;              00: Block device
;              01: Other, non removable
;              10: CD-ROM
;              11: Other, removable
;    bits 4,5: Device type for LUN 2 on master device
;    bits 6,7: Device type for LUN 3 on master device
;
;+1: Logical unit types for master device
;    bits 0,1: Device type for LUN 4 on master device
;    bits 2,3: Device type for LUN 5 on master device
;    bits 4,5: Device type for LUN 6 on master device
;    bits 6,7: Device type for LUN 7 on master device
;
;+2,3: Reserved for CHS data for the master device (to be implemented)
;
;+4..+7: Same as +0..+3, for the slave device
;
; Note: Actually, due to driver limitations, currently only the
; "device type" bits are used, and with possible values 00 and 10 only.
; LUN type bits are always 00.


;-----------------------------------------------------------------------------
;
; V3 page-3 work area: preserve the original first 8 bytes and add a
; 65-byte scratch buffer used to adapt the old DEV_INFO strings to the
; length-limited Nextor v3 DEVICE_QUERY GET_STRING interface.
WRKAREA_STRBUFF	equ	8
WRKAREA_SIZE	equ	WRKAREA_STRBUFF+65

; Error codes for DEV_RW and DEV_FORMAT
;

NCOMP	equ	0FFh
WRERR	equ	0FEh
DISK	equ	0FDh
NRDY	equ	0FCh
DATA	equ	0FAh
RNF	equ	0F9h
WPROT	equ	0F8h
UFORM	equ	0F7h
SEEK	equ	0F3h
IFORM	equ	0F0h
IDEVL	equ	0B5h
IPARM	equ	08Bh

;-----------------------------------------------------------------------------
;
; Routines available on kernel page 0
;

;* Get in A the current slot for page 1. Corrupts F.
;  Must be called by using CALBNK to bank 0:
;  xor a
;  ld ix,GSLOT1
;  call CALBNK

GSLOT1	equ	402Dh


;* This routine reads a byte from another bank.
;  Must be called by using CALBNK to the desired bank,
;  passing the address to be read in HL:
;  ld a,bank
;  ld hl,address
;  ld ix,RDBANK
;  call CALBNK

RDBANK	equ	403Ch


;* This routine temporarily switches kernel bank 0/3,
;  then jumps to CALBAS in MSX BIOS.
;  This is necessary so that kernel bank is correct in case of BASIC error.

CALBAS	equ	403Fh


;* Call a routine in another bank.
;  Must be used if the driver spawns across more than one bank.
;  Input: A = bank
;         IX = routine address
;         AF' = AF for the routine
;         BC, DE, HL, IY = input for the routine

CALBNK	equ	4042h


;* Get in IX the address of the SLTWRK entry for the slot passed in A,
;  which will in turn contain a pointer to the allocated page 3
;  work area for that slot (0 if no work area was allocated).
;  If A=0, then it uses the slot currently switched in page 1.
;  Returns A=current slot for page 1, if A=0 was passed.
;  Corrupts F.
;  Must be called by using CALBNK to bank 0:
;  ld a,slot
;  ex af,af'
;  xor a
;  ld ix,GWORK
;  call CALBNK

GWORK	equ	4045h


;* Call a routine in the driver bank.
;  Input: (BK4_ADD) = routine address
;         AF, BC, DE, HL, IY = input for the routine
;
; Calls a routine in the driver bank. This routine is the same as CALBNK,
; except that the routine address is passed in address BK4_ADD (#F2ED)
; instead of IX, and the bank number is always 5. This is useful when used
; in combination with CALSLT to call a driver routine from outside
; the driver itself.
;
; Note that register IX can't be used as input parameter, it is
; corrupted before reaching the invoked code.

CALDRV	equ	4048h


;-----------------------------------------------------------------------------
;
; Built-in format choice strings
;

NULL_MSG  equ     741Fh	;Null string (disk can't be formatted)
SING_DBL  equ     7420h ;"1-Single side / 2-Double side"


;-----------------------------------------------------------------------------
;
; Driver signature
;
;-----------------------------------------------------------------------------
; Nextor v3 fixed driver entry table.
; This repository version uses the NEXTORv3_DRIVER entry format used by
; Nextor 3 and by source/drivers/standalone-rom-driver.asm.
;
	db	"NEXTORv3_DRIVER",0

	jp	DRV_TIMI
	jp	DRV_BASSTAT
	jp	DRV_BASDEV
	jp	DRV_EXTBIO
	jp	DRIVER_QUERY
	jp	DEVICE_QUERY
	jp	CUSTOM_DRIVER_QUERY
	jp	CUSTOM_DEVICE_QUERY
	jp	READ_WRITE
	jp	RESERVED_0
	jp	RESERVED_1
	jp	RESERVED_2
	jp	DRV_DIRECT0
	jp	DRV_DIRECT1
	jp	DRV_DIRECT2
	jp	DRV_DIRECT3
	jp	DRV_DIRECT4

; End of the fixed v3 entry data.

; Driver query / device query code follows.

;=============================================================================
; Nextor v3 query interface
;=============================================================================

DRIVER_QUERY:
	dec	a
	jr	z,DO_DRVQ_GET_VERSION
	dec	a
	jr	z,DO_DRVQ_GET_STRING
	dec	a
	jr	z,DO_DRVQ_GET_INIT_PARAMS
	dec	a
	jr	z,DO_DRVQ_INIT
	dec	a
	jr	z,DO_DRVQ_GET_MAX_DEVICE
	ld	a,RESULT_NOT_IMPLEMENTED
	ret

; Query 1: driver version. Nextor v3 returns B.C.D, with A as result code.
DO_DRVQ_GET_VERSION:
	ld	b,VER_MAIN
	ld	c,VER_SEC
	ld	d,VER_REV
	xor	a
	ret

; Query 2: driver identification strings.
DO_DRVQ_GET_STRING:
	ld	a,b
	ld	b,d
	ex	de,hl
	dec	a
	ld	hl,V3_STR_DRIVER_NAME
	jp	z,OUTPUT_STRING
	dec	a
	ld	hl,V3_STR_DRIVER_AUTHOR
	jp	z,OUTPUT_STRING
	dec	a
	ld	hl,V3_STR_HARDWARE_NAME
	jp	z,OUTPUT_STRING
	dec	a
	ld	hl,V3_STR_HARDWARE_AUTHOR
	jp	z,OUTPUT_STRING
	; Serial number is hardware-dependent and is exposed by DEVICE_QUERY.
	ld	a,RESULT_NOT_IMPLEMENTED
	ret

; Query 3: initialization parameters.
; The legacy DRV_INIT first pass still decides whether TIMER must be hooked.
DO_DRVQ_GET_INIT_PARAMS:
	xor	a
	call	DRV_INIT
	ld	b,0
	rl	b			; Carry from DRV_INIT -> output flag bit 0
	xor	a
	ret

; Query 4: initialize the ROM driver.
; DE is the kernel character-output routine used by the legacy init code.
DO_DRVQ_INIT:
	bit	7,c			; Not enough page-3 work area?
	jr	nz,DO_DRVQ_INIT_ERROR
	push	de
	pop	iy
	ld	a,1
	call	DRV_INIT
	xor	a
	ret
DO_DRVQ_INIT_ERROR:
	ld	a,RESULT_INIT_ERROR
	ret

; Query 5: FlashJacks has two device slots: master and slave.
DO_DRVQ_GET_MAX_DEVICE:
	ld	b,2
	xor	a
	ret

; Character output adapter used by the old FlashJacks initialization code.
DRIVER_CHPUT:
	jp	(iy)

;=============================================================================
; Nextor v3 DEVICE_QUERY
;=============================================================================

DEVICE_QUERY:
	dec	a
	jr	z,DO_DEVQ_GET_STRING
	dec	a
	jp	z,DO_DEVQ_GET_PARAMS
	dec	a
	jp	z,DO_DEVQ_GET_STATUS
	dec	a
	jp	z,DO_DEVQ_GET_AVAILABILITY
	dec	a
	jp	z,DO_DEVQ_GET_FORMAT_CHOICES
	dec	a
	jp	z,DO_DEVQ_DO_FORMAT
	dec	a
	jp	z,DO_DEVQ_STOP_MOTOR
	ld	a,RESULT_NOT_IMPLEMENTED
	ret

; Validate C=device and make sure the corresponding legacy work-area entry
; says that the device was detected during initialization.
; Carry set = invalid/non-existing device.
V3_CHECK_DEVICE:
	ld	a,c
	or	a
	jr	z,V3_CHECK_DEVICE_BAD
	cp	3
	jr	nc,V3_CHECK_DEVICE_BAD
	call	MY_GWORK
	ld	a,(ix)
	or	a
	ret	nz			; Existing device, carry cleared by OR A
V3_CHECK_DEVICE_BAD:
	scf
	ret

; Device query 1: identification strings.
; B=1 manufacturer, 2 medium, 3 serial, 4 device name.
DO_DEVQ_GET_STRING:
	push	bc
	ld	a,c
	call	V3_CHECK_DEVICE
	pop	bc
	jr	c,V3_DEVQ_INVALID

	ld	a,b
	cp	3
	jr	z,V3_DEVQ_STRING_OLD
	cp	4
	jr	z,V3_DEVQ_STRING_OLD
	ld	a,RESULT_NOT_IMPLEMENTED
	ret

V3_DEVQ_STRING_OLD:
	; Preserve the user's destination and size while DEV_INFO fills the
	; legacy 64-byte image in the driver's page-3 scratch area.
	push	hl
	push	de
	push	bc

	ld	a,c
	call	MY_GWORK
	push	ix
	pop	hl
	ld	de,WRKAREA_STRBUFF
	add	hl,de			; HL = scratch buffer

	pop	bc			; B=subquery, C=device
	push	bc			; Preserve for after DEV_INFO
	push	hl			; Preserve scratch address

	ld	a,c
	cp	3
	jr	z,V3_DEVQ_SERIAL
	ld	b,2			; Old DEV_INFO: 2=device name
	jr	V3_DEVQ_CALL_INFO
V3_DEVQ_SERIAL:
	ld	b,3			; Old DEV_INFO: 3=serial number
V3_DEVQ_CALL_INFO:
	call	DEV_INFO

	pop	hl			; Scratch
	pop	bc			; Original B/C
	or	a
	jr	nz,V3_DEVQ_STRING_FAIL

	; DEV_INFO pads the legacy image with spaces. It writes the device
	; name at offset 0 and the serial number at offset 44.
	ld	a,b
	cp	3
	jr	z,V3_DEVQ_SERIAL_PTR
	ld	hl,WRKAREA_STRBUFF
	push	ix
	pop	de
	add	hl,de
	jr	V3_DEVQ_STRING_DEST
V3_DEVQ_SERIAL_PTR:
	ld	hl,WRKAREA_STRBUFF
	push	ix
	pop	de
	add	hl,de
	ld	bc,44
	add	hl,bc
V3_DEVQ_STRING_DEST:
	pop	de			; DE = user buffer size
	ld	b,d			; B = user buffer size
	pop	de			; DE = user buffer
	jp	OUTPUT_STRING

V3_DEVQ_STRING_FAIL:
	pop	de			; User size
	pop	hl			; User buffer
	ld	a,RESULT_NOT_IMPLEMENTED
	ret

V3_DEVQ_INVALID:
	ld	a,RESULT_INVALID_DEVICE
	ret

; Device query 2: device parameters.
; The legacy LUN_INFO layout is almost identical to the v3 parameter block.
DO_DEVQ_GET_PARAMS:
	push	hl
	ld	a,c
	call	V3_CHECK_DEVICE
	pop	hl
	jr	c,V3_DEVQ_INVALID
	ld	a,h
	or	l
	ret	z			; Valid device, caller requested no buffer

	ld	a,c
	ld	b,1			; FlashJacks implements one LUN per device
	call	LUN_INFO
	or	a
	ret	z

	; Device exists but the medium may currently be unavailable. Return
	; useful default parameters instead of reporting a non-existing device.
	push	hl
	pop	ix
	xor	a
	ld	(ix+0),a		; Block device
	ld	(ix+1),a
	ld	(ix+2),2		; 512-byte sectors
	ld	(ix+3),a
	ld	(ix+4),a
	ld	(ix+5),a
	ld	(ix+6),a		; Unknown capacity
	ld	(ix+7),1		; Removable
	ld	(ix+8),a
	ld	(ix+9),a
	ld	(ix+10),a
	ld	(ix+11),a
	xor	a
	ret

; Device query 3: device/medium change status.
DO_DEVQ_GET_STATUS:
	call	V3_DEVQ_READ_MEDIA_STATUS
	ret

; Device query 4: availability without consuming the media-change state.
DO_DEVQ_GET_AVAILABILITY:
	call	V3_DEVQ_READ_MEDIA_AVAILABILITY
	ret

; Read the FlashJacks error/status register and translate its bits to v3.
V3_DEVQ_READ_MEDIA_STATUS:
	call	V3_CHECK_DEVICE
	jr	c,V3_DEVQ_INVALID
	call	IDE_ON
	ld	a,(IDE_ERROR)
	ld	b,a
	call	IDE_OFF
	ld	a,b
	bit	NM,a
	jr	nz,V3_MEDIA_ABSENT
	bit	MC,a
	jr	nz,V3_MEDIA_CHANGED
	ld	b,1
	xor	a
	ret
V3_MEDIA_ABSENT:
	ld	b,0
	xor	a
	ret
V3_MEDIA_CHANGED:
	ld	b,2
	xor	a
	ret

V3_DEVQ_READ_MEDIA_AVAILABILITY:
	call	V3_CHECK_DEVICE
	jr	c,V3_DEVQ_INVALID
	call	IDE_ON
	ld	a,(IDE_ERROR)
	ld	b,a
	call	IDE_OFF
	ld	a,b
	bit	NM,a
	jr	nz,V3_AVAIL_ABSENT
	ld	b,1
	xor	a
	ret
V3_AVAIL_ABSENT:
	ld	b,0
	xor	a
	ret

; FlashJacks is not a floppy device and has no format/motor API.
DO_DEVQ_GET_FORMAT_CHOICES:
	ld	a,RESULT_NOT_IMPLEMENTED
	ret
DO_DEVQ_DO_FORMAT:
	ld	a,RESULT_NOT_IMPLEMENTED
	ret
DO_DEVQ_STOP_MOTOR:
	ld	a,RESULT_NOT_IMPLEMENTED
	ret

CUSTOM_DRIVER_QUERY:
	ld	a,RESULT_NOT_IMPLEMENTED
	ret

CUSTOM_DEVICE_QUERY:
	ld	a,RESULT_NOT_IMPLEMENTED
	ret

; Nextor v3 read/write has no LUN parameter. The FlashJacks core is a
; one-LUN-per-device v2 implementation, so force C=1.
READ_WRITE:
	; Nextor v3: A=device, B=count, C=media descriptor (0 for block devices).
	; Legacy FlashJacks DEV_RW expects C=LUN. There is one LUN per device,
	; so translate the v3 call to C=1.
	push	af
	push	af
	or	a
	jr	z,V3_RW_BAD_DEVICE_EARLY
	cp	3
	jr	nc,V3_RW_BAD_DEVICE_EARLY
	call	MY_GWORK
	ld	a,(ix)
	or	a
	jr	z,V3_RW_BAD_DEVICE
	pop	af			; discard validation copy
	pop	af			; original AF, including Carry
	ld	c,1
	call	DEV_RW
	ret

V3_RW_BAD_DEVICE_EARLY:
	pop	af			; validation copy
V3_RW_BAD_DEVICE:
	pop	af			; original AF
	ld	a,IDEVL
	ld	b,0
	ret



	INCLUDE asm/code/output_string.asm

;-----------------------------------------------------------------------------
;
; Timer interrupt routine, it will be called on each timer interrupt
; (at 50 or 60Hz), but only if DRV_INIT returns Cy=1 on its first execution.

; ============================================================================
; MAIN TIMER INTERRUPT ROUTINE
; Runs 50/60 times per second
; ============================================================================
DRV_TIMI:
        push af
        push bc
        push hl
        push de
        exx                     ; Preserve shadow registers
        ex   af,af'             ; Preserve AF'
        di                      ; Critical section

        ; ====================================================================
        ; PHASE 1: FAST KEYBOARD MATRIX SCAN FROM ALTERNATE PORT
        ; ====================================================================
        ; This scan reads from port 0DEh (FlashJacks alternate port)
        ; and stores into NEWKEY (FBE5h) for BIOS compatibility
        
        in   a,(0AAh)           ; Prepare PPI register C
        and  0F0h               ; Clear bits 0-3 (row selection)
        ld   c,a                ; C = base for row selection
        ld   b,0Bh              ; 11 rows (0-10)
        ld   hl,NEWKEY          ; Destination: NEWKEY area (BIOS compatible)
        xor  a
        ld   d,a                ; D=0: "no keys" flag

scan_loop:
        ld   a,c
        out  (0AAh),a           ; Select row on PPI
        in   a,(0DEh)           ; Read from ALTERNATE FlashJacks port
        ld   (hl),a             ; Store into NEWKEY
        
        cp   0FFh               ; All keys unpressed?
        jr   z,scan_next        ; Yes, continue
        ld   d,01h              ; Mark that keys are pressed
        
scan_next:
        inc  c                  ; Next row
        inc  hl                 ; Next NEWKEY byte
        djnz scan_loop          ; Repeat for 11 rows

        ; ====================================================================
        ; PHASE 2: INTELLIGENT CHANGE ANALYSIS
        ; ====================================================================
        ld   a,d
        or   a
        jr   nz,hay_tecla       ; Keys are pressed
        
        ; --------------------------------------------------------------------
        ; NO KEYS PRESSED - Cleanup and reset
        ; --------------------------------------------------------------------
sin_tecla:
        xor  a
        ld   (COUNTER_REP),a    ; Reset repeat counter
        
        ; Clear keyboard buffer (40 bytes from FBF0h)
        ld   hl,KEYBUF
        ld   de,KEYBUF+1
        ld   bc,39
        ld   (hl),0
        ldir
        
        ; Reset pointers
        ld   hl,KEYBUF
        ld   (PUTPNT),hl        ; PUTPNT = buffer start
        ld   (GETPNT),hl        ; GETPNT = buffer start
        
        jr   fin_timi

        ; --------------------------------------------------------------------
        ; KEYS ARE PRESSED - Detailed analysis
        ; --------------------------------------------------------------------
hay_tecla:
        ; First: is it a modifier key ALONE?
        call CHECK_ONLY_MODIFIERS
        jr   c,tecla_modificadora_sola
        
        ; It is a normal key, or a key + modifier
        ; Manage repeat counter
        ld   a,(COUNTER_REP)
        inc  a
        cp   2                ; Avoid overflow
        jr   nz,no_overflow
        ld   a,2
no_overflow:
        ld   (COUNTER_REP),a
        
        ; Decide whether to run the BIOS scan
        cp   1                  ; First keypress?
        jr   z,ejecutar_scan
        
        cp   DELAY_INICIAL+1    ; Before the initial delay?
        jr   c,fin_timi         ; Yes, do nothing yet
        jr   z,ejecutar_scan    ; Right after the delay, run it
        
        ; Compute whether a repeat is due (modulo INTERVALO_REP)
        sub  DELAY_INICIAL+1
mod_loop:
        cp   INTERVALO_REP
        jr   c,mod_check_zero
        sub  INTERVALO_REP
        jr   mod_loop
mod_check_zero:
        or   a
        jr   nz,fin_timi        ; Not due yet

ejecutar_scan:
        ; Call the BIOS routine for full processing
        ei                      ; Enable interrupts for BIOS
        call 0D26h              ; BIOS keyboard decoding routine
        jr   fin_timi

        ; --------------------------------------------------------------------
        ; MODIFIER KEY ALONE - Do not generate repeat
        ; --------------------------------------------------------------------
tecla_modificadora_sola:
        ; Modifier keys ALONE must NOT:
        ; - Increment the repeat counter
        ; - Generate characters in the buffer
        ; - Call the decoding routine
        
        ; BUT they SHOULD:
        ; - Update NEWKEY so other routines can see them
        ; - Be readable via SNSMAT
        
        xor  a
        ld   (COUNTER_REP),a    ; Reset counter (no repeat)
        ; Do not call 0D26h
        jr   fin_timi

        ; ====================================================================
        ; PHASE 3: FINALIZATION
        ; ====================================================================
fin_timi:
        ei                      ; Re-enable interrupts
        ex   af,af'             ; Restore AF'
        exx                     ; Restore shadow registers
        pop  de
        pop  hl
        pop  bc
        pop  af
        ret

; ============================================================================
; SUBROUTINE: CHECK_ONLY_MODIFIERS
; Checks whether ONLY modifier keys are pressed (no normal keys)
; 
; Output:
;   Cy = 1: Only modifiers (or none)
;   Cy = 0: There are normal keys (with or without modifiers)
; ============================================================================
CHECK_ONLY_MODIFIERS:
        push hl
        push bc
        
        ; Check rows 0-5 (normal keys)
        ld   hl,NEWKEY
        ld   b,6                ; First 6 rows
check_normal_loop:
        ld   a,(hl)
        cp   0FFh               ; Any key pressed in this row?
        jr   nz,found_normal    ; Yes, there is a normal key
        inc  hl
        djnz check_normal_loop
        
        ; Check row 6 (modifiers) - bits 5-7 only
        ; Bits 0-4 are modifiers, bits 5-7 are F1-F3
        ld   a,(hl)             ; NEWKEY+6
        or   MASK_MODIFIERS     ; Mask out modifiers (bits 0-4)
        cp   0FFh               ; Only modifiers, or nothing?
        jr   nz,found_normal    ; Bits 5-7 active = F1-F3 = normal key
        
        inc  hl
        ; Check rows 7-10 (special and numeric keys)
        ld   b,4
check_special_loop:
        ld   a,(hl)
        cp   0FFh
        jr   nz,found_normal
        inc  hl
        djnz check_special_loop
        
        ; Only modifiers (or no key at all)
        pop  bc
        pop  hl
        scf                     ; Cy = 1
        ret

found_normal:
        ; There is at least one normal key
        pop  bc
        pop  hl
        or   a                  ; Cy = 0
        ret



;-----------------------------------------------------------------------------
;
; Driver initialization, it is called twice:
;
; 1) First execution, for information gathering.
;    Input:
;      A = 0
;      B = number of available drives (drive-based drivers only)
;      HL = maximum size of allocatable work area in page 3
;    Output:
;      A = number of required drives (for drive-based driver only)
;      HL = size of required work area in page 3
;      Cy = 1 if DRV_TIMI must be hooked to the timer interrupt, 0 otherwise
;
; 2) Second execution, for work area and hardware initialization.
;    Input:
;      A = 1
;      B = number of allocated drives for this controller
;          (255 if device-based driver, unless 4 is pressed at boot)
;
;    The work area address can be obtained by using GWORK.
;
;    If first execution requests more work area than available,
;    second execution will not be done and DRV_TIMI will not be hooked
;    to the timer interrupt.
;
;    If first execution requests more drives than available,
;    as many drives as possible will be allocated, and the initialization
;    procedure will continue the normal way
;    (for drive-based drivers only. Device-based drivers always
;     get two allocated drives.)

TEMP_WORK	equ	0C000h

DRV_INIT:
	;--- If first execution, just inform that no work area is needed
	;    (the 8 bytes in SLTWRK are enough)

	or	a
	jr	nz,DRV_INIT2
	
	;Check first whether to disable H.TIMI
	push	af
	call	IDE_ON 
	ld      a,(IDE_FLASHJACKS) ; Fetch the Flashjacks register. (Counts 1 for possible double reset)
	and	00100000b ; Keep only the SOFTPORT bit
	cp	020h ;	Check bit flag.
	jp	z,FORINIT2 ; If 1 is detected in SOFTPORT, does not disable H.TIMI
	; First run: do not request timer hook
	call	IDE_OFF	
	pop	af
	or	a		; ← Cy=0: DISABLES DRV_TIMI for keyboard hook
	ld	hl,WRKAREA_SIZE	; 8-byte legacy area + 65-byte v3 string scratch
	ld	a,2		; 2 drives
	ret	
		
FORINIT2:
	; First run: request timer hook
	call	IDE_OFF	
	pop	af
	ld	hl,WRKAREA_SIZE	; 8-byte legacy area + 65-byte v3 string scratch
	ld	a,2		; 2 drives
	scf			; ← Cy=1: ENABLES DRV_TIMI for keyboard hook
	ret	
	
DRV_INIT2:

	;xor a
	;ld (TESTADD),a

	;--- Clear the screen. On MSX1 this must be done explicitly since it is not implemented by default.
	
	push	af ; Save the startup variables.
	push	bc
	push	hl
	
	;-- Screen clearing is skipped on Nextor >= 3.0 so the Nextor options remain visible.
		;bit	0,a ; Clear the Z flag
		;xor	a ; Clear a
		;call	CLS
		;--- This clearing method is better. Contributed by Victor.
		;ld	a,40 ; 40 columns
		;ld	(0F3AEh),a
		;xor	a
		;call	005Fh ; Screen 0

	;--- Check the double-reset bit and run it if it is on.
	call	IDE_ON
	ld      a,(IDE_FLASHJACKS) ; Fetch the Flashjacks register.(Counts 2 for possible double reset)  
	and	00000100b ; Clear the freq and second-slot bits, keeping only the option-flag bits.
	cp	004h ;	Check reset flag bit
	jp	nz,CONTPRG ; No correct flag was detected in the Flashjacks register, so nothing from the reset is executed.
	call	IDE_OFF
	pop	hl ; Restore the startup variables.
	pop	bc 
	pop	af
	rst	0 ; Force a reset. From here on it does a soft reset and does not continue with the program.

CONTPRG:
	call	IDE_OFF

	;----------------------------------------------
	;Check the F4 and F5 keys (VDP FREQ and force TURBOCPU)
	push	af
	push	hl
	push	de
	push	bc

	; Compare pressed key
	ld	b,7 ;row 7 	RET 	SELECT 	BS 	STOP 	TAB 	ESC 	F5 	F4
	in	a,(0AAh)
	and	11110000b
	or	b
	out	(0AAh),a
	; Read from standard port A9h
	in      a, (0A9h)       ; First read (standard port)
	ld      c, a            ; Store in C
	; Read from alternate port DEh
	in      a, (0DEh)       ; Second read (alternate port)
	; Combine both reads with AND
	and     c               ; A = A9h AND DEh	
	bit	0,a ;F4 -- If the turbo key is pressed, jumps to the turbo activation routine.
	jp	nz,Fin_ini ; Jump if the turbo key is not pressed.
	push	af
	call	putTURBO_CPU ; Run turbo CPU.
	pop	af
Fin_ini:pop	bc
	pop	de
	pop	hl
	pop	af
	
	
	;-- Adds a line break to separate the Nextor >= 3.0 info from the Flashjacks info.
	ld	de,CRLF_S
	call	PRINT

	;--- Begin writing the driver text on screen.	
	ld	de,INFO_S
	call	PRINT
	
	;--- Print the computer model on screen.	
	ld	de,MODELO ; Print "Model:"
	call	PRINT
	ld      a,(MSXVER) ; Fetch the MSX version register from the BIOS
	cp	00h ; If it is an MSX1, jump to print MSX1.
	jp	z,IMP_MSX1 
	cp	01h ; If it is an MSX2, jump to print MSX2.
	jp	z,IMP_MSX2 
	cp	02h ; If it is an MSX2+, jump to print MSX2+.
	jp	z,IMP_MSX2M 
	cp	03h ; If it is an MSX TurboR, jump to print MSX TurboR.
	jp	z,IMP_MSXR 
	cp	04h ; If it is an OCM, jump to print OCM.
	jp	z,IMP_OCM 
	jp	NO_DETEC ; If it is none of the versions above, print "not detected".
IMP_MSX1:
	ld	de,M_MSX1
	call	PRINT
	jp	FIN_IMP;
IMP_MSX2:
	ld	de,M_MSX2
	call	PRINT
	jp	FIN_IMP;
IMP_MSX2M:
	ld	de,M_MSX2M
	call	PRINT
	jp	FIN_IMP;
IMP_MSXR:
	ld	de,M_MSXR
	call	PRINT
	jp	FIN_IMP;
IMP_OCM:
	ld	de,M_OCM
	call	PRINT
	jp	FIN_IMP;
NO_DETEC:
	ld	de,M_NDTC
	call	PRINT
FIN_IMP:
	pop	hl ; Restore the startup variables.
	pop	bc 
	pop	af

	;-- Print the search for the drive on screen.
	ld	de,SEARCH_S
	call	PRINT

	ld	a,1
	call	MY_GWORK
	ld	(ix),0			;Assume both devices empty
	ld	(ix+4),0	

        call    IDE_ON
        ld      a,M_SRST		;Do a software reset
        ld      (IDE_DEVCTRL),a
        nop     ;Wait 5 us
        xor     a
        ld      (IDE_DEVCTRL),a
        call    IDE_OFF

WAIT_RESET:
        ld      de,7640			;Timeout after 30 s
WAIT_RESET1:
        ld      a,0
        cp      e
        jp      nz,WAIT_DOT		;Print dots while waiting
        ld      a,46
        call    DRIVER_CHPUT
WAIT_DOT:
	call	CHECK_ESC
	jp	c,INIT_NO_DEV
        ld      b,255
WAIT_RESET2:
        call    IDE_ON
        ld      a,(IDE_STATUS)
        and     M_BSY+M_DRDY
        cp      M_DRDY
        call    IDE_OFF
        jp      z,WAIT_RESET_END        ;Wait for BSY to clear and DRDY to set          
        djnz    WAIT_RESET2
        dec     de
        ld      a,d
        or      e
        jp      nz,WAIT_RESET1
        jp      INIT_NO_DEV
WAIT_RESET_END:

	ld	a,1			;Flag the device 0
	ld	(ix),a
MASTER_CHECK1_END:
        ld      a,46			;Print dot
        call    DRIVER_CHPUT

        ; The reset wait has left IDE disabled. Re-enable it only for
        ; the short hardware reset sequence, then release it again.
        call    IDE_ON
        ld      a,M_SRST		; Do ANOTHER software reset
        ld      (IDE_DEVCTRL),a
        nop     			;Wait 5 us
        xor     a
        ld      (IDE_DEVCTRL),a
	nop				;Wait 5 us
        call    IDE_OFF
        ld      a,46			;Print dot
        call    DRIVER_CHPUT

	ld      de,CRLF_S
        call    PRINT

	;--- Get info and show the name for the MASTER

	ld	de,MASTER_S
	call	PRINT

WSKIPMAS:			; If ESC is pressed, ignore this device
        ld      de,624			; Wait 1s to read the keyboard
WSKIPMAS1:
        call    CHECK_ESC
        jp      c,NODEV_MASTER_NOIDE
        ld      b,64
WSKIPMAS2:
	ex	(sp),hl
	ex	(sp),hl
        djnz    WSKIPMAS2
        dec     de
        ld      a,d
        or      e
        jp      nz,WSKIPMAS1

	ld	a,(ix)			;If the device isn't flagged it doesn't exists
	cp	1
	jp	nz,NODEV_MASTER_NOIDE
        call    IDE_ON
        ld      a,46			;Print FIRST dot
        call    DRIVER_CHPUT

	call	WAIT_CMD_RDY
	jp	c,NODEV_MASTER
	ld	a,0
	ld	(IDE_HEAD),a		;Select device 0
        ld      a,46			;Print SECOND dot
        call    DRIVER_CHPUT

	ld	a,0ECh			;Send IDENTIFY commad
	call	DO_IDE			
	jp	c,NODEV_MASTER
        ld      a,46			;Print THIRD dot
        call    DRIVER_CHPUT

	call	INIT_CHECK_DEV		;Check if the device is ATA or ATAPI
	jp	c,NODEV_MASTER
        ld      a,46			;Print FOURTH dot
        call    DRIVER_CHPUT

	; Test IDIOMA, RAM1 and RAM2 commands. This must be entered with its call IDE_ON and its IDE_OFF at the end. <-- Delete this piece of code once tested.
	;ld	a,(IDE_IDIOMA) ; Read the language variable 0 to 255 (0 Spanish, 1 English)
	;add	a, 30h
	;call	DRIVER_CHPUT

	;ld	a,6 ; Set to 6
	;ld	(IDE_RAM1), a ; Transfer it to an FPGA RAM byte (RAM1)
	;xor	a ; Clear accumulator
	;ld	a,(IDE_RAM1) ; Retrieve an FPGA RAM byte (RAM1)
	;add	a, 30h
	;call	DRIVER_CHPUT

	;ld	a,9
	;ld	(IDE_RAM2), a ; Transfer it to an FPGA RAM byte (RAM1)
	;xor	a ; Clear accumulator
	;ld	a,(IDE_RAM2) ; Retrieve an FPGA RAM byte (RAM1)
	;add	a, 30h
	;call	DRIVER_CHPUT
	; End of IDIOMA, RAM1 and RAM2 command test.

	call	WAIT_CMD_RDY		;Try to select the device
	jp	c,NODEV_MASTER		;this is our last chance to *NOT* detect it
	ld	a,0
	ld	(IDE_HEAD),a		;Select device 0
        ld      a,46			;Print FIFTH dot
        call    DRIVER_CHPUT

	call	INIT_PRINT_NAME

	ld	(ix),2	;ATA device with LBA
	jp	OK_MASTER

NODEV_MASTER:
        ; From here on the IDE hardware is no longer needed. Release it
        ; before waiting for ESC, otherwise IDE_OFF would leave interrupts
        ; disabled for an indeterminate time.
        call    IDE_OFF
NODEV_MASTER_WAIT:
	call	CHECK_ESC
	jp	c,NODEV_MASTER_NOIDE
	jp	NODEV_MASTER_WAIT

NODEV_MASTER_NOIDE:
	ld	(ix),0
	ld	de,NODEVS_S
	call	PRINT

FINAL_RESET:
        call    IDE_ON
        jp      FINAL_RESET_ACTIVE

OK_MASTER:
FINAL_RESET_ACTIVE:
        ld      a,M_SRST		;Last software reset before we go
        ld      (IDE_DEVCTRL),a		;some times a faulty slave leaves
					;BSY set forever (30s)
        nop     ;Wait 5 us
        xor     a
        ld      (IDE_DEVCTRL),a
        call    IDE_OFF

	jp	DRV_INIT_END_NOIDE

INIT_NO_DEV:
	call	CHECK_ESC
	jp	c,INIT_NO_DEV

	ld      de,CRLF_S
        call    PRINT
	ld	de,MASTER_S
	call	PRINT
	ld	de,NODEVS_S
	call	PRINT
		
	;--- End of the initialization procedure.

DRV_INIT_END_NOIDE:
	ld	(ix+4),0 ; Flag that there is no slave device.

	;--- Wait delay of 2 seconds so the driver loading text can be seen on screen. 
	;--- Not done on an MSXTurboR, since that machine already has its own delay at boot.
	push	de
	push	bc
	ld      a,(MSXVER) ; Fetch the MSX version register from the BIOS
	cp	03h ; If it is an MSX TurboR, jump ahead since this machine is already slow to boot.
	jp	z,ESPERA_FIN ; Skip the 2s wait for the TurboR
	ld	de,1861	; Counter loaded for 2s
ESPERA_RDY1:
	ld	b,255
ESPERA_RDY2:
	djnz	ESPERA_RDY2	; ESPERA_RDY2 loop
	dec	de
	ld	a,d
	or	e
	jp	nz,ESPERA_RDY1	; ESPERA_RDY1 loop
ESPERA_FIN:
	pop	bc
	pop	de

	;--- Support code for the FLASHJACKS drive. Runs after NEXTOR startup.
	call	IDE_ON
	ld      a,(MSXVER) ; Fetch the MSX version register from the BIOS
	cp	00h ; If it is an MSX1, skip the VDP forcing operation due to incompatibility.
	jp	z,DEV_FLASH_FIN 
	
	; Compare pressed key
	ld	b,7 ;row 7 	RET 	SELECT 	BS 	STOP 	TAB 	ESC 	F5 	F4
	in	a,(0AAh)
	and	11110000b
	or	b
	out	(0AAh),a
	; Read from standard port A9h
	in      a, (0A9h)       ; First read (standard port)
	ld      c, a            ; Store in C
	; Read from alternate port DEh
	in      a, (0DEh)       ; Second read (alternate port)
	; Combine both reads with AND
	and     c               ; A = A9h AND DEh	
	bit	1,a ;F5 -- If the VDP key is pressed, jumps to the frequency-switching routine.
	jp	z,DEV_VDP_FIN ; Skips VDP handling for the pressed-key VDP switch.
	ld      a,(IDE_FLASHJACKS) ; Fetch the Flashjacks register. 
	and	00000011b ; Keep only the frequency-force bits.
	cp	003h ;	Forced to 60Hz. Force bit set to 1 + 60 Hz bit set to 1
	jp	z,DEV_FLASH60 ; Jump to force 60 Hz.
	cp	002h ;	Forced to 50Hz. Force bit set to 1 + 50 Hz bit set to 0
	jp	z,DEV_FLASH50 ; Jump to force 50 Hz.
	jp	DEV_FLASH_FIN ; Other options are ignored and no change is made.

DEV_FLASH50:
	ld	a,02h ; 02h for 50hz and 00h for 60hz
	jp	DEV_FLASHVDP;

DEV_FLASH60:
	ld	a,00h ; 02h for 50hz and 00h for 60hz

DEV_FLASHVDP:
	out	(099h),a ;Direct VDP output
	ld	(0ffe8h), a ;VDP register 9 output via BIOS
	ld	a,89h
	out	(099h),a

DEV_FLASH_FIN:
	call	IDE_OFF
	jp	NO_FIRM_BOOT ; Jump to check the firmware boot skip for some MSX models.

DEV_VDP_FIN:
	; Toggle the existing VDP setting
	ld	hl,0ffe8h;VDP register value
	ld	a,(hl)
	xor	2
	ld	(hl),a
	out	(99h),a ;Set VDP Frequency
	ld	a,9+128
	out	(099h),a
	call	IDE_OFF
	jp	NO_FIRM_BOOT ; Jump to check the firmware boot skip for some MSX models.

NO_FIRM_BOOT:; Check for the firmware boot skip on some MSX models.
	
	call	IDE_ON
	ld      a,(IDE_FLASHJACKS) ; Fetch the Flashjacks register. 
	and	00010000b ; Keep only the MSX firmware boot-skip flag
	cp	010h ;	Check the MSX firmware boot-skip bit.
	call	z,IDE_OFF
	jp	nz,NULL_OTHER_SLOT ; No correct flag was detected in the Flashjacks register, so nothing from the firmware boot skip is executed.

	;---- Bypass of the internal boot. To follow along, set a breakpoint on Hook #FEDA. (Memory write watchpoint)
	;---- Created entirely by Aquijacks (Flashjacks) 16/12/2023.

	;---- Checks via the hook whether this is not a Panasonic.
	ld	a,(#FEFE)
	cp	#87
	jp	nz, No_Panasonic
	
	;If it is a Panasonic, bypass FS-A1, FS-A1F and FS-A1mk2.
	ld	a,#23
	ld	(#CBD8),a	; Bypass FS-A1 firmware
	ld	(#C3CE),a	; Bypass FS-A1F firmware
	ld	(#C3D2),a	; Bypass FS-A1mk2 firmware
	jp	NULL_OTHER_SLOT ; End of the story. Nothing more is needed.
	 
No_Panasonic:
	;Check that this is not a Sony HB-55/75p, then continue with the rest of the models.
	ld	a,0		; Slot 0
	ld	hl,#8010	; Read the menu ROM.
	call	RDSLT
	ei			; RDSLT does a DI but not an EI. We add it here.
	cp	#F3		; value to compare
	jp	nz, No_HB_75
	ld	a,0		; Slot 0
	ld	hl,#8011	; Read the menu ROM.
	call	RDSLT
	ei			; RDSLT does a DI but not an EI. We add it here.
	cp	#3E		; value to compare
	jp	nz, No_HB_75	
	jp	NULL_OTHER_SLOT	; Return control if this is an unpatched HB-75p, since these models detect the disk and disable the menu.

No_HB_75:
	; Routine that performs the ROM bypass for the HB-F9P/S, HB-F1, HB-101/201P, Mitsubishi G1 Series, Toshiba Series H, National FS-4000/4500 models and others using the same system.  
	; Patches the instruction at address F38Fh, call #F398, to call #F460 (free memory)
	ld	a,060h
	ld	(#F390),a
	ld	a,0F4h
	ld	(#F391),a

	; At memory address #F460, add the "Adding" patch code to be executed.
	ld	hl,Adding
	ld	de,#F460
	ld	bc,7Fh ; Number of bytes to copy. Not exact, but more than enough for the code being inserted.
	ldir
	; This is a counter we created to abort after x attempts of looking for the patch point. If a call to address 00XXh is made via the F390 jump, it aborts and restores its initial state.
	ld	a, 30h    ; Number of attempts, in hexadecimal.
	ld	(#F4E0),a ; Any free memory address.

	jp	NULL_OTHER_SLOT	 ; Return control. RAM is now patched with the little program. Now we just wait for the CPU to land here.

Adding:
	; The patch only triggers on access to the firmware menu. On all other accesses to the F390 addresses, it jumps to ix as if nothing happened.
	; ix holds the jump address. That routine isn't only used to jump to the firmware menu, so we only act on the jump to it. For everything else, we stay invisible.
	push	af ; Save the accumulator and flags, since some MSX models are sensitive in this part of the code about preserving the accumulator and flags.
	ld	a,ixh
	cp	#00
	jr	z, Adding3 ;If it points to memory 00xxh, decrement the failed-attempts counter, and if it's the last one, unpatch and finish.
	ld	a,ixh
	cp	#40
	jr	nz, Adding2 ;If it does not point to memory 40xxh, jump.
	ld	a,ixl
	cp	#49 ; 4049h start address of the HB-F1
	jr	z, Adding4
	cp	#10 ; 4010h start address of the HB-F9s / Mitsubishi G1 / Toshiba Series H
	jr	z, Adding4
	cp	#43 ; 4043h start address of the HB-201
	jr	z, Adding4
	cp	#4C ; 404Ch start address of the HB-F1II
	jr	z, Adding4
	cp	#3B ; 403Bh start address of the National FS-4500
	jr	z, Adding4
	cp	#1B ; 401Bh start address of the National FS-4000
	jr	z, Adding4
Adding2:
	pop	af   ; Restore af to its initial values for the rest of the MSX's operations.
	jp	(ix) ; Jump as if nothing had happened, waiting for the next attempt.
Adding3:
	; Decreasing countdown process, aborting after x attempts to remove the patch when no satisfactory MSX model is found to patch.
	ld	a,(#F4E0) ; Retrieve the counter.
	dec	a	  ; Subtract 1 from the counter.
	ld	(#F4E0),a ; Store the counter.
	jr	nz, Adding2 ; If it's not zero, do another full cycle.
	
	; Apply another patch at address F38F so it goes back to being call #F398, as it was initially. Nothing happened here. ;-)
	ld	a,098h
	ld	(#F390),a
	ld	a,0F3h
	ld	(#F391),a
	pop	af   ; Restore af to its initial values for the rest of the MSX's operations.
	jp	(ix) ; Jump as if nothing had happened, since Philips and similar models are not to be patched.
Adding4:
	; Apply another patch at address F38F so it goes back to being call #F398, as it was initially. Nothing happened here. ;-)
	ld	a,098h
	ld	(#F390),a
	ld	a,0F3h
	ld	(#F391),a
	pop	af ; Restore af to its initial values for the rest of the MSX's operations.
	ret	; Perform the long-awaited ret, leaving everything intact. (This is the ret that returns the load without running the internal ROM)	
	ret	; With the ret done, it's patched back to its original state, leaving the code intact and exiting cleanly.
	ret

	;---- End of the internal boot bypass. Created entirely by Aquijacks (Flashjacks)

NULL_OTHER_SLOT:; Check to cancel execution of another cartridge in slot 2 or higher.
	
	call	IDE_ON
	ld      a,(IDE_FLASHJACKS) ; Fetch the Flashjacks register. 
	and	00001000b ; Keep only the slot-2 cancellation flag.
	cp	008h ;	Check the slot-2 cancellation bit
	jp	nz,NULL_OTHER_SLOT_EXIT ; No correct flag was detected in the Flashjacks register, so nothing from the reset is executed.

	; Cancel execution in slots 2 and above.
	ld a,#40
        cp h
        jp z, NULL_OTHER_SLOT_EXIT
        ld IX,(0f674h)
        ld (IX-6),0C3h
        ld (IX-8),0EBh
        ld (IX-12),2
	jp NULL_OTHER_SLOT_EXIT ; Return control.

NULL_OTHER_SLOT_EXIT:
	call	IDE_OFF
	ret ; Return control.


;--- Subroutines for the INIT procedure

; Checks that FLASHJACKS appears at address 457 onward in the SD driver ID.
; Returns zero in a if found, or sets the carry flag if not found.
; It also dumps the first 100 bytes of the SD driver ID content into TEMP_WORK. 

INIT_CHECK_DEV:
	ld	hl,IDE_DATA
	ld	de,TEMP_WORK
	ld	bc,50*2	;Take the first 100 values of the SD driver ID
	ldir

	ld	a,(IDE_STATUS)		;Check status
	cp	01111111b		;Usually this means "no device"
	jp	z,INIT_CHECK_NODEV
	
TEST_FOR_FLASHJACKS:
	ld	hl,TEMP_WORK+27*2 ; Go to where FLASHJACKS should be
	ld	b,10 ; Number of bytes to compare.
	ld	de,DRIVER_N ; Name to compare against (FLASHJACKS)
	
TESTNAME_LOOP:
	ld	a,(de)	; Fetch what the FLASHJACKS constant points to
	inc	de	; Increment to the next byte
	ld	c,a	; Store it in c
	ld	a,(hl)	; Fetch the byte read from the SD driver ID
	inc	hl	; Increment to the next byte

	cp	c	; Compare a with c
	jp	nz,INIT_CHECK_NODEV	; If not equal, return "not found".
	djnz	TESTNAME_LOOP		; If there are bytes left to compare, go to the next one
	xor	a			; Output a zero in a		
	ret				; Return control.

INIT_CHECK_NODEV:
	scf				; Set the carry flag to 1.
	ret				; Return control.


;Print a device name.
;Input: 50 first bytes of IDENTIFY device on TEMP_WORK.

INIT_PRINT_NAME:
	ld	hl,TEMP_WORK+27*2
	ld	b,20
DEVNAME_LOOP:
	ld	c,(hl)
	inc	hl
	ld	a,(hl)
	inc	hl
	call	DRIVER_CHPUT
	ld	a,c
	call	DRIVER_CHPUT
	djnz	DEVNAME_LOOP

	ld	de,CRLF_S
	call	PRINT
	ret


;-----------------------------------------------------------------------------
;
; Obtain driver version
;
; Input:  -
; Output: A = Main version number
;         B = Secondary version number
;         C = Revision number

DRV_VERSION:
	; Deprecated in Nextor v3; kept harmless for legacy callers.
	xor	a
	ld	bc,0
	ret


;-----------------------------------------------------------------------------
;
; BASIC expanded statement ("CALL") handler.
; Works the expected way, except that CALBAS in kernel page 0
; must be called instead of CALBAS in MSX BIOS.

DRV_BASSTAT:
	scf
	ret


;-----------------------------------------------------------------------------
;
; BASIC expanded device handler.
; Works the expected way, except that CALBAS in kernel page 0
; must be called instead of CALBAS in MSX BIOS.

DRV_BASDEV:
	scf
	ret


;-----------------------------------------------------------------------------
;
; Extended BIOS hook.
; Works the expected way, except that it must return
; D'=1 if the old hook must be called, D'=0 otherwise.
; It is entered with D'=1.

DRV_EXTBIO:
	ret


;-----------------------------------------------------------------------------
;
; Direct calls entry points.
; Calls to addresses 7450h, 7453h, 7456h, 7459h and 745Ch
; in kernel banks 0 and 3 will be redirected
; to DIRECT0/1/2/3/4 respectively.
; Receives all register data from the caller except IX and AF'.

RESERVED_0:
	ld	a,RESULT_NOT_IMPLEMENTED
	ret

RESERVED_1:
	ld	a,RESULT_NOT_IMPLEMENTED
	ret

RESERVED_2:
	ld	a,RESULT_NOT_IMPLEMENTED
	ret

DRV_DIRECT0:
DRV_DIRECT1:
DRV_DIRECT2:
DRV_DIRECT3:
DRV_DIRECT4:
	ret


;-----------------------------------------------------------------------------
;
; Get driver configuration 
; (bit 2 of driver flags must be set if this routine is implemented)
;
; Input:
;   A = Configuration index
;   BC, DE, HL = Depends on the configuration
;
; Output:
;   A = 0: Ok
;       1: Configuration not available for the supplied index
;   BC, DE, HL = Depends on the configuration
;
; * Get number of drives at boot time (for device-based drivers only):
;   Input:
;     A = 1
;     B = 0 for DOS 2 mode, 1 for DOS 1 mode
;     C: bit 5 set if user is requesting reduced drive count
;        (by pressing the 5 key)
;   Output:
;     B = number of drives
;
; * Get default configuration for drive
;   Input:
;     A = 2
;     B = 0 for DOS 2 mode, 1 for DOS 1 mode
;     C = Relative drive number at boot time
;   Output:
;     B = Device index
;     C = LUN index

DRV_CONFIG:
	
	
	;ld a,1
	ret


;=====
;=====  BEGIN of DEVICE-BASED specific routines
;=====

;-----------------------------------------------------------------------------
;
; Read or write logical sectors from/to a logical unit
;
;Input:    Cy=0 to read, 1 to write
;          A = Device number, 1 to 7
;          B = Number of sectors to read or write
;          C = Logical unit number, 1 to 7
;          HL = Source or destination memory address for the transfer
;          DE = Address where the 4 byte sector number is stored
;Output:   A = Error code (the same codes of MSX-DOS are used):
;              0: Ok
;              .IDEVL: Invalid device or LUN
;              .NRDY: Not ready
;              .DISK: General unknown disk error
;              .DATA: CRC error when reading
;              .RNF: Sector not found
;              .UFORM: Unformatted disk
;              .WPROT: Write protected media, or read-only logical unit
;              .WRERR: Write error
;              .NCOMP: Incompatible disk
;              .SEEK: Seek error
;          B = Number of sectors actually read/written

DEV_RW:
	
	push	af

	ld	a,b	;Swap B and C
	ld	b,c
	ld	c,a
	pop	af
	push	af
	push	bc
	call	CHECK_DEV_LUN
	pop	bc
	jp	c,DEV_RW_NODEV

	dec	a
	jp	z,DEV_RW2
	ld	a,M_DEV
DEV_RW2:
	ld	b,a

	ld	a,c
	or	a
	jp	nz,DEV_RW_NO0SEC
	pop	af
	xor	a
	ld	b,0
	ret	
DEV_RW_NO0SEC:

	push	de
	pop	ix
	ld	a,(ix+3)
	and	11110000b
	jp	nz,DEV_RW_NOSEC	;Only 28 bit sector numbers supported

	call	IDE_ON

	ld	a,(ix+3)
	or	M_LBA
	or	b
	ld	(IDE_HEAD),a	;IDE_HEAD must be written first,
	ld	a,(ix)		;or the other IDE_LBAxxx and IDE_SECCNT
	ld	(IDE_LBALOW),a	;registers will not get a correct value
	ld	a,(ix+1)	;(blueMSX issue?)
	ld	(IDE_LBAMID),a
	ld	a,(ix+2)
	ld	(IDE_LBAHIGH),a
	ld	a,c
	ld	(IDE_SECCNT),a
	
	pop	af
	jp	c,DEV_DO_WR ; Jump if this is a write request.

	;---
	;---  READ
	;---
	
	call	WAIT_CMD_RDY
	jp	c,DEV_RW_ERR
	ld	a,20h
	push	bc	;Save sector count
	call	DO_IDE
	pop	bc
	
	jp	c,DEV_RW_ERR ; Check whether a failure occurred.
	call	DEV_RW_FAULT
	ret	nz

	ld	b,c	;Retrieve sector count
	ex	de,hl
DEV_R_GDATA:
	push	bc
	ld	hl,IDE_DATA
	ld	bc,512

BUCLE_R_GDATA:
	; Interruptions remain disabled from IDE_ON until IDE_OFF.
	ld	a,(IDE_STATUS)
	bit	BSY,a
	jp	nz,BUCLE_R_GDATA ; Checks at the start and lets execution continue once FLASHJACKS reports it can proceed.
	ldi_512 ; This is an ldir, 21% faster.

BUCLE_R_FIN:	
	ld	a,(IDE_STATUS)
	bit	BSY,a
	jp	nz,BUCLE_R_FIN ; Checks at the end and lets execution continue once FLASHJACKS reports it can proceed.
	pop	bc

	call	WAIT_IDE
	jp	c,DEV_RW_ERR ; Check whether a failure occurred.
	call	DEV_RW_FAULT
	ret	nz

	dec	b
	jp	nz,DEV_R_GDATA
	call	IDE_OFF
	xor	a
	ret
	
	;---
	;---  WRITE
	;---

DEV_DO_WR:
	call	WAIT_CMD_RDY
	jp	c,DEV_RW_ERR
	ld	a,30h
	push	bc	;Save sector count
	call	DO_IDE
	pop	bc
	jp	c,DEV_RW_ERR ; Check whether a failure occurred.

	ld	b,c	;Retrieve sector count
DEV_W_LOOP:
	push	bc
	ld	de,IDE_DATA
	ld	bc,512
	ldi_512 ; This is an ldir, 21% faster.
	pop	bc

	call	WAIT_IDE
	jp	c,DEV_RW_ERR ; Check whether the ERR status bit is set.
	call	DEV_RW_FAULT
	ret	nz
	
	dec	b	
	jp	nz,DEV_W_LOOP

	call	IDE_OFF
	xor	a
	ret

	;---
	;---  ERROR ON READ/WRITE
	;---

DEV_RW_ERR:
	ld	a,(IDE_ERROR)
	ld	b,a
	call	IDE_OFF
	ld	a,b	

	bit	NM,a	;Not ready
	jp	z,DEV_R_ERR1
	ld	a,NRDY
	ld	b,0
	ret
DEV_R_ERR1:

	bit	IDNF,a	;Sector not found
	jp	z,DEV_R_ERR2
	ld	a,RNF
	ld	b,0
	ret
DEV_R_ERR2:

	bit	WP,a	;Write protected
	jp	z,DEV_R_ERR3
	ld	a,WPROT
	ld	b,0
	ret
DEV_R_ERR3:

	ld	a,DISK	;Other error
	ld	b,0
	ret

	;--- Check for device fault
	;    Output: NZ and A=.DISK on fault

DEV_RW_FAULT:
	ld	a,(IDE_STATUS)
	and	M_DF	;Device fault
	ret	z

	call	IDE_OFF
	ld	a,DISK
	ld	b,0
	or	a
	ret

	;--- Termination points

DEV_RW_NOSEC:
	pop	af
	ld	a,RNF
	ld	b,0
	ret

DEV_RW_NODEV:
	pop	af
	ld	a,IDEVL
	ld	b,0
	ret

;-----------------------------------------------------------------------------
;
; Device information gathering
;
;Input:   A = Device index, 1 to 7
;         B = Information to return:
;             0: Basic information
;             1: Manufacturer name string
;             2: Device name string
;             3: Serial number string
;         HL = Pointer to a buffer in RAM
;Output:  A = Error code:
;             0: Ok
;             1: Device not available or invalid device index
;             2: Information not available, or invalid information index
;         When basic information is requested,
;         buffer filled with the following information:
;
;+0 (1): Numer of logical units, from 1 to 8. 1 if the device has no logical
;        drives (which is functionally equivalent to having only one).
;+1 (1): Flags, always zero
;
; The strings must be printable ASCII string (ASCII codes 32 to 126),
; left justified and padded with spaces. All the strings are optional,
; if not available, an error must be returned.
; If a string is provided by the device in binary format, it must be reported
; as an hexadecimal, upper-cased string, preceded by the prefix "0x".
; The maximum length for a string is 64 characters;
; if the string is actually longer, the leftmost 64 characters
; should be provided.
;
; In the case of the serial number string, the same rules for the strings
; apply, except that it must be provided right-justified,
; and if it is too long, the rightmost characters must be
; provided, not the leftmost.

DEV_INFO:
	or	a	;Check device index
	jp	z,DEV_INFO_BAD1
	cp	3
	jp	nc,DEV_INFO_BAD1

	call	MY_GWORK

	ld	c,a
	ld	a,b
	or	a
	jp	nz,DEV_INFO_STRING

	;--- Obtain basic information

	ld	a,(ix)
	or	a	;Device available?
	jp	z,DEV_INFO_BAD1

	ld	(hl),1	;One single LUN
	inc	hl
	ld	(hl),0	;Always zero
	xor	a
	ret

	;--- Obtain string information

DEV_INFO_STRING:
	push	hl
	push	bc
	push	hl
	pop	de
	inc	de
	ld	(hl)," "
	ld	bc,64-1
	ldir
	pop	bc
	pop	hl

	call	IDE_ON

	ld	a,c
	dec	a
	jp	z,DEV_INFO_STRING2
	ld	a,M_DEV

DEV_INFO_STRING2:
	ld	c,a	;C=Device flag for the HEAD register
	ld	a,b

	dec	a
	jp	z,DEV_INFO_ERR2	;Manufacturer name

	;--- Device name

	dec	a
	jp	nz,DEV_STRING_NO1

	ld	b,27
	call	DEV_STING_PREPARE
	jp	c,DEV_INFO_ERR1

	ld	b,20
DEV_STRING_LOOP:
	ld	de,(IDE_DATA)
	ld	a,d
	cp	33
	jp	nc,DEVSTRLOOP_1
	cp	126
	jp	c,DEVSTRLOOP_1
	ld	a," "
DEVSTRLOOP_1:
	ld	(hl),a
	inc	hl
	ld	a,e
	cp	33
	jp	nc,DEVSTRLOOP_2
	cp	126
	jp	c,DEVSTRLOOP_2
	ld	a," "
DEVSTRLOOP_2:
	ld	(hl),a
	inc	hl
	djnz	DEV_STRING_LOOP

	call	IDE_OFF
	xor	a
	ret

DEV_STRING_NO1:

	;--- Serial number

	dec	a
	jp	nz,DEV_INFO_ERR2	;Unknown string

	ld	b,10
	call	DEV_STING_PREPARE
	jp	c,DEV_INFO_ERR1

	ld	bc,44
	add	hl,bc	;Since the string is 20 chars long
	ld	b,10
	jp	DEV_STRING_LOOP
	
	;--- Termination with error

DEV_INFO_ERR1:
	call	IDE_OFF
	ld	a,1
	ret

DEV_INFO_BAD1:
	ld	a,1
	ret

DEV_INFO_ERR2:
	call	IDE_OFF
	ld	a,2
	ret



;Common processing for obtaining a device information string
;Input: B  = Offset of the string in the device information (words)
;       HL = Destination address for the string
;       C  = Device flag for the HEAD register
;Corrupts AF, DE

DEV_STING_PREPARE:
	call	WAIT_CMD_RDY
	ld	a,c		;Issue IDENTIFY DEVICE command
	ld	(IDE_HEAD),a
	ld	a,0ECh
	call	DO_IDE
	ret	c

	push	hl		;Fill destination with spaces
	push	bc
	push	hl
	pop	de
	inc	de
	ld	(hl)," "
	ld	bc,64-1
	ldir
	pop	bc
	pop	hl

DEV_STRING_SKIP:
	ld	de,(IDE_DATA)	;Skip device data until the desired string
	djnz	DEV_STRING_SKIP

	ret


;-----------------------------------------------------------------------------
;
; Obtain device status
;
;Input:   A = Device index, 1 to 7
;         B = Logical unit number, 1 to 7.
;             0 to return the status of the device itself.
;Output:  A = Status for the specified logical unit,
;             or for the whole device if 0 was specified:
;                0: The device or logical unit is not available, or the
;                   device or logical unit number supplied is invalid.
;                1: The device or logical unit is available and has not
;                   changed since the last status request.
;                2: The device or logical unit is available and has changed
;                   since the last status request
;                   (for devices, the device has been unplugged and a
;                    different device has been plugged which has been
;                    assigned the same device index; for logical units,
;                    the media has been changed).
;                3: The device or logical unit is available, but it is not
;                   possible to determine whether it has been changed
;                   or not since the last status request.
;
; Devices not supporting hot-plugging must always return status value 1.
; Non removable logical units may return values 0 and 1.

DEV_STATUS:
	set	0,b	;So that CHECK_DEV_LUN admits B=0

	call	CHECK_DEV_LUN ; Check the logical unit.
	ld	e,a
	ld	a,0
	ret	c

	call	IDE_ON	      ; Enable the IDE registers
	ld	a,(IDE_ERROR) ; Request the error codes.
	ld	b,a
	call	IDE_OFF	      ; Disable the IDE registers.
	ld	a,b	

	bit	MC,a	;Check whether an SD card change was detected
	jp	z,DEV_No_Cambio
	ld	a,2	;Report that the unit has changed.
	ret

DEV_No_Cambio:
	ld	a,1	;Report that the unit has not changed.
	ret


;-----------------------------------------------------------------------------
;
; Obtain logical unit information
;
;Input:   A  = Device index, 1 to 7.
;         B  = Logical unit number, 1 to 7.
;         HL = Pointer to buffer in RAM.
;Output:  A = 0: Ok, buffer filled with information.
;             1: Error, device or logical unit not available,
;                or device index or logical unit number invalid.
;         On success, buffer filled with the following information:
;
;+0 (1): Medium type:
;        0: Block device
;        1: CD or DVD reader or recorder
;        2-254: Unused. Additional codes may be defined in the future.
;        255: Other
;+1 (2): Sector size, 0 if this information does not apply or is
;        not available.
;+3 (4): Total number of available sectors.
;        0 if this information does not apply or is not available.
;+7 (1): Flags:
;        bit 0: 1 if the medium is removable.
;        bit 1: 1 if the medium is read only. A medium that can dinamically
;               be write protected or write enabled is not considered
;               to be read-only.
;        bit 2: 1 if the LUN is a floppy disk drive.
;+8 (2): Number of cylinders (0, if not a hard disk)
;+10 (1): Number of heads (0, if not a hard disk)
;+11 (1): Number of sectors per track (0, if not a hard disk)

LUN_INFO:
	call	CHECK_DEV_LUN
	jp	c,LUN_INFO_BAD

	ld	b,a
	call	IDE_ON
	ld	a,b

	push	hl
	pop	ix

	dec	a
	jp	z,LUN_INFO2
	ld	a,M_DEV
LUN_INFO2:
	ld	e,a
	call	WAIT_CMD_RDY	
	jp	c,LUN_INFO_ERROR
	ld	a,e

	ld	(IDE_HEAD),a

	ld	a,0ECh
	call	DO_IDE
	jp	c,LUN_INFO_ERROR

	;Set cylinders, heads, and sectors/track

	ld	hl,(IDE_DATA)	;Skip word 0
	ld	hl,(IDE_DATA)
	ld	(ix+8),l	;Word 1: Cylinders
	ld	(ix+9),h
	ld	hl,(IDE_DATA)	;Skip word 2
	ld	hl,(IDE_DATA)
	ld	(ix+10),l	;Word 3: Heads
	ld	hl,(IDE_DATA)
	ld	hl,(IDE_DATA)	;Skip words 4,5
	ld	hl,(IDE_DATA)
	ld	(ix+11),l	;Word 6: Sectors/track

	;Set maximum sector number

	ld	b,60-7	;Skip until word 60
LUN_INFO_SKIP1:
	ld	de,(IDE_DATA)
	djnz	LUN_INFO_SKIP1

	ld	de,(IDE_DATA)	;DE = Low word
	ld	hl,(IDE_DATA)	;HL = High word

	ld	(ix+3),e
	ld	(ix+4),d
	ld	(ix+5),l
	ld	(ix+6),h

	;Set sector size

	ld	b,117-62	;Skip until word 117
LUN_INFO_SKIP2:
	ld	de,(IDE_DATA)
	djnz	LUN_INFO_SKIP2

	ld	de,(IDE_DATA)	;DE = Low word
	ld	hl,(IDE_DATA)	;HL = High word

	ld	a,h	;If high word not zero, set zero (info not available)
	or	l
	ld	hl,0
	jp	nz,LUN_INFO_SSIZE

	ld	a,d
	or	e
	jp	nz,LUN_INFO_SSIZE
	ld	de,512	;If low word is zero, assume 512 bytes
LUN_INFO_SSIZE:
	ld	(ix+1),e
	ld	(ix+2),d

	;Set other parameters

	ld	(ix),0	  ;Block device
	ld	(ix+7), 1 ;bit 0 set to 1: it is a hot-plug removable medium (see +7 and its flags in the LUN_INFO description)

	call	IDE_OFF
	xor	a
	ret

LUN_INFO_ERROR:
	call	IDE_OFF
	ld	a,1
	ret

LUN_INFO_BAD:
	ld	a,1
	ret

;-----------------------------------------------------------------------------
;
; Physical format a device
;
;Input:   A = Device index, 1 to 7
;         B = Logical unit number, 1 to 7
;         C = Format choice, 0 to return choice string
;Output:
;        When C=0 at input:
;        A = 0: Ok, address of choice string returned
;            .IFORM: Invalid device or logical unit number,
;                    or device not formattable
;        HL = Address of format choice string (in bank 0 or 3),
;             only if A=0 returned.
;             Zero, if only one choice is available.
;
;        When C<>0 at input:
;        A = 0: Ok, device formatted
;            Other: error code, same as DEV_RW plus:
;            .IPARM: Invalid format choice
;            .IFORM: Invalid device or logical unit number,
;                    or device not formattable
;        B = Media ID if the device is a floppy disk, zero otherwise
;            (only if A=0 is returned)
;
; Media IDs are:
; F0h: 3.5" Double Sided, 80 tracks per side, 18 sectors per track (1.44MB)
; F8h: 3.5" Single sided, 80 tracks per side, 9 sectors per track (360K)
; F9h: 3.5" Double sided, 80 tracks per side, 9 sectors per track (720K)
; FAh: 5.25" Single sided, 80 tracks per side, 8 sectors per track (320K)
; FBh: 3.5" Double sided, 80 tracks per side, 8 sectors per track (640K)
; FCh: 5.25" Single sided, 40 tracks per side, 9 sectors per track (180K)
; FDh: 5.25" Double sided, 40 tracks per side, 9 sectors per track (360K)
; FEh: 5.25" Single sided, 40 tracks per side, 8 sectors per track (160K)
; FFh: 5.25" Double sided, 40 tracks per side, 8 sectors per track (320K)

DEV_FORMAT:
	ld	a,IFORM
	ret


;-----------------------------------------------------------------------------
;
; Execute direct command on a device
;
;Input:    A = Device number, 1 to 7
;          B = Logical unit number, 1 to 7 (if applicable)
;          HL = Address of input buffer
;          DE = Address of output buffer, 0 if not necessary
;Output:   Output buffer appropriately filled (if applicable)
;          A = Error code:
;              0: Ok
;              1: Invalid device number or logical unit number,
;                 or device not ready
;              2: Invalid or unknown command
;              3: Insufficient output buffer space
;              4-15: Reserved
;              16-255: Device specific error codes
;
; The first two bytes of the input and output buffers must contain the size
; of the buffer, not incuding the size bytes themselves.
; For example, if 16 bytes are needed for a buffer, then 18 bytes must
; be allocated, and the first two bytes of the buffer must be 16, 0.

DEV_CMD:
	ld	a,2
	ret


;=====
;=====  END of DEVICE-BASED specific routines
;=====


;=======================
; Subroutines
;=======================

;-----------------------------------------------------------------------------
;
; Enable or disable the IDE registers

;Note that bank 7 (the driver code bank) must be kept switched

IDE_ON:
	; Entering this routine starts the FlashJacks critical section.
	; Interrupts are disabled before the IDE mapping is changed.
	di
	ld	a,1+7*32
	ld	(IDE_BANK),a
	ret

IDE_OFF:
	; Every successful IDE_ON must finish through IDE_OFF.
	; Restore the normal ROM mapping and re-enable interrupts.
	ld	a,7*32
	ld	(IDE_BANK),a
	ei
	ret

;-----------------------------------------------------------------------------
;
; Wait the BSY flag to clear and RDY flag to be set
; if we wait for more than 5s, send a soft reset to IDE BUS
; if the soft reset didn't work after 5s return with error
;
; Input:  Nothing
; Output: Cy=1 if timeout after soft reset 
; Preserves: DE and BC

WAIT_CMD_RDY:
	push	de
	push	bc
	ld	de,1357		;Limit the wait to 5s
WAIT_RDY1:
	ld	b,255
WAIT_RDY2:
	ld	a,(IDE_STATUS)
	and	M_BSY+M_DRDY
	cp	M_DRDY
	jp	z,WAIT_RDY_END	;Wait for BSY to clear and DRDY to set		
	djnz	WAIT_RDY2	;End of WAIT_RDY2 loop
	dec	de
	ld	a,d
	or	e
	jp	nz,WAIT_RDY1	;End of WAIT_RDY1 loop
	scf
WAIT_RDY_END:
	pop	bc
	pop	de
	ret	
	
;-----------------------------------------------------------------------------
;
; Execute a command
;
; Input:  A = Command code
;         Other command registers appropriately set
; Output: Cy=1 if ERR bit in status register set, or on timeout

DO_IDE:
	ld	(IDE_CMD),a ; Send a command.
	; Falls through into WAIT_IDE to wait for DRQ/end of command.

;-----------------------------------------------------------------------------
;
; Wait for DRQ to be set, or for BSY to clear, after a command has been
; issued (via DO_IDE) or after transferring a 512-byte block during a
; multi-sector READ/WRITE.
;
; Previously there was no time limit: if the card got stuck
; (removed mid-operation, core failure, etc.) the Z80 would
; wait forever, and with interrupts disabled on top of that.
; The same ~5s timeout as WAIT_CMD_RDY is added here,
; returning Cy=1 (treated as an error) if it runs out.
;
; Input:  Nothing
; Output: Cy=1 if ERR bit in status register set, or on timeout
; Preserves: HL, DE, BC

WAIT_IDE:
	push	hl
	push	de
	push	bc
	ld	de,1357		;Limit the wait to 5s, same as WAIT_CMD_RDY
WAIT_IDE1:
	ld	b,255
WAIT_IDE2:
	nop	; Wait 50us
	nop	; Wait 50us
	ld	a,(IDE_STATUS)
	bit	DRQ,a
	jp	nz,WAIT_IDE_END
	bit	BSY,a
	jp	z,WAIT_IDE_END
	djnz	WAIT_IDE2	;End of WAIT_IDE2 loop
	dec	de
	ld	a,d
	or	e
	jp	nz,WAIT_IDE1	;End of WAIT_IDE1 loop

	;--- Timeout: no response within ~5s. Treated as an error
	;    (Cy=1), the same as if the ERR bit were set.
	pop	bc
	pop	de
	pop	hl
	scf
	ret

WAIT_IDE_END:
	pop	bc
	pop	de
	pop	hl
	rrca	; If bit 0 of status is 1, sends it to Cy, which is error bit 0 (ERR) of IDE_Status
	ret

;-----------------------------------------------------------------------------
;
; Read the keyboard matrix to see if ESC is pressed
; Output: Cy = 1 if pressed, 0 otherwise

CHECK_ESC:
	ld	b,7
	in	a,(0AAh)
	and	11110000b
	or	b
	out	(0AAh),a
	; Read from standard port A9h
	in      a, (0A9h)       ; First read (standard port)
	ld      c, a            ; Store in C
	; Read from alternate port DEh
	in      a, (0DEh)       ; Second read (alternate port)
	; Combine both reads with AND
	and     c               ; A = A9h AND DEh	
	bit	2,a
	jp	nz,CHECK_ESC_END
	scf
CHECK_ESC_END:
	ret

;-----------------------------------------------------------------------------
;
; Print a zero-terminated string on screen
; Input: DE = String address

PRINT:
	ld	a,(de)
	or	a
	ret	z
	call	DRIVER_CHPUT
	inc	de
	jp	PRINT


;-----------------------------------------------------------------------------
;
; Obtain the work area address for the driver
; Input: A=1  to obtain the work area for the master, 2 for the slave
; Preserves A

MY_GWORK:
	push	af
	xor	a
	EX AF,AF'
	XOR A
	LD IX,GWORK
	call CALBNK
	pop	af
	cp	1
	ret	z
	inc	ix
	inc	ix
	inc	ix
	inc	ix
	ret


;-----------------------------------------------------------------------------
;
; Check the device index and LUN
; Input:  A = device index, B = lun
; Output: Cy=0 if OK, 1 if device or LUN invalid
;         IX = Work area for the device
; Modifies F, C

CHECK_DEV_LUN:
	or	a	;Check device index
	scf
	ret	z
	cp	3
	ccf
	ret	c

	ld	c,a
	ld	a,b	;Check LUN number
	cp	1
	ld	a,c
	scf
	ret	nz

	push	hl
	push	de
	call	MY_GWORK
	pop	de
	pop	hl
	ld	c,a
	ld	a,(ix)
	or	a
	ld	a,c
	scf
	ret	z

	or	a
	ret

;----------------------------------------------------------------------------------
;Turn On Turbo CPU: MSX CIEL, Panasonic 2+,Panasonic Turbo R, special TurboCPU kits
;
;Input:	Nothing
;Output: Nothing 

putTURBO_CPU:
	
CHGTURCIEL	equ	01387h	; CIEL Expert3 bizarre turbo routine

_TURBO3:
;	; Expert 3 CIEL	
;	; Test if the CIEL change-turbo routine signature is in ROM
	ld	hl,CHGTURCIEL
	ld	de,CIELSIGN
	ld	c,2

_CIEL1:	ld	b,3
_CIEL2: ld	a,(hl)
	ld	ixh,a
	ld	a,(de)
	cp	ixh
	jp	nz,NOTCIEL
	inc	hl
	inc	de
	djnz	_CIEL2
	ld	hl,CHGTURCIEL+0Ch
	dec	c
	ld	a,c
	or	a
	jp	nz,_CIEL2
	call	CHGTURCIEL
	db	1	; Padding to make the CIELSIGN inert
CIELSIGN:	DEFB	0A7h,0FAh,093h,013h,0DBh,0B6h

NOTCIEL:			
	
;------------------------------------------------------------------------------			
				;Check for Panasonic 2+
	LD	A,8
	OUT 	(040H),A	;out the manufacturer code 8 (Panasonic) to I/O port 40h
	IN	A,(040H)	;read the value you have just written
	CPL			;complement all bits of the value
	CP	8		;if it does not match the value you originally wrote,
	JP	NZ,Not_WX	;it is not a WX/WSX/FX.
	XOR	A		;write 0 to I/O port 41h
	OUT	(041H),A	;and the mode changes to high-speed clock
	
		
	jp	end_turbo

Not_WX:  ld	a,(0180h)	;Turbo R or Turbo CPU kits with JUMP in 0180h
	cp	0c3h
		;no_turbo
	jp	nz,end_turbo
	ld	a,081h		;ROM Mode... for DRAM Mode-> 82h
	call	0180h

end_turbo:

	ret
;---------------------------------------------------------------


;=======================
; Strings
;=======================

V3_STR_DRIVER_NAME:
	db	"FlashJacks Nextor 3 driver",0
V3_STR_DRIVER_AUTHOR:
	db	"Aquijacks / Konamiman",0
V3_STR_HARDWARE_NAME:
	db	"FlashJacks IDE",0
V3_STR_HARDWARE_AUTHOR:
	db	"Aquijacks",0

INFO_S:
	db	"FLASHJACKS SD driver v"
	db	VER_MAIN+"0",".",VER_SEC+"0",".",VER_REV+"0",13,10
	db	"(c) Konamiman  2009",13,10
	db	"(c) Aquijacks  2026",13,10,13,10,0

SEARCH_S:
	db	"Buscando: ",0
DRIVER_N:
	db	"LFSAJHCASK",0 ; Compares this name at boot. Odd bytes paired with even ones.
NODEVS_S:
	db	"No encontrada",13,10,0
MASTER_S:
	db	"Unidad: ",0
CRLF_S:
	db	13,10,0
MODELO:
	db	"Modelo: ",0
M_MSX1:
	db	"MSX1",13,10,13,10,0
M_MSX2:
	db	"MSX2",13,10,13,10,0
M_MSX2M:
	db	"MSX2+",13,10,13,10,0
M_MSXR:
	db	"MSX TurboR",13,10,13,10,0
M_OCM:
	db	"OCM",13,10,13,10,0
M_NDTC:
	db	"No detectado",13,10,13,10,0

;-----------------------------------------------------------------------------
;
; Padding up to the required driver size

DRV_END:

	ds	3ED0h-(DRV_END - DRV_START)

	end


