HUD:; drawing the top bar for score at end
  XOR DI, DI
  XOR AX, AX
  MOV CX, (SCREEN_WIDTH*HUD_HEIGHT)/2
  REP STOSW;black background on hud

  MOV DI, 8
  MOV SI, coinText
  CALL drawString
 
  MOV AX, [coinsCollected]
  CALL drawNumber
  
  MOV DI, 250 
  MOV SI, livesText 
  CALL drawString
  
  MOV AL, [lives]
  XOR AH, AH
  CALL drawNumber
  ret

sky:
  MOV DI, (SCREEN_WIDTH * HUD_HEIGHT)
  MOV AL, 77
  MOV AH, 77
  MOV CX, ((SCREEN_HEIGHT-HUD_HEIGHT) * SCREEN_WIDTH)/2
  REP STOSW
  RET


startScreen:
  ;clear backbuffer to black
  MOV AX, [bufferSegment]
  MOV ES, AX
  XOR DI, DI
  XOR AX, AX
  MOV CX, 32000
  REP STOSW

  ;draw big 16x16 title: "SUPER MARIO" (11 chars * 16px = 176px wide, centered at X=72, Y=70)
  MOV DI, (70 * SCREEN_WIDTH) + 72
  MOV SI, titleText
  CALL drawString2x

  ;draw 8x8 subtitle: "PRESS ENTER TO START" (20 chars * 8px = 160px wide, centered at X=80, Y=120)
  MOV DI, (120 * SCREEN_WIDTH) + 80
  MOV SI, startText
  CALL drawString

  CALL screenSync
  CALL displayFrame

  ;wait loop for ENTER (scancode 0x1C) or ESC (0x01)
.waitLoop:
  CMP BYTE [keyDown + 0x01], 1
  JE terminate
  CMP BYTE [keyDown + 0x1C], 1
  JNE .waitLoop

  ;clear Enter key so game doesn't receive it
  MOV BYTE [keyDown + 0x1C], 0
  RET

; freezes game in place, draws "PAUSED" over the frame, and waits for 'P' again
pauseMenu:
    MOV AX, [bufferSegment]
    MOV ES, AX
    MOV BX, 100 ; height
    MOV DI, 50*SCREEN_WIDTH+50
.loopBlackBox:
    XOR AX, AX
    MOV CX, 220 ; width
    REP STOSB ; draw one row
    ADD DI, SCREEN_WIDTH - 220 ; move to next row
    DEC BX
    JNZ .loopBlackBox

  ;wait until 'P' is released so it doesn't instantly unpause
.waitRelease1:
  CMP BYTE [keyDown + 0x19], 0
  JNE .waitRelease1

  ;draw big 16x16 "PAUSED" in the center over the frozen game frame
  ; 6 chars * 16px = 96px wide, centered at X = 112, Y = 90
  MOV DI, (90 * SCREEN_WIDTH) + 112
  MOV SI, pausedText
  CALL drawString2x

  CALL screenSync
  CALL displayFrame

  ;wait loop until 'P' is pressed again (or ESC to quit)
.waitPress:
  CMP BYTE [keyDown + 0x01], 1
  JE terminate
  CMP BYTE [keyDown + 0x19], 1
  JNE .waitPress

  ;wait until 'P' is released before returning to the game
.waitRelease2:
  CMP BYTE [keyDown + 0x19], 0
  JNE .waitRelease2
  RET


; black screen with "GAME OVER", holds for ~1.5 seconds, then resets the level
deathScreen:
  ;clear buffer to black
  MOV AX, [bufferSegment]
  MOV ES, AX
  XOR DI, DI
  XOR AX, AX
  MOV CX, 32000
  REP STOSW

  ; 2. draw big 16x16 "GAME OVER" (9 chars * 16px = 144px wide, centered at X = 88, Y = 90)
  MOV DI, (90 * SCREEN_WIDTH) + 88
  MOV SI, gameOverText
  CALL drawString2x

  CALL screenSync
  CALL displayFrame

  RET

;requires si pointing to string to print
;di holds location where to print on screen
drawString:
.stringLoop:
  LODSB ; AL = next char, SI++
  CMP AL, 0
  JE .done  ; 0 at end of string
  CALL drawChar ; draws char and steps DI forward by 8 (each character is 8 width)
  JMP .stringLoop
.done:
  RET

;only called by draw string 
drawChar:
  PUSH DS
  PUSH SI
  PUSH DI

  ;to get offset we use formula  fontOffset + (ascii*8)  here 8 because 8 height charcters
  ;AL holds ascii
  XOR AH, AH
  SHL AX, 3 ; AX now holds ASCII * 8
  ADD AX, [fontOffset]
  MOV SI, AX
  MOV AX, [fontSegment]
  MOV DS, AX ; DS:SI points to start of the 8 byte character in memory

  MOV DX, 8 ;rows
.rowLoop:
  LODSB ; taskes value from ds:si into  AL (gets one full row 8 bits)
  MOV CX, 8 ;columns

.pixelLoop:
  SHL AL, 1 ; push leftmost bit into Carry Flag
  JNC .skipPixel
  MOV BYTE [ES:DI], 15 ; bit was 1 we draw white pixel (color 15)
.skipPixel:
  INC DI
  LOOP .pixelLoop

  ADD DI, (SCREEN_WIDTH - 8); advance DI to start of next scanline
  DEC DX
  JNZ .rowLoop

  POP DI
  ADD DI, 8 ; step 8 pixels right for next char
  POP SI
  POP DS
  RET


; draws a 2 digit number from AX at current DI
drawNumber:
  MOV BL, 10
;when using 8 bit division, asnwer goes to al and remainder in ah.
  DIV BL ; dividing by 12 gets us each digit seperated into AL and AH
  
  ADD AL, '0' ; convert tens to ASCII
  PUSH AX ; saves tens
  CALL drawChar
  POP AX
  
  MOV AL, AH
  ADD AL, '0' ; convert ones to ASCII
  CALL drawChar
  RET

drawString2x:
.loop:
  LODSB
  CMP AL, 0
  JE .done
  CALL drawChar2x
  JMP .loop
.done:
  RET

; draws a 16x16 character by scaling each 8x8 font bit into a 2x2 pixel block
; works similar to drawchar but draws a blcok of 4pixels
drawChar2x:
  PUSH DS
  PUSH SI
  PUSH DI

  XOR AH, AH
  SHL AX, 3
  ADD AX, [fontOffset]
  MOV SI, AX
  MOV AX, [fontSegment]
  MOV DS, AX ; DS:SI points to ROM font

  MOV DX, 8 ; 8 font rows (will become 16 screen scanlines)
.rowLoop:
  LODSB  ; AL = 1 font byte
  PUSH DI  ; remember start of this printing
  MOV CX, 8  ; 8 bits across

.bitLoop:
  SHL AL, 1
  JNC .skipPixel
  ; draw a 2x2 block of white pixels. using red and white color for a pattern
  MOV BYTE [ES:DI], 0CH
  MOV BYTE [ES:DI + 1], 15
  MOV BYTE [ES:DI + SCREEN_WIDTH], 0CH
  MOV BYTE [ES:DI + SCREEN_WIDTH + 1], 0CH
.skipPixel:
  ADD DI, 2 ; step 2 pixels across
  LOOP .bitLoop

  POP DI ; get back to start of prev print so we can jump 2 pixels down
  ADD DI, (SCREEN_WIDTH * 2); jump 2 pixels
  DEC DX
  JNZ .rowLoop

  POP DI
  ADD DI, 16; advance DI by 16 pixels for the next 2x letter
  POP SI
  POP DS
  RET

