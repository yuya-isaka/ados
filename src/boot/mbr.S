/* 定数を定義 */
#define VGA_TEXT_COLOR_80x25    0x03
#define NUM_RETRIES     3               /* # of retries for disk read */
#define ERRCODE_TIMEOUT 0x80            /* Error code: Timeout */
#define BOOTMON_SEG             0x0900  /* Memory where to load boot monitor */
#define BOOTMON_OFF             0x0000  /*  segment and offset [0900:0000] */
#define BOOTMON_SIZE            0x0020  /* Boot monitor size in sector */

    /* ラベルstartを外部ファイルから参照可能にする．リンカファイルからこのラベルを参照してる */
	.globl	start

	/* プログラム部を開始して，リアルモード用の16ビットコードのアセンブリであることを明治*/
	.text
	.code16

start:
	cld		/* Clear Direction Flag ストリング命令のdi/siの方向を減算方向にするフラグをクリアする　*/
	        /*つまり小さい方向から大きい方向に実行する BIOSからの起動時はフラグが未定なのでこの命令実行 */
	cli     /* Clear Interrupt Flag. Interrupt Flagをクリアし，割り込みを無効にする．*/
	        /*（この後スタックをセットするため，ここで割り込みが発生するとスタックが壊れる可能性があるから．） */

	/* Setup the stack (below $start = 0x7c00) */
	xorw	%ax,%ax /* 同じレジスタを指定したXOR命令を実行して，同じレジスタに戻すことでその内容をゼロにすることができる */
	/* movw は16ビットのデータのmov命令 */
	movw	%ax,%ss /* スタックセグメントを0に設定 */
	movw	$start,%sp /* スタックポインタをstartラベルの場所，すなわち0x7c00に設定している */
	                   /* -> つまり，MBRのプログラムが0x7c00から上のメモリ領域に配置され，スタックはその下に伸びていくようにする*/
	/* メモリの中にはBIOSやシステムで使用している領域があるが，0x7c00からしばらく下は空いているからここをスタックに使う*/

	/* Reset data segment registers */
	/* データセグメント（セグメントレジスタ）dsとesを0で初期化*/
	/*　メッセージ表示で使う */
	movw	%ax,%ds
	movw	%ax,%es
	/*　ここまででスタックのセットアップが終わり*/

	sti /* 割り込みを有効にする．（スタック終わったから）*/
	/* 文字列の画面表示などはBIOSの機能を割り込み命令越しで使うので，割り込みは有効にする必要がある．*/

	/* Save drive information */
	/* BIOSからの起動時に，ブートドライブ（フロッピー，HDD/SSD，USB）のBIOS内部でのドライブ番号（管理ID）が%dlレジスタに入っている*/
	/* .dataセグメントのdriveラベルの場所に保存する．*/
	/* movbは8ビット命令？？ */
	movb	%dl,drive

	/* Set the video mode to 16-bit color text mode */
	movb	$VGA_TEXT_COLOR_80x25,%al /*画面モードをVGAカラーテキストの80列25行モードにする*/
	movb	$0x00,%ah
	int	$0x10 /* ディスプレイ関係のBIOSサービスはVideo BIOS servicesとして割り込み番号10版への割り込みで提供されている*/

	/* Get drive parameters */
	xorw	%ax,%ax
	movw	%ax,%es
	movw	%ax,%di
	movb	$0x08,%ah
	int	$0x13
	jc	disk_error

	/* Save the drive information (CHS) */
	incb	%dh		/* Get # of heads (%dh: last index of heads) */
	movb	%dh,heads
	movb	%cl,%al		/* %cl[5:0]: last index of sectors per track */
	andb	$0x3f,%al	/*  N.B., sector is one-based numbering */
	movb	%al,sectors
	movb	%ch,%al         /* %cx[7:6]%cx[15:8]: last index of cylinders */
				/*  then copy %cx[15:8] to %al */
	movb	%cl,%ah		/* Lower byte to higher byte */
	shrb	$6,%ah		/* Pick most significant two bits */
	incw	%ax		/*  N.B., cylinder starting with 0 */
	movw	%ax,cylinders

	/* Load boot monitor */
	movb	drive,%dl
	movw	$BOOTMON_SIZE,%cx/* Specify boot monitor size */
	movw	$1,%ax
	movw	$BOOTMON_SEG,%bx
	movw	%bx,%es		/* Buffer address pointer (Segment) */
	movw	$BOOTMON_OFF,%bx/* Buffer address pointer (Offset) */
	call	read		/* Read %cx sectors starting at LBA %ax on */
				/*  drive %dl into %es:[%bx] */

	/* Jump to boot monitor */
	ljmp	$BOOTMON_SEG,$BOOTMON_OFF

/*
 * Load sectors from the disk
 * Parameters:
 *   %dl: drive
 *   %cx: # of sectors to read
 *   %ax: Position in LBA
 *   %es:(%bx): Buffer
 */
read:
	pushw	%bp
	movw	%sp,%bp
	/* Save registers */
	movw	%ax,-2(%bp)
	movw	%bx,-4(%bp)
	movw	%cx,-6(%bp)
	movw	%dx,-8(%bp)
	/* Prepare space for local variables */
	/* u16 counter -10(%bp) */
	subw	$10,%sp
	/* Reset counter */
	xorw	%ax,%ax
	movw	%ax,-10(%bp)
