/*
 * File      : context_gcc.S
 * This file is part of RT-Thread RTOS
 * COPYRIGHT (C) 2009 - 2013, RT-Thread Development Team
 *
 * The license and distribution terms for this file may be
 * found in the file LICENSE in this distribution or at
 * http://www.rt-thread.org/license/LICENSE
 *
 * Change Logs:
 * Date         Author    Notes
 * 2010-01-25   Bernard      first version
 * 2012-06-01   aozima       set pendsv priority to 0xFF.
 * 2012-08-17   aozima       fixed bug: store r8 - r11.
 * 2013-02-20   aozima       port to gcc.
 */
 
	.cpu 	cortex-m3
	.fpu 	softvfp
	.syntax	unified
	.thumb
	.text

	.equ	ICSR, 0xE000ED04 				/* interrupt control state register */
	.equ	PENDSVSET_BIT, 0x10000000 		/* value to trigger PendSV exception */
	
	.equ	SHPR3, 0xE000ED20 				/* system priority register (3) */
	.equ	PENDSV_PRI_LOWEST, 0x00FF0000 	/* PendSV priority value (lowest) */

/*
 * rt_base_t rt_hw_interrupt_disable();
 */
	.global rt_hw_interrupt_disable
	.type rt_hw_interrupt_disable, %function
rt_hw_interrupt_disable:
	MRS		R0, PRIMASK
	CPSID	I
	BX		LR

/*
 * void rt_hw_interrupt_enable(rt_base_t level);
 */
	.global rt_hw_interrupt_enable
	.type rt_hw_interrupt_enable, %function
rt_hw_interrupt_enable:
	MSR		PRIMASK, R0
	BX		LR

/*
 * void rt_hw_context_switch(rt_uint32 from, rt_uint32 to);
 * R0 --> from
 * R1 --> to
 */
	.global rt_hw_context_switch_interrupt
	.type rt_hw_context_switch_interrupt, %function
	.global rt_hw_context_switch
	.type rt_hw_context_switch, %function
rt_hw_context_switch_interrupt:
rt_hw_context_switch:
	/* set rt_thread_switch_interrupt_flag to 1 */
	LDR 	R2, =rt_thread_switch_interrupt_flag
	LDR 	R3, [R2]
	CMP 	R3, #1
	BEQ 	_reswitch
	MOV 	R3, #1
	STR 	R3, [R2]

	LDR 	R2, =rt_interrupt_from_thread	/* set rt_interrupt_from_thread */
	STR 	R0, [R2]

_reswitch:
	LDR 	R2, =rt_interrupt_to_thread		/* set rt_interrupt_to_thread */
	STR 	R1, [R2]

	LDR		R0, =ICSR      		/* trigger the PendSV exception (causes context switch) */
	LDR		R1, =PENDSVSET_BIT
	STR		R1, [R0]
	BX		LR

/* R0 --> swith from thread stack
 * R1 --> swith to thread stack
 * psr, pc, LR, R12, R3, R2, R1, R0 are pushed into [from] stack
 */
	.global PendSV_Handler
	.type PendSV_Handler, %function
PendSV_Handler:
	/* disable interrupt to protect context switch */
	MRS		R2, PRIMASK
	CPSID	I

	/* get rt_thread_switch_interrupt_flag */
	LDR		R0, =rt_thread_switch_interrupt_flag
	LDR		R1, [R0]
	CBZ		R1, pendsv_exit			/* pendsv aLReady handled */

	/* clear rt_thread_switch_interrupt_flag to 0 */
	MOV		R1, #0
	STR		R1, [R0]

	LDR		R0, =rt_interrupt_from_thread
	LDR		R1, [R0]
	CBZ		R1, swtich_to_thread    /* skip register save at the first time */

	MRS		R1, PSP					/* get from thread stack pointer */
	STMFD	R1!, {R4 - R11}			/* push R4 - R11 register */
	LDR		R0, [R0]
	STR		R1, [R0]				/* update from thread stack pointer */

swtich_to_thread:
	LDR		R1, =rt_interrupt_to_thread
	LDR		R1, [R1]
	LDR		R1, [R1]				/* load thread stack pointer */

	LDMFD	R1!, {R4 - R11}			/* pop R4 - R11 register */
	MSR		PSP, R1					/* update stack pointer */

pendsv_exit:
	/* restore interrupt */
	MSR		PRIMASK, R2

	ORR		LR, LR, #0x04
	BX		LR

/*
 * void rt_hw_context_switch_to(rt_uint32 to);
 * R0 --> to
 */
	.global rt_hw_context_switch_to
	.type rt_hw_context_switch_to, %function
rt_hw_context_switch_to:
	LDR		R1, =rt_interrupt_to_thread
	STR		R0, [R1]

	/* set from thread to 0 */
	LDR		R1, =rt_interrupt_from_thread
	MOV		R0, #0
	STR		R0, [R1]

	/* set interrupt flag to 1 */
	LDR 	R1, =rt_thread_switch_interrupt_flag
	MOV 	R0, #1
	STR 	R0, [R1]

	/* set the PendSV exception priority */
	LDR		R0, =SHPR3
	LDR		R1, =PENDSV_PRI_LOWEST
	LDR.W   R2, [R0,#0]				/* read */
	ORR     R1, R1, R2				/* modify */
	STR     R1, [R0]				/* write-back */

	LDR		R0, =ICSR				/* trigger the PendSV exception (causes context switch) */
	LDR		R1, =PENDSVSET_BIT
	STR		R1, [R0]

	CPSIE	I						/* enable interrupts at processor level */

	/* never reach here! */

/* compatible with old version */
	.global rt_hw_interrupt_thread_switch
	.type rt_hw_interrupt_thread_switch, %function
rt_hw_interrupt_thread_switch:
	BX		LR
	NOP

	.global HardFault_Handler
	.type HardFault_Handler, %function
HardFault_Handler:
    /* get current context */
    MRS     R0, PSP                 /* get fault thread stack pointer */
    PUSH    {LR}
    BL      rt_hw_hard_fault_exception
    POP     {LR}

    ORR     LR, LR, #0x04
    BX      LR

/*
 * rt_uint32_t rt_hw_interrupt_check(void);
 * R0 --> state
 */
	.global rt_hw_interrupt_check
	.type rt_hw_interrupt_check, %function
rt_hw_interrupt_check:
	MRS     R0, IPSR
	BX		LR
