drawChar:
  PUSH DS
  PUSH SI
  PUSH DI

  ; compute ROM font address: fontOffset + (ASCII * 8)
  XOR AH, AH
  SHL AX, 3                 ; AX = ASCII * 8
  ADD AX, [fontOffset]
  MOV SI, AX
  MOV AX, [fontSegment]
  MOV DS, AX                ; DS:SI points to 8-byte font glyph in ROM

  MOV DX, 8                 ; 8 rows tall
.rowLoop:
  LODSB                     ; AL = 1 row byte from ROM, SI++
  MOV CX, 8                 ; 8 pixels wide

.pixelLoop:
  SHL AL, 1                 ; push leftmost bit into Carry Flag
  JNC .skipPixel
  MOV BYTE [ES:DI], 15      ; bit was 1: draw crisp white pixel (color 15)
.skipPixel:
  INC DI
  LOOP .pixelLoop

  ADD DI, (SCREEN_WIDTH - 8); advance DI to start of next scanline
  DEC DX
  JNZ .rowLoop

  POP DI
  ADD DI, 8                 ; step 8 pixels right for next char
  POP SI
  POP DS
  RET

drawString:
.loop:
  LODSB                     ; AL = next char, SI++
  CMP AL, 0
  JE .done                  ; hit null terminator (0)
  CALL drawChar             ; draws char and steps DI forward by 8
  JMP .loop
.done:
  RET

; draws a 2-digit number (00..99) from AX at current DI
drawNumber:
  PUSH AX
  PUSH BX
  MOV BL, 10
  DIV BL                    ; AL = tens digit (quotient), AH = units digit (remainder)
  
  ADD AL, '0'               ; convert tens to ASCII
  PUSH AX                   ; save remainder (AH)
  CALL drawChar
  POP AX
  
  MOV AL, AH
  ADD AL, '0'               ; convert units to ASCII
  CALL drawChar
  
  POP BX
  POP AX
  RET

; draws a 16x16 character by scaling each 8x8 font bit into a 2x2 pixel block
drawChar2x:
  PUSH DS
  PUSH SI
  PUSH DI

  XOR AH, AH
  SHL AX, 3
  ADD AX, [fontOffset]
  MOV SI, AX
  MOV AX, [fontSegment]
  MOV DS, AX                ; DS:SI points to ROM font

  MOV DX, 8                 ; 8 font rows (will become 16 screen scanlines)
.rowLoop:
  LODSB                     ; AL = 1 font byte
  PUSH DI                   ; remember start of this scanline pair
  MOV CX, 8                 ; 8 bits across

.bitLoop:
  SHL AL, 1
  JNC .skipPixel
  ; draw a 2x2 block of white pixels (color 15)
  MOV BYTE [ES:DI], 15
  MOV BYTE [ES:DI + 1], 15
  MOV BYTE [ES:DI + SCREEN_WIDTH], 15
  MOV BYTE [ES:DI + SCREEN_WIDTH + 1], 15
.skipPixel:
  ADD DI, 2                 ; step 2 pixels across
  LOOP .bitLoop

  POP DI                    ; restore start of current scanline pair
  ADD DI, (SCREEN_WIDTH * 2); jump down 2 full scanlines
  DEC DX
  JNZ .rowLoop

  POP DI
  ADD DI, 16                ; advance DI by 16 pixels for the next 2x letter
  POP SI
  POP DS
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


startScreen:
  ; 1. clear backbuffer to black
  MOV AX, [bufferSegment]
  MOV ES, AX
  XOR DI, DI
  XOR AX, AX
  MOV CX, 32000
  REP STOSW

  ; 2. draw big 16x16 title: "SUPER MARIO" (11 chars * 16px = 176px wide, centered at X=72, Y=70)
  MOV DI, (70 * SCREEN_WIDTH) + 72
  MOV SI, titleText
  CALL drawString2x

  ; 3. draw 8x8 subtitle: "PRESS ENTER TO START" (20 chars * 8px = 160px wide, centered at X=80, Y=120)
  MOV DI, (120 * SCREEN_WIDTH) + 80
  MOV SI, startText
  CALL drawString

  ; 4. blit to monitor
  CALL screenSync
  CALL displayFrame

  ; 5. wait loop for ENTER (scancode 0x1C) or ESC (0x01)
.waitLoop:
  CMP BYTE [keyDown + 0x01], 1
  JE terminate
  CMP BYTE [keyDown + 0x1C], 1
  JNE .waitLoop

  ; debounce: clear Enter key so game doesn't receive it
  MOV BYTE [keyDown + 0x1C], 0
  RET

; freezes game in place, draws "PAUSED" over the frame, and waits for 'P' again
pauseMenu:
  ; 1. wait until 'P' is released so it doesn't instantly unpause
.waitRelease1:
  CMP BYTE [keyDown + 0x19], 0
  JNE .waitRelease1

  ; 2. draw big 16x16 "PAUSED" in the center over the frozen game frame
  ; 6 chars * 16px = 96px wide, centered at X = 112, Y = 90
  MOV DI, (90 * SCREEN_WIDTH) + 112
  MOV SI, pausedText
  CALL drawString2x

  ; 3. blit paused screen to monitor
  CALL screenSync
  CALL displayFrame

  ; 4. wait loop until 'P' is pressed again (or ESC to quit)
.waitPress:
  CMP BYTE [keyDown + 0x01], 1
  JE terminate
  CMP BYTE [keyDown + 0x19], 1
  JNE .waitPress

  ; 5. wait until 'P' is released before returning to the game
.waitRelease2:
  CMP BYTE [keyDown + 0x19], 0
  JNE .waitRelease2
  RET


; black screen with "GAME OVER", holds for ~1.5 seconds, then resets the level
deathScreen:
  ; 1. clear buffer to black
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

  ; 3. blit to monitor
  CALL screenSync
  CALL displayFrame

  ; 4. hold for ~100 frames (~1.4 seconds at 70 Hz) with NO input required
  MOV CX, 100
.timerLoop:
  PUSH CX
  CALL screenSync
  POP CX
  LOOP .timerLoop

  ; 5. now safely reset the level!
  CALL resetLevel
  RET
