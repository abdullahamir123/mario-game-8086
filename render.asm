drawMario:
  TEST BYTE [invulnerabilityTimer], 4 ; no draw every 4 frames while bigger than 0
  JZ .draw
  RET
.draw:
  MOV AX, [marioWorldX]
  SUB AX, [cameraX]
  MOV [drawStartX], AX
  MOV AX, [marioWorldY]
  MOV [drawStartY], AX
  MOV SI, [currentMarioTable] 
  MOV BX, [superMario]
  CMP BYTE [isOnGround], 1
  JE .drawMarioGround
  MOV BX, [SI + BX +6]
  JMP .done
.drawMarioGround:
  CMP WORD [marioVelX], 0
  JNE .drawMarioRun
  MOV BX, [SI + BX + 4]
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
  SHL BX, 1 
  ADD BX, [superMario] ; 0 for normal, 8 for super mario
  MOV BX, [SI + BX]
.done:
  CALL drawAsset
  ret

drawAsset:
  PUSH BX
  PUSH DI
  PUSH BP
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
  CMP AX, 0
  JL .needsClip
  ADD AX, BP
  CMP AX, SCREEN_WIDTH
  JG .needsClip
  XOR DX, DX
  MOV DL, [BX-1] ;height
  MOV AX, [drawStartY]
  CMP AX, HUD_HEIGHT
  JL .needsClip
  ADD AX, DX
  CMP AX, SCREEN_HEIGHT
  JG .needsClip

  XOR SI, SI
.fastReadPair:
  MOV AL, [BX] ;color
  CMP AL, 249
  JNE .notDone
  JMP .done
.notDone
  XOR CX, CX
  MOV CL, [BX+1];count
  ADD BX, 2;go to next pair
  ADD SI, CX
  CMP AL, 248
  JE .fastSkip
  REP STOSB   ; draws CX pixels of color AL and adds CX to DI
  JMP .fastCheckRow
.fastSkip:
  ADD DI, CX
.fastCheckRow:
  CMP SI, BP
  JL .fastReadPair
  ADD DI, SCREEN_WIDTH
  SUB DI, BP
  XOR SI, SI
  JMP .fastReadPair
.needsClip:
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
  POP BP
  POP DI
  POP BX
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
;
;think about drawing on 886 vga screen as a cathode ray shooting beams one by one. 
;once done it needs to go back called a vertical retrace
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
  MOV AX, (MAPCOLUMNS*16)-SCREEN_WIDTH
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

checkItem:
;checks four corner pixels (from inside) of mario there is a coin or mushroom
  ; topleft
  MOV BX, [marioWorldX]
  ADD BX, 2
  MOV AX, [marioWorldY]
  ADD AX, 2
  CALL tryCollect

  ;topright
  MOV BX, [marioWorldX]
  ADD BX, [marioWidth]
  SUB BX, 3
  MOV AX, [marioWorldY]
  ADD AX, 2
  CALL tryCollect

  ;bottomleft
  MOV BX, [marioWorldX]
  ADD BX, 2
  MOV AX, [marioWorldY]
  ADD AX, [marioHeight]
  DEC AX
  CALL tryCollect

  ;bottomright
  MOV BX, [marioWorldX]
  ADD BX, [marioWidth]
  SUB BX, 3
  MOV AX, [marioWorldY]
  ADD AX, [marioHeight]
  DEC AX
  CALL tryCollect
  RET

tryCollect:
  CALL getTile
  TEST AL, AL
  JZ .notItem
  CMP AL, 5
  JNE .checkMushroom
  MOV BYTE [worldMap + SI], 0
  INC WORD [coinsCollected]
  ADD WORD [score], 50
  RET
.checkMushroom:
  CMP AL, 17
  JNE .notItem
  MOV BYTE [worldMap + SI], 0
  MOV BYTE [superMario], 8
  ADD WORD [score], 100   
.notItem:
  RET

checkFlag:
  MOV AX, [marioWorldX]
  ADD AX, [marioWidth]
  CMP AX, 151*16 ;flag is on 151th column
  JL .done
  MOV BX, [marioWorldY]
  MOV AX, SCREEN_HEIGHT
  SUB AX, BX
  MOV BX, 10
  MUL BX
  ADD [score], AX 
  MOV WORD [currentMarioTable], marioTable ;change mario animation to rightwards just incase
  CALL drawAnimation
  MOV CX, 70
  CALL screenPause
  CALL gameEndAnimation
.done:
  ret

gameEndAnimation:
  ADD WORD [marioWorldY], 2
  CALL drawAnimation
  CMP WORD [marioWorldY], 152 ;ground at 152
  JL gameEndAnimation
  MOV BYTE [isOnGround], 1
  MOV WORD [marioVelX], 8
.moveToCastle:
  ADD WORD [marioWorldX], 2
  CALL drawAnimation
  CMP WORD [marioWorldX], (156*16)+8
  JL .moveToCastle
  CALL winScreen
  ret

drawAnimation:
  MOV AX, [bufferSegment]
  MOV ES, AX
  CALL updateCamera
  CALL HUD
  CALL sky
  CALL drawMap
  CALL drawMario
  CALL screenSync
  CALL displayFrame
  ret

screenPause:
  CALL screenSync
  LOOP screenPause
