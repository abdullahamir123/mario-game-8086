HUD:; drawing the top bar for score at end
  XOR DI, DI
  XOR AX, AX
  MOV CX, (SCREEN_WIDTH*HUD_HEIGHT)/2
  REP STOSW

  MOV DI, 8
  MOV SI, coinText
  CALL drawString
 
  MOV AX, [coinsCollected]
  CALL drawNumber
  ret

sky:
  MOV DI, (SCREEN_WIDTH * HUD_HEIGHT)
  MOV AL, 77
  MOV AH, 77
  MOV CX, ((SCREEN_HEIGHT-HUD_HEIGHT) * SCREEN_WIDTH)/2
  REP STOSW
  RET

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

drawMario:
  MOV AX, [marioWorldX]
  SUB AX, [cameraX]
  MOV [drawStartX], AX
  MOV AX, [marioWorldY]
  MOV [drawStartY], AX
  MOV SI, [currentMarioTable] 
  CMP BYTE [isOnGround], 1
  JE .drawMarioGround
  MOV BX, [SI + 6]
  JMP .done
.drawMarioGround:
  CMP WORD [marioVelX], 0
  JNE .drawMarioRun
  MOV BX, [SI + 4]
  JMP .done
.drawMarioRun:
  INC BYTE [marioRunTimer]
  CMP BYTE [marioRunTimer], 8
  JL .noSwap
  MOV BYTE [marioRunTimer], 0
  XOR BYTE [marioRunIndex], 1; makes index 1 to 0 (swaps between the two)
.noSwap:
  XOR BX, BX
  MOV BL, [marioRunIndex]
  SHL BX, 1; mario table is dw
  MOV BX, [SI + BX]
.done:
  CALL drawAsset
  ret

drawAsset:
  PUSH AX
  PUSH CX
  PUSH DX
  PUSH SI

  ;BX must be at asset to draw
  XOR AX, AX
  MOV AL, [BX]
  MOV BP, AX; asset width
  ADD BX, 2
  MOV AX, [drawStartY]
  MOV [assetCurrentY], AX
  MOV CX, SCREEN_WIDTH
  MUL CX
  ADD AX, [drawStartX]  
  MOV DI, AX; di gets y*screenwidth+x
  MOV AX, [drawStartX]
  MOV [assetCurrentX], AX

  XOR SI, SI;si holds how many pixels have been drawn in current col
.readPair:
  MOV AL, [BX];al has color 
  CMP AL, 249; custom key for end of asset
  JE .done
  XOR CX, CX
  MOV CL, [BX+1]; cl has color count
  ADD BX, 2
  ADD SI, CX
  CMP AL, 248;248 is our custom code for transparent color (draw nothing)
  JE .skipPixel

 .drawLoop:
  CMP WORD [assetCurrentX], 0;if asset is being clipped from left side, do not draw those pixels
  JL .skipDrawPixel 
  CMP WORD [assetCurrentX], SCREEN_WIDTH;if asset on right, we won't draw those pixels
  JGE .skipDrawPixel
  CMP WORD [assetCurrentY], HUD_HEIGHT
  JL .skipDrawPixel
  CMP WORD [assetCurrentY], SCREEN_HEIGHT
  JGE .skipDrawPixel
  MOV [ES:DI], AL
.skipDrawPixel:
  INC DI
  INC WORD [assetCurrentX]
  LOOP .drawLoop
  JMP .checkEndOfRow

.skipPixel:
  ADD DI, CX ; add count of transparent pixels into DI
  ADD [assetCurrentX], CX
.checkEndOfRow:
  CMP SI, BP
  JL .readPair
  ADD DI, SCREEN_WIDTH
  SUB DI, BP ; move DI to start of next row
  XOR SI, SI  ; reset row pixel counter
  MOV AX, [drawStartX]
  MOV [assetCurrentX], AX
  INC WORD [assetCurrentY]
  JMP .readPair

.done:
  POP SI
  POP DX
  POP CX
  POP AX 
  ret

