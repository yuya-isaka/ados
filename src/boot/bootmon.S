	.globl	bootmon

	/* Code segment */
	.text
	.code16

/*
 * Boot monitor (from MBR)
 *   %cs:%ip=0x0900:0x0000 (=0x9000)
 *   %dl: drive
 *   %ds: 0x0000
 */
bootmon:
	cld

	/* Display welcome message */
	movw	$msg_welcome,%ax
	movw	%ax,%si
	call	putstr

halt:
	hlt
	jmp	halt


/*
 * Display a null-terminated string
 * Parameters:
 *   %ds:(%si): Pointer to the string
 * Unpreserved registers: %ax
 */
putstr:
putstr.load:
	lodsb			/* Load %ds:(%si) to %al, then incl %si */
	testb	%al,%al
	jnz	putstr.putc
	xorw	%ax,%ax
	ret
putstr.putc:
	call	putc
	jmp	putstr
putc:
	pushw	%bx
	movw	$0x7,%bx
	movb	$0xe,%ah
	int	$0x10
	popw	%bx
	ret


	/* Data segment */
	.data

msg_welcome:
	.asciz	"Welcome to advos\r\n\n"