%define SCREEN_WIDTH  320
%define SCREEN_HEIGHT 200

%define MAPCOLUMNS 60
%define SCREENCOLUMNS 20
%define SCREENROWS 12

%define HUD_HEIGHT 8


[ORG 0x100]

START:
  ;set up our own stack
  MOV AX, CS
  MOV SS, AX
  MOV SP, stackTop

  ;shrink our COM program block to just what we need
  MOV ES, AX
  MOV BX, programEnd + 15
  SHR BX, 4
  MOV AH, 4Ah
  INT 21H

  ;allocate 64,000 bytes (4000 paragraphs) for framebuffer
  MOV BX, 4000
  MOV AH, 48H
  INT 21H
  MOV [bufferSegment], AX

  ;set VGA Mode 13h (320x200, 256 colors)
  MOV AX, 0013H
  INT 10H


;AH 11h has character generator fucntions
;AL 30h specifies get font unformation
;it returns a pointer to alpahabet table. segment in ES and offset in BP
;BH 03h specifies we want 8x8 font size
  MOV AX, 1130H
  MOV BH, 03H
  INT 10H
  MOV [fontSegment], ES
  MOV [fontOffset], BP

  ;int 16h and int 21h is usually used with AH 0x00 or 0x01 for keybaord interrupts.
  ;but it only allows one input at a time make jumping while running impossible.
  ;hence we have to make our own keyboard interrupt handler

  ;we fetch interrupt vector for keybaord. it gives us offset in bx and segment in ax.
  ;we save in memory. this is because we need to reset to old keyHandler after our program finishes.
  ;once thats done save address of our own keyHandler into the IVT (interrupt vector table)
  MOV AX, 0x3509
  INT 0x21
  ;with int 21H, AH 35H means fetch interrupt vector. AL 09 specifies which vector (09H is for keybaord)
  MOV WORD [oldInterrupt9Offset], BX
  MOV AX, ES
  MOV WORD [oldInterrupt9Segment], AX
  ;with int 21H, AH 35H means write on interrupt vector. AL 09 specifies which vector (09H is for keybaord)
  MOV DX, keyHandler
  MOV AX, 0x2509
  INT 0x21

gameLoop:
  ;always ensure ES points to the backbuffer before drawing
  MOV AX, [bufferSegment]
  MOV ES, AX

  CALL input
  CALL gravity
  CALL checkCoins
  CALL updateCamera
  CALL HUD
  CALL sky
  CALL drawMap
  CALL drawMario  
  CALL screenSync
  CALL displayFrame
  JMP gameLoop

; keyhandler is not called by us it is called whenever a key is pressed
; this means it can be called during instruction. this is why it does not only push IP but also but also CS and flags
; this means it requires special return called iret
; we must also push all registers we use in keyhandler incase it had something valuable in it
; it simply checks whihc key is pressed and updates keydown array
keyHandler:
  PUSH AX
  PUSH BX
  PUSH CX
  MOV CX, 1
  XOR AH, AH
  IN AL, 0x60;keybaord interrupt key
  ;in from port 60 gives us keycode in first 0 to 6 bits and 1 or 0 in last bit depending if pressed or released
  TEST AL, 10000000b ;checking if 7th bit on(if pressed or not)
  JZ .pressed
  AND AL, 0X7F; (0111 1111 clearing last bit)
  XOR CX, CX
.pressed:
  MOV BX, AX
  MOV BYTE [CS:keyDown+ BX], CL; if not pressed cl will be 0. if pressed cl is 1
.done:
;ran into an issue. when we press enter on to run a program, the enter was pressed before program execution
;but released afterwards. this cause an issue where irq1 (keybaord interrupt request line) gets blocked as it.
;to reset such an issue, we must turn port 0x61 bit 7 on and off.
;odd that it only happened now and not before. unsure about the reason
  IN AL, 0x61
  OR AL, 10000000b; turn bit 7 on
  OUT 0x61, AL ; send back bit 7 as 1
  AND AL, 01111111b; turn bit 7 off
  OUT 0x61, AL ; send back bit 7 as 0
  
  MOV AL, 0x20 ; moving 0x20 into al and then feeding to PIC tells it interrupt has finished. and code can continue now
  OUT 0x20, AL;port 20 is interrupt controller
  POP CX
  POP BX
  POP AX
  IRET; need to used iret instead of ret for interrupts

resetLevel:
;wait 1 second
  MOV CX, 70 ;screens are 70hz in 8086 vga
  .pauseLoop:
  CALL screenSync
  LOOP .pauseLoop

;reset worldMap using initialworldMap
  PUSH ES
  MOV AX, DS
  MOV ES, AX
  MOV SI, initialworldMap
  MOV DI, worldMap
  MOV CX, (MAPCOLUMNS * 12) / 2
  REP MOVSW
  POP ES
;reset all var
  MOV WORD [marioWorldY], 120
  MOV WORD [marioWorldX], 20
  MOV WORD [marioVelX], 0
  MOV WORD [marioVelY], 0
  MOV WORD [marioSubX], 0
  MOV WORD [marioSubY], 0
  MOV WORD [cameraX], 0
  MOV BYTE [isOnGround], 0
  MOV WORD [coinsCollected], 0
  MOV WORD [currentMarioTable], marioTable

  ret

terminate:
  ;return to standard text mode
  MOV AX, 0003H
  INT 10H

  ;restore old interrupt in ivt
  MOV DX, [oldInterrupt9Offset]
  MOV AX, [oldInterrupt9Segment]
  MOV DS, AX
  MOV AX, 0x2509
  INT 0x21

  MOV AX, CS
  MOV DS, AX; place ds back at right address

  ;free the framebuffer memory
  MOV ES, [bufferSegment]
  MOV AH, 49H
  INT 21H

  MOV AX, 4C00H
  INT 21H

%include "mario/render.asm"
%include "mario/player.asm"
%include "mario/data.asm"