drawMap:
;screenw idth is exactly 20 columns. but the issue is if we move forward,
;the first column gets slightly clipped and a new column appears on right. 
;so we assume there are 21 columns always to print. we only skip 21st if cameraX is on frist pixel of each tile
  MOV SI, [cameraX]
  MOV AX, SI
  SHR SI, 4 ;starting map column
  AND AX, 0x000F ; gives value between 0 to 15. tells us how many pixels are cutt off
  NEG AX

  MOV WORD [drawStartY], 8  ; map starts below 8px HUD
  MOV DX, 12 ; 12 rows on screen

.mapOuterLoop:
  MOV [drawStartX], AX ; reset screenX for this row
  MOV CX, 21

.mapLoop:
  CMP WORD [drawStartX], SCREEN_WIDTH
  JGE .skipMap  ; skip 21 column if it starts off-screen
  XOR BX, BX
  MOV BL, [worldMap + SI]
  SHL BX, 1 ; tiletable is dw
  MOV BX, [tileTable + BX]
  CMP BX, 0  ; skipping if sky
  JE .skipMap
  CALL drawAsset 

.skipMap:
  INC SI
  ADD WORD [drawStartX], 16
  LOOP .mapLoop

  ADD SI, MAPCOLUMNS-21 ;makes us skip worldmap parts not on screen
  ADD WORD [drawStartY], 16
  DEC DX
  JNZ .mapOuterLoop
  RET

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
  RET


updateCamera:
  MOV AX, [marioWorldX]
  SUB AX, SCREEN_WIDTH/2
  CMP AX, 0
  JL .reset
  CMP AX, (MAPCOLUMNS*16)-SCREEN_WIDTH
  JLE .done
  MOV AX, (MAPCOLUMNS*16 ) - SCREEN_WIDTH
  JMP .done
.reset:
  XOR AX, AX
.done:
  MOV WORD [cameraX], AX
  ret

displayFrame:
  PUSH DS
  MOV AX, [bufferSegment]
  MOV DS, AX
  MOV AX, 0xA000
  MOV ES, AX

  XOR SI, SI
  XOR DI, DI
  MOV CX, 32000 
  REP MOVSW

  POP DS
  RET

getTile:
  ;bx gets pixelx
  ;ax gets pixely
  SUB AX, HUD_HEIGHT
  CMP AX, 0;check out of screen bounds (top) 
  JL .returnAir
  SHR BX, 4; divide by 16 so we get map column number
  SHR AX, 4; divide by 16 gets map row number
  CMP AX, 12
  JGE .returnAir
  MOV CX, MAPCOLUMNS
  MUL CX
  ADD AX, BX; (mapRow*totalcolumns)+mapCol
  MOV SI, AX
  MOV AL, [worldMap+SI]
  JMP .validTile
.returnAir:
  XOR AL, AL
.validTile:
  ret

checkCoins:
;checks four corner pixels (from inside) of mario there is a coin.
  ; topleft
  MOV BX, [marioWorldX]
  ADD BX, 2
  MOV AX, [marioWorldY]
  ADD AX, 2
  CALL tryCollectCoin

  ;topright
  MOV BX, [marioWorldX]
  ADD BX, [marioWidth]
  SUB BX, 3
  MOV AX, [marioWorldY]
  ADD AX, 2
  CALL tryCollectCoin

  ;bottomleft
  MOV BX, [marioWorldX]
  ADD BX, 2
  MOV AX, [marioWorldY]
  ADD AX, [marioHeight]
  DEC AX
  CALL tryCollectCoin

  ;bottomright
  MOV BX, [marioWorldX]
  ADD BX, [marioWidth]
  SUB BX, 3
  MOV AX, [marioWorldY]
  ADD AX, [marioHeight]
  DEC AX
  CALL tryCollectCoin
  RET

tryCollectCoin:
  CALL getTile
  CMP AL, 5
  JNE .notCoin
  MOV BYTE [worldMap + SI], 0
  INC WORD [coinsCollected]
.notCoin:
  RET