1:
	movw	-2(%bp),%ax	/* Restore %ax */
	addw	-10(%bp),%ax	/* Current LBA */
	call	lba2chs		/* Convert LBA (%ax) to CHS (%cx,%dh) */
	call	read_sector	/* Read a sector */
	/* Next 512-byte buffer */
	addw	$512,%bx
	/* Increment the counter */
	movw	-10(%bp),%ax
	incw	%ax
	movw	%ax,-10(%bp)
	/* More sectors to read? */
	cmpw	-6(%bp),%ax
	jb	1b		/* Read more sectors */
	/* Restore the saved registers */
	movw	-8(%bp),%dx
	movw	-6(%bp),%cx
	movw	-4(%bp),%bx
	movw	-2(%bp),%ax
	movw	%bp,%sp
	popw	%bp
	ret

/*
 * Load one sector from the disk
 * Parameters:
 *   %dl: drive
 *   %cx, %dh: CHS (%cx[7:6]%cx[15:8] ,%dh, %cx[5:0])
 *   %es:(%bx): Buffer
 */
read_sector:
	pushw	%bp
	movw	%sp,%bp
	/* Save registers */
	movw	%ax,-2(%bp)
	/* Prepare space for local variables */
	/* u16 retries -4(%bp); retry counter  */
	/* u16 error -6(%bp); error code  */
	subw	$6,%sp
	/* Reset retry counter */
	xorw	%ax,%ax
	movw	%ax,-4(%bp)
1:
	/* Read a sector from the drive */
	movb	$0x02,%ah
	movb	$1,%al
	int	$0x13
	jnc	2f		/* Jump if success */
	movw	%ax,-6(%bp)	/* Save the error code */
	movw	-4(%bp),%ax
	incw	%ax
	movw	%ax,-4(%bp)
	cmpw	$NUM_RETRIES,%ax
	movw	-6(%bp),%ax	/* Restore the error code */
	ja	disk_error	/* Exceeded the maximum number of retries */
	jmp	1b
2:
	/* Restore saved registers */
	movw	-2(%bp),%ax
	movw	%bp,%sp
	popw	%bp
	ret

/*
 * LBA to CHS
 * Parameters:
 *   %ax: LBA
 * Return values:
 *   %cx, %dh: CHS (%cx[7:6]%cx[15:8] ,%dh, %cx[5:0])
 */
lba2chs:
	/* Save registers */
	pushw	%ax
	pushw	%bx
	pushw	%dx
	/* Compute sector number */
	xorw	%bx,%bx
	movw	%bx,%dx
	movw	%bx,%cx
	movb	sectors,%bl
	divw	%bx		/* %dx:%ax / %bx; %ax:quotient, %dx:remainder */
	incw	%dx		/* Sector number is one-based numbering */
	movb	%dl,%cl		/* Sector: %cx[5:0] */
	/* Compute head and track (cylinder) numbers */
	xorw	%bx,%bx
	movw	%bx,%dx
	movb	heads,%bl
	divw	%bx		/* %dx:%ax / %bx; %ax:quotient, %dx:remainder */
	movb	%al,%ch		/* Cylinder[7:0]: %cx[7:6]%cx[15:8] */
	shlb	$6,%ah
	orb	%ah,%cl
	movw	%dx,%bx		/* %dl: Head */
	popw	%dx		/* Restore %dx */
	movb	%bl,%dh		/* Head */
	/* Restore registers */
	popw	%bx
	popw	%ax
	ret

/*
 * Display a null-terminated string
 * Parameters:
 *   %ds:(%si): Pointer to the string
 * Unpreserved registers: %ax
 */
 /* NULL-terminateされた文字列をディスプレイに表示 */
 /*
 * %ds:(%si)から１文字ずつ読んで，INT 10h, AH=0Ehでテレタイプモードで書き込む
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

/*
 * Display the read error message (%ah = error codee)
 * Parameters:
 *   %ds:(%si): Pointer to the string
 * Unpreserved registers: %es, %ax, %di
 */
disk_error:
	pushw	%bx
	movb	%ah,%al
	movw	$error_code,%di
	xorw	%bx,%bx
	movw	%bx,%es
	call	hex8
	movw	$msg_error,%si
	call	putstr
	popw	%bx
	ret

/*
 * Convert %al to hex characters, and save the result to %es:(%di)
 * Parameters:
 *   %es:(%di): Pointer to the buffer to store the result (2 bytes)
 *   %al: Byte to be converted to hex characters
 * Unpreserved registers: %al, %di
 */
hex8:
	pushw	%ax
	shrb	$4,%al		/* Get the most significant 4 bits in %al */
	call	hex8.allsb
	popw	%ax
hex8.allsb:
	andb	$0xf,%al	/* Get the least significant 4 bits in %al */
	cmpb	$0xa,%al	/* CF=1 if %al < 10 */
	sbbb	$0x69,%al	/* %al <= %al - (0x69 + CF) */
	das			/* Adjust BCD */
	orb	$0x20,%al	/* To lower case */
	stosb			/* Save chars to %es:(%di) and inc %di */
	ret

	/* Data segment */
	.data

drive:
	.byte	0
heads:
	.byte	0
cylinders:
	.word	0
sectors:
	.byte	0
msg_error:
	.ascii	"Disk error: 0x"
error_code:
	.asciz	"00\r"
