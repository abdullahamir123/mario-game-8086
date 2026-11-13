%define SCREEN_WIDTH  320
%define SCREEN_HEIGHT 200

%define MARIOHEIGHT 40
%define MARIOWIDTH  20

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

gameLoop:
  ;always ensure ES points to the backbuffer before drawing
  MOV AX, [bufferSegment]
  MOV ES, AX

  CALL sky
  CALL ground

;get key from keybaord
  MOV AH, 0x01
  INT 0x16
  JZ .skipKey
  MOV AH, 0x00
  INT 0x16

  CMP AH, 0x4B
  JE .walkLeft
  CMP AL, 'A'
  JE .walkLeft
  CMP AL, 'a'
  JE .walkLeft

  CMP AH, 0x4D
  JE .walkRight
  CMP AL, 'D'
  JE .walkRight
  CMP AL, 'd'
  JE .walkRight

  CMP AL, ' '  ;check if button pressed is space 
  JE .jump     ; got to jump if space pressed
  CMP AH, 0x39 ; scan code (space button)
  JE .jump     

  CMP AL, 0x1B
  JE terminate

  JMP .skipKey

.walkLeft:
  SUB WORD [marioWorldX], 2
  JMP .skipKey

.walkRight:
  ADD WORD [marioWorldX], 2
  JMP .flushBuffer ;clear extra buffered keys

.jump:
CMP BYTE [isOnGround], 1 ;check if mario on ground (1 means on ground and 0 means in sky)
JNE .flushBuffer ; if mario in space then go back to flush buffer
MOV WORD [marioVelY],-10 ;initial upward velocity(i choosed a random value)
MOV BYTE [isOnGround],0 ; move mario to sky (do a jump)
JMP .flushBuffer  ; clear extra buffered keys

;flash buffer. if multiple inputs in our buffer only one will be taken. (stop moving instantly on stop pressing)
.flushBuffer:
  MOV AH, 01H
  INT 16H
  JZ .skipKey
  MOV AH, 00H
  INT 16H
  JMP .flushBuffer

.skipKey: ;gravity and ground checks
  ADD WORD [marioVelY],1       ; pulls down mario by 1
  MOV AX , [marioVelY]          ; put vertical velocity in AX to add it to mariowordly
  ADD [marioWorldY],AX          ;moves mario up or down
  CMP  WORD [marioWorldY],120   ;checking if mario on ground
  JL .draw                      ; jump if mario still in air
  MOV WORD [marioWorldY],120    ; keeping mario in air
  MOV WORD [marioVelY],0         ;vertical velcity =0
  MOV BYTE [isOnGround],1      ; making it went back to ground so we can jump again
.draw:
  CALL drawMario

;0X03da is vga port for status
;only imp port is 3rd (counting from 0).
;if bit 3 is 0, currently drawing. if we call new display frame, we get screen tear
;if bit 3 is 1, it currentl reseting itself to pizel 0.
;loop1: wait until drawing starts
;loop2: once drawing start. wait until reset comes
;we check until it gets 1 and then display frame.
screenSync:
  MOV DX, 0x03DA
.waitEnd:
  IN AL, DX
  TEST AL, 00001000B
  JNZ .waitEnd
.waitStart:
  IN AL, DX
  TEST AL, 00001000B
  JZ .waitStart

  CALL displayFrame
  JMP gameLoop

terminate:
  ;return to standard text mode
  MOV AX, 0003H
  INT 10H

  ;free the framebuffer memory
  MOV ES, [bufferSegment]
  MOV AH, 49H
  INT 21H

  MOV AX, 4C00H
  INT 21H


sky:
  cld
  XOR DI, DI
  MOV AL, 77
  MOV CX, (160 * SCREEN_WIDTH)
  REP STOSB
  RET

ground:
  cld
  MOV DI, (160 * SCREEN_WIDTH)
  MOV AL, 184
  MOV CX, (40 * SCREEN_WIDTH)
  REP STOSB
  RET

drawMario:
  MOV CX, 320;
  MOV AX, [marioWorldY]
  MUL CX
  ADD AX, [marioWorldX]
  MOV DI, AX
  MOV DX, MARIOHEIGHT
.outer:
  MOV CX, MARIOWIDTH
  MOV AL, 4
  REP STOSB
  ADD DI, (SCREEN_WIDTH - MARIOWIDTH)
  DEC DX
  JNZ .outer
  RET

displayFrame:
  PUSH DS
  MOV AX, [bufferSegment]
  MOV DS, AX
  MOV AX, 0xA000
  MOV ES, AX

  cld
  XOR SI, SI
  XOR DI, DI
  MOV CX, 32000  ; 32,000 words = 64,000 bytes
  REP MOVSW

  POP DS
  RET

;mario: dw (120 * SCREEN_WIDTH + 20)
marioWorldX: dw 20
marioWorldY: dw 120
marioVelY: dw 0 ; mario velocity
isOnGround: db 1
bufferSegment: dw 0

stackSpace: times 1024 db 0
stackTop:

programEnd:
