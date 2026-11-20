%define SCREEN_WIDTH  320
%define SCREEN_HEIGHT 200

%define MAPCOLUMNS 60
%define SCREENCOLUMNS 20

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

  CALL HUD
  CALL sky
  CALL drawMap
  CALL input
  CALL gravity
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
  TEST AL, 0x80 ;(1000 0000). checking if 7th bit on(if pressed or not)
  JZ .pressed
  AND AL, 0X7F; (0111 1111 clearing last bit)
  XOR CX, CX
.pressed:
  MOV BX, AX
  MOV BYTE [CS:keyDown+ BX], CL; if not pressed cl will be 0. if pressed cl is 1
.done:
  MOV AL, 0x20 ; moving 0x20 into al and then feeding to PIC tells it interrupt has finished. and code can continue now
  OUT 0x20, AL;port 20 is interrupt controller
  POP CX
  POP BX
  POP AX
  IRET; need to used iret instead of ret for interrupts


input:
  ;port 0x60 scancodes:
  ;ESC: 0x01
  ;A: 0x1E
  ;Left Arrow: 0x4B
  ;D: 0x20
  ;Right Arrow: 0x4D
  ;W: 0x11
  ;Spacebar: 0x39
  ;Up Arrow: 0x48
  ; check if player is pressing left (a or left arrow)
  CMP BYTE [keyDown + 0x1E], 1
  JE .accelLeft
  CMP BYTE [keyDown + 0x4B], 1
  JE .accelLeft

  ; check if player is pressing right (d or right arrow)
  CMP BYTE [keyDown + 0x20], 1
  JE .accelRight
  CMP BYTE [keyDown + 0x4D], 1
  JE .accelRight

  ; neither left nor right is held, so apply friction to slow mario down smoothly
  CMP WORD [marioVelX], 0
  JE .applyHorizontalMove
  JG .frictionRight
  INC WORD [marioVelX] ; sliding left so push velocity back toward 0
  JMP .applyHorizontalMove
.frictionRight:
  DEC WORD [marioVelX] ; sliding right so pull velocity back toward 0
  JMP .applyHorizontalMove

.accelLeft:
  ; check if left shift (0x2A) is held to run faster
  MOV CX, 16   ; normal max walk speed (2 px/frame = 16 eighths)
  CMP BYTE [keyDown + 0x2A], 1
  JNE .applyAccelLeft
  MOV CX, 24 ; max run speed when holding shift (3 px/frame = 24 eighths)
.applyAccelLeft:
  NEG CX  ; make speed limit negative for moving left
  DEC WORD [marioVelX]
  CMP WORD [marioVelX], CX
  JGE .applyHorizontalMove
  MOV [marioVelX], CX
  JMP .applyHorizontalMove

.accelRight:
  ; check if left shift (0x2A) is held to run faster
  MOV CX, 16  ; normal max walk speed (2 px/frame)
  CMP BYTE [keyDown + 0x2A], 1
  JNE .applyAccelRight
  MOV CX, 24  ; max run speed when holding shift (3 px/frame)
.applyAccelRight:
  INC WORD [marioVelX]
  CMP WORD [marioVelX], CX
  JLE .applyHorizontalMove
  MOV [marioVelX], CX

.applyHorizontalMove:
  ; convert eighth-pixel velocity into whole pixels to move this frame
  MOV AX, [marioSubX]
  ADD AX, [marioVelX]  ; add current velocity to leftover sub-pixels
  MOV BX, AX  ; save a copy before dividing by 8
  SAR AX, 3   ; signed divide by 8 to get whole pixels (dx)
  AND BX, 7 ; keep remainder (0..7) in sub-pixel accumulator
  MOV [marioSubX], BX

  CMP AX, 0
  JE NEAR .noHorizontalMove   ; 0 whole pixels to move this frame
  JL NEAR .tryMoveLeft        ; negative means moving left
  JMP .tryMoveRight           ; positive means moving right

.tryMoveLeft:
  ; ax is negative (e.g. -1 or -2), turn it into positive step count in cx
  NEG AX
  MOV CX, AX
.leftStepLoop:
  PUSH CX
  ; stop at left edge of world map
  CMP WORD [marioWorldX], 1
  JL .hitLeftWall

  ; check top-left corner 1 pixel ahead
  MOV BX, [marioWorldX]
  DEC BX
  ADD BX, 2                   ; 2 px sprite border inset
  MOV AX, [marioWorldY]
  ADD AX, 2
  CMP AX, 8
  JGE .topLeftStepOk
  MOV AX, 8
.topLeftStepOk:
  CALL getTile
  CMP AL, 0
  JE .checkBottomLeftStep
  CMP AL, 5
  JE .checkBottomLeftStep
  JMP .hitLeftWall

.checkBottomLeftStep:
  ; check bottom-left corner 1 pixel ahead
  MOV BX, [marioWorldX]
  DEC BX
  ADD BX, 2
  MOV AX, [marioWorldY]
  ADD AX, [marioHeight]
  DEC AX
  CMP AX, 8
  JGE .bottomLeftStepOk
  MOV AX, 8
.bottomLeftStepOk:
  CALL getTile
  CMP AL, 0
  JE .stepLeftOne
  CMP AL, 5
  JE .stepLeftOne
  JMP .hitLeftWall

.stepLeftOne:
  DEC WORD [marioWorldX]   ; safe to step 1 pixel left
  POP CX
  DEC CX
  JNZ NEAR .leftStepLoop
  JMP .noHorizontalMove

.hitLeftWall:
  POP CX
  MOV WORD [marioVelX], 0 ; stop horizontal momentum when hitting a wall
  MOV WORD [marioSubX], 0
  JMP .noHorizontalMove

.tryMoveRight:
  ; ax is positive step count (e.g. 1 or 2)
  MOV CX, AX
.rightStepLoop:
  PUSH CX
  ; stop at right edge of 60-tile level (60 * 16 = 960)
  MOV AX, [marioWorldX]
  ADD AX, [marioWidth]
  CMP AX, (MAPCOLUMNS * 16)
  JGE .hitRightWall

  ; check top-right corner 1 pixel ahead
  MOV BX, [marioWorldX]
  INC BX
  ADD BX, [marioWidth]
  SUB BX, 3 ; right sprite border inset
  MOV AX, [marioWorldY]
  ADD AX, 2
  CMP AX, 8
  JGE .topRightStepOk
  MOV AX, 8
.topRightStepOk:
  CALL getTile
  CMP AL, 0
  JE .checkBottomRightStep
  CMP AL, 5
  JE .checkBottomRightStep
  JMP .hitRightWall

.checkBottomRightStep:
  ; check bottom-right corner 1 pixel ahead
  MOV BX, [marioWorldX]
  INC BX
  ADD BX, [marioWidth]
  SUB BX, 3
  MOV AX, [marioWorldY]
  ADD AX, [marioHeight]
  DEC AX
  CMP AX, 8
  JGE .bottomRightStepOk
  MOV AX, 8
.bottomRightStepOk:
  CALL getTile
  CMP AL, 0
  JE .stepRightOne
  CMP AL, 5
  JE .stepRightOne
  JMP .hitRightWall

.stepRightOne:
  INC WORD [marioWorldX]  ; safe to step 1 pixel right
  POP CX
  DEC CX
  JNZ NEAR .rightStepLoop
  JMP .noHorizontalMove

.hitRightWall:
  POP CX
  MOV WORD [marioVelX], 0  ; stop horizontal momentum when hitting a wall
  MOV WORD [marioSubX], 0

.noHorizontalMove:

.noRight:
  CMP BYTE [keyDown + 0x11], 1
  JE .jump
  CMP BYTE [keyDown + 0x39], 1
  JE .jump
  CMP BYTE [keyDown + 0x48], 1
  JE .jump
  MOV BYTE [jumpWasDown], 0; makes it so that if jump already pressed and not released since last jump dont jump again.
  JMP .noJump
.jump:
  
  CMP BYTE [isOnGround], 1
  JNE .noJump
  MOV WORD [marioVelY], -44
  MOV BYTE [isOnGround], 0
.noJump:
  ; variable jump height: if mario is moving up and jump key is released, cut upward speed
  CMP WORD [marioVelY], -12
  JGE .checkEsc  ; only cut off if rising faster than -12
  CMP BYTE [keyDown + 0x11], 1
  JE .checkEsc
  CMP BYTE [keyDown + 0x39], 1
  JE .checkEsc
  CMP BYTE [keyDown + 0x48], 1
  JE .checkEsc
  MOV WORD [marioVelY], -12    ; player released jump early so do a small hop

.checkEsc:
  CMP BYTE [keyDown + 0x01], 1
  JNE .done
  JMP terminate
  .done:
  RET


gravity:
  ;convert eighthpixel vertical velocity into whole pixels to move
  MOV AX, [marioSubY]
  ADD AX, [marioVelY] ; add current velocity to leftover sub-pixels
  MOV BX, AX; save a copy before dividing by 8
  SAR AX, 3  ; signed divide by 8 to get whole pixels (dy)
  AND BX, 7  ; keep remainder (0..7) in sub-pixel accumulator
  MOV [marioSubY], BX
  ADD WORD [marioWorldY], AX  ; move mario up or down by whole pixels

  ; apply gravity (pull downward by 2 eighths/frame, max fall speed = 48 eighths = 6 px/frame)
  ADD WORD [marioVelY], 2
  CMP WORD [marioVelY], 48
  JLE .validVelocity
  MOV WORD [marioVelY], 48

.validVelocity:
  ;check whether mario is moving up or falling/standing
  CMP WORD [marioVelY], 0
  JL .checkHead; mario is moving up so check if his head hits a block
  JMP .checkLeftFoot ; mario is falling or still so check his feet

.checkHead:
  ; make sure mario doesnt jump above the top hud bar (y < 8)
  CMP WORD [marioWorldY], 8
  JGE .headNotAtCeiling
  MOV WORD [marioWorldY], 8
  MOV WORD [marioVelY], 0
  JMP .inAir

.headNotAtCeiling:
  ; check top left corner of marios head (using 2 px inset so side walls dont snag)
  MOV BX, [marioWorldX]
  ADD BX, 2
  MOV AX, [marioWorldY]
  CALL getTile ; gives tile number in al
  CMP AL, 0 ; 0 is sky so keep going up
  JE .checkRightHead
  CMP AL, 5; 5 is coin so keep going up
  JE .checkRightHead
  JMP .hitHead ; solid block above left side of head

.checkRightHead:
  ; check top right corner of marios head
  MOV BX, [marioWorldX]
  ADD BX, [marioWidth]
  SUB BX, 3
  MOV AX, [marioWorldY]
  CALL getTile
  CMP AL, 0   ; sky is clear
  JE .clearTile
  CMP AL, 5 ; coin is clear
  JE .clearTile
  JMP .blocked

.clearTile:
  JMP .inAir;had to add because of short jumps gettign out of range
.blocked:

.hitHead:
  ; mario bonked his head on a solid block above him
  ; push his head down to the bottom edge of the block so he doesnt clip inside
  MOV AX, [marioWorldY]
  SUB AX, 8  ; remove top hud offset
  AND AX, 0xFFF0 ; round down to the top edge of the tile he hit
  ADD AX, 8 ; put hud offset back
  ADD AX, 16 ; move down 16 pixels to the bottom edge of that tile
  MOV [marioWorldY], AX

  MOV WORD [marioVelY], 0   ; stop upward speed so gravity pulls him down
  MOV WORD [marioSubY], 0
  JMP .inAir

.checkLeftFoot:
  ;first check left foot of mario
  MOV AX, [marioWorldY]
  MOV BX, [marioWorldX]
  ADD BX, 2 ; 2 px sprite border inset to match walls/head
  ADD AX, [marioHeight]
  CALL getTile; gives back a tile in AL (marios left most bottom pixel)
  CMP AL, 0; if sky we fall
  JZ .checkRightFoot
  CMP AL, 5; check if coin
  JE .checkRightFoot
  JMP .onGround
.checkRightFoot:
  ;now check right foot
  MOV AX, [marioWorldY]
  MOV BX, [marioWorldX]
  ADD AX, [marioHeight]
  ADD BX, [marioWidth]
  SUB BX, 3 ; -1 for right edge, -2 for border inset
  CALL getTile; gives back a tile in AL (marios right most bottom pixel)
  CMP AL, 0; if sky we fall
  JZ .inAir
  CMP AL, 5; check if coin
  JE .inAir

.onGround:
  ;because of velocity, we're actually falling more than a single pixel. may fall into ground before next check.
  ;if happens pop up to surface
  MOV AX, [marioWorldY]
  ADD AX, [marioHeight]; AX will have feetY
  SUB AX, 8 ; remove HUD offset
  AND AX, 0xFFF0 ; round down to the tile top edge (multiple of 16)
  ADD AX, 8 ; restore HUD offset
  SUB AX, [marioHeight] ; convert back to mario toplefty
  MOV [marioWorldY], AX

  MOV WORD [marioVelY], 0
  MOV WORD [marioSubY], 0
  MOV BYTE [isOnGround], 1
  RET
.inAir:
  MOV BYTE [isOnGround], 0
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

getTile:
  ;bx gets pixelx
  ;ax gets pixely
  SUB AX, 8;remove top HUD
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
.validTile
  ret

HUD:; drawing the top bar for score at end
  XOR DI, DI
  MOV AL, 0
  MOV CX, (SCREEN_WIDTH*8)
  REP STOSB
  ret

sky:
  MOV DI, (SCREEN_WIDTH * 8)
  MOV AL, 77
  MOV CX, ((SCREEN_HEIGHT-8) * SCREEN_WIDTH)
  REP STOSB
  RET

drawMario:
  MOV BX, mario_idle
  MOV AX, [marioWorldY]
  MOV CX, SCREEN_WIDTH
  MUL CX
  ADD AX, [marioWorldX]
  MOV DI, AX; basically, (marioY*SCREENWIDTH)+marioX (location of mario)
  CALL drawAsset
  ret

drawAsset:
  ;BX must be at asset to draw
  ;DI must be where on screen to draw
  XOR AX, AX
  MOV AL, [BX]
  MOV WORD [assetWidth], AX
  MOV AL, [BX+1]
  MOV WORD [assetHeight], AX

  ADD BX, 2
  MOV SI, 0;si holds how many pixels have been drawn in current col

.readPair:
  MOV AL, [BX];al has color
  XOR CX, CX
  MOV CL, [BX+1]; cl has color count

.pixelLoop:
  CMP AL, 248;248 is our custom code for transparent color (draw nothing)
  JE .skipPixel
  MOV BYTE [ES:DI], AL
.skipPixel:
  INC DI
  INC SI

  CMP SI, [assetWidth]
  JNE .notEndOfRow

  MOV SI, 0
  ADD DI, SCREEN_WIDTH
  SUB DI, [assetWidth]; we go from right of one row of asset to bottom left(start) of next column
  DEC WORD [assetHeight]
  JZ .done

.notEndOfRow:
  LOOP .pixelLoop
  ADD BX, 2;move to next pair
  JMP .readPair

.done:
  ret


drawMap:
  MOV DI, (8*SCREEN_WIDTH);for dem pixels
  XOR SI, SI;for iterating the map
  MOV DX, 12; number of rows in screen
.mapOuterLoop:
  MOV CX, 20; columns in screen. each is 16 byte asset
.mapLoop:
  XOR BX, BX
  MOV BL, [worldMap+SI]; holds map current asset code.
  ADD BL, BL ;tileTable is dw not db
  MOV BX, [tileTable+BX]
  CMP BX, 0;0 in tileTable means sky(skip)
  JE .skipMap
  ;save all imp registers and draw the current asset
  PUSH SI
  PUSH DI
  PUSH CX
  PUSH BX
  call drawAsset
  POP BX
  POP CX
  POP DI
  POP SI
.skipMap:
  INC SI;
  ADD DI, 16; jump 16 columns in screen(each asset is 16 columns)
  LOOP .mapLoop
  ADD SI, (MAPCOLUMNS-SCREENCOLUMNS); move SI to next row first value of map
  ADD DI, (15*SCREEN_WIDTH); looped through a screen row already so need to skip next 15 not 16.
  DEC DX
  JNZ .mapOuterLoop
  ret

displayFrame:
  PUSH DS
  MOV AX, [bufferSegment]
  MOV DS, AX
  MOV AX, 0xA000
  MOV ES, AX

  XOR SI, SI
  XOR DI, DI
  MOV CX, 32000  ; 32,000 words = 64,000 bytes
  REP MOVSW

  POP DS
  RET

terminate:
  ;return to standard text mode
  MOV AX, 0003H
  INT 10H

  ;free the framebuffer memory
  MOV ES, [bufferSegment]
  MOV AH, 49H
  INT 21H

  MOV DX, [oldInterrupt9Offset]
  MOV AX, [oldInterrupt9Segment]
  MOV DS, AX
  MOV AX, 0x2509
  INT 0x21

  MOV AX, 4C00H
  INT 21H

marioWorldX: dw 20
marioWorldY: dw 120
marioHeight: dw 16
marioWidth: dw 16

assetWidth: dw 0
assetHeight: dw 0

cameraX: dw 0
marioVelX: dw 0 ; horizontal velocity in eighth-pixels (8 = 1 px/frame)
marioSubX: dw 0 ; leftover sub-pixel accumulator for smooth movement
marioVelY: dw 0 ; mario velocity
marioSubY: dw 0
isOnGround: db 1

keyDown: times 128 db 0
oldInterrupt9Segment: dw 0
oldInterrupt9Offset: dw 0
jumpWasDown: db 0; to make sure player has to leave jump button and press again for two consecutive jumps

;memory format:
;first index width
;second index height
;after that every index is a pair (color, count of color)

brick:
  db 16, 16, 0, 16, 112, 6, 0, 1, 112, 15, 0, 1, 112, 15, 0, 1
  db 112, 15, 0, 1, 112, 15, 0, 1, 112, 15, 0, 1, 112, 9, 0, 16
  db 112, 3, 0, 1, 112, 7, 0, 1, 112, 7, 0, 1, 112, 7, 0, 1
  db 112, 7, 0, 1, 112, 7, 0, 1, 112, 7, 0, 1, 112, 7, 0, 1
  db 112, 7, 0, 1, 112, 7, 0, 1, 112, 7, 0, 1, 112, 7, 0, 1
  db 112, 7, 0, 1, 112, 7, 0, 1, 112, 4, 0, 16

cloud:
  db 32, 16, 248, 11, 22, 8, 248, 7, 22, 1, 248, 15, 22, 1, 29, 1
  db 22, 10, 248, 1, 22, 1, 248, 10, 22, 2, 248, 5, 22, 1, 29, 1
  db 22, 11, 248, 11, 22, 1, 29, 2, 22, 1, 248, 3, 22, 1, 29, 1
  db 22, 17, 248, 5, 22, 1, 29, 2, 22, 5, 29, 1, 22, 21, 248, 2
  db 22, 1, 29, 1, 22, 5, 29, 1, 22, 22, 248, 2, 22, 1, 29, 1
  db 22, 31, 29, 1, 22, 31, 29, 1, 22, 32, 29, 1, 22, 29, 248, 1
  db 22, 2, 29, 1, 22, 28, 248, 2, 22, 2, 29, 1, 22, 27, 248, 3
  db 22, 1, 29, 1, 22, 5, 29, 2, 22, 7, 29, 3, 22, 9, 248, 4
  db 22, 1, 29, 2, 22, 5, 29, 2, 22, 9, 29, 1, 22, 3, 29, 2
  db 22, 3, 248, 5, 22, 2, 29, 1, 22, 2, 248, 2, 22, 1, 29, 7
  db 22, 1, 248, 1, 22, 2, 29, 2, 22, 4, 248, 8, 22, 3, 248, 4
  db 22, 7, 248, 3, 22, 4, 248, 6

coin:
  db 16, 16, 248, 69, 43, 6, 248, 9, 43, 8, 248, 7, 43, 3, 42, 4
  db 43, 3, 248, 5, 43, 3, 42, 1, 43, 3, 20, 1, 18, 1, 43, 3
  db 248, 4, 43, 3, 42, 1, 43, 3, 20, 1, 18, 1, 43, 3, 248, 4
  db 43, 3, 42, 1, 43, 3, 20, 1, 18, 1, 43, 3, 248, 4, 43, 3
  db 42, 1, 43, 3, 20, 1, 18, 1, 43, 3, 248, 4, 43, 3, 42, 1
  db 43, 3, 20, 1, 18, 1, 43, 3, 248, 5, 43, 3, 18, 4, 43, 3
  db 248, 7, 43, 8, 248, 9, 43, 6, 248, 21

dirt:
  db 16, 16, 112, 2, 114, 5, 112, 3, 114, 5, 112, 1, 114, 1, 112, 2
  db 114, 3, 112, 2, 114, 1, 112, 2, 114, 3, 112, 2, 114, 2, 112, 2
  db 114, 1, 112, 2, 114, 3, 112, 2, 114, 1, 112, 2, 114, 4, 112, 3
  db 114, 5, 112, 3, 114, 2, 112, 2, 114, 5, 112, 3, 114, 5, 112, 1
  db 114, 1, 112, 2, 114, 3, 112, 2, 114, 1, 112, 2, 114, 3, 112, 2
  db 114, 2, 112, 2, 114, 1, 112, 2, 114, 3, 112, 2, 114, 1, 112, 2
  db 114, 4, 112, 3, 114, 5, 112, 3, 114, 2, 112, 2, 114, 5, 112, 3
  db 114, 5, 112, 1, 114, 1, 112, 2, 114, 3, 112, 2, 114, 1, 112, 2
  db 114, 3, 112, 2, 114, 2, 112, 2, 114, 1, 112, 2, 114, 3, 112, 2
  db 114, 1, 112, 2, 114, 4, 112, 3, 114, 5, 112, 3, 114, 2, 112, 2
  db 114, 5, 112, 3, 114, 5, 112, 1, 114, 1, 112, 2, 114, 3, 112, 2
  db 114, 1, 112, 2, 114, 3, 112, 2, 114, 2, 112, 2, 114, 1, 112, 2
  db 114, 3, 112, 2, 114, 1, 112, 2, 114, 4, 112, 3, 114, 5, 112, 3
  db 114, 2

dirtGrass:
  db 16, 16, 120, 18, 114, 1, 120, 10, 114, 1, 120, 2, 114, 1, 120, 1
  db 112, 1, 120, 1, 114, 1, 112, 1, 120, 3, 114, 1, 120, 1, 112, 1
  db 114, 1, 112, 1, 120, 1, 114, 4, 120, 2, 112, 1, 114, 4, 120, 2
  db 112, 1, 120, 2, 114, 1, 112, 2, 114, 2, 120, 1, 114, 2, 112, 3
  db 114, 3, 120, 1, 114, 1, 112, 1, 114, 1, 112, 2, 114, 3, 112, 2
  db 114, 1, 112, 2, 114, 3, 112, 2, 114, 2, 22, 1, 112, 1, 114, 1
  db 112, 2, 114, 3, 112, 1, 22, 1, 114, 1, 112, 2, 114, 4, 112, 3
  db 114, 1, 22, 1, 114, 3, 112, 3, 114, 2, 112, 2, 114, 5, 112, 3
  db 114, 5, 112, 1, 114, 1, 112, 2, 114, 3, 112, 2, 114, 1, 112, 2
  db 114, 3, 112, 2, 114, 2, 112, 2, 114, 1, 112, 2, 114, 3, 112, 2
  db 114, 1, 112, 2, 114, 4, 112, 3, 114, 4, 22, 1, 112, 3, 114, 2
  db 112, 2, 114, 5, 112, 3, 114, 3, 22, 1, 114, 1, 112, 1, 114, 1
  db 112, 2, 114, 3, 112, 2, 114, 1, 112, 2, 114, 3, 112, 2, 114, 2
  db 112, 2, 22, 1, 112, 2, 114, 3, 112, 2, 114, 1, 112, 2, 114, 4
  db 112, 3, 114, 5, 112, 3, 114, 2

stair:
  db 16, 16, 138, 15, 208, 1, 138, 1, 114, 14, 208, 1, 138, 1, 114, 14
  db 208, 1, 138, 1, 114, 14, 208, 1, 138, 1, 114, 14, 208, 1, 138, 1
  db 114, 14, 208, 1, 138, 1, 114, 14, 208, 1, 138, 1, 114, 14, 208, 1
  db 138, 1, 114, 14, 208, 1, 138, 1, 114, 14, 208, 1, 138, 1, 114, 14
  db 208, 1, 138, 1, 114, 14, 208, 1, 138, 1, 114, 14, 208, 1, 138, 1
  db 114, 14, 208, 1, 138, 1, 114, 14, 208, 17

questionBlock:
  db 16, 16, 42, 17, 43, 14, 42, 2, 43, 1, 42, 1, 43, 3, 15, 4
  db 43, 3, 42, 1, 43, 1, 42, 2, 43, 4, 15, 2, 43, 2, 15, 2
  db 43, 4, 42, 2, 43, 3, 15, 2, 43, 4, 15, 2, 43, 3, 42, 2
  db 43, 10, 15, 1, 43, 3, 42, 2, 43, 9, 15, 2, 43, 3, 42, 2
  db 43, 8, 15, 2, 43, 4, 42, 2, 43, 7, 15, 2, 43, 5, 42, 2
  db 43, 6, 15, 2, 43, 6, 42, 2, 43, 14, 42, 2, 43, 6, 15, 2
  db 43, 6, 42, 2, 43, 6, 15, 2, 43, 6, 42, 2, 43, 1, 42, 1
  db 43, 10, 42, 1, 43, 1, 42, 2, 43, 14, 42, 17

usedQuestion:
  db 16, 16, 42, 17, 138, 14, 42, 2, 138, 1, 42, 1, 138, 10, 42, 1
  db 138, 1, 42, 2, 138, 14, 42, 2, 138, 14, 42, 2, 138, 14, 42, 2
  db 138, 14, 42, 2, 138, 14, 42, 2, 138, 14, 42, 2, 138, 14, 42, 2
  db 138, 14, 42, 2, 138, 14, 42, 2, 138, 14, 42, 2, 138, 1, 42, 1
  db 138, 10, 42, 1, 138, 1, 42, 2, 138, 14, 42, 17


gooma_squish:
  db 16, 16, 248, 146, 0, 1, 114, 10, 0, 1, 248, 3, 0, 1, 114, 1
  db 15, 1, 0, 1, 114, 6, 0, 1, 15, 1, 114, 1, 0, 1, 248, 1
  db 114, 3, 15, 1, 0, 1, 114, 6, 0, 1, 15, 1, 114, 19, 248, 1
  db 88, 14, 248, 2, 88, 14, 248, 2, 0, 4, 248, 6, 0, 4, 248, 1

goomba:
  db 16, 16, 248, 5, 0, 6, 248, 8, 0, 2, 114, 6, 0, 2, 248, 5
  db 0, 1, 114, 10, 0, 1, 248, 3, 0, 1, 114, 2, 15, 2, 114, 4
  db 15, 2, 114, 2, 0, 1, 248, 2, 114, 3, 15, 1, 0, 1, 114, 4
  db 0, 1, 15, 1, 114, 3, 248, 2, 114, 3, 15, 1, 0, 1, 114, 4
  db 0, 1, 15, 1, 114, 3, 248, 2, 114, 3, 15, 1, 0, 1, 114, 4
  db 0, 1, 15, 1, 114, 3, 248, 1, 114, 4, 15, 2, 114, 4, 15, 2
  db 114, 20, 248, 2, 114, 12, 248, 5, 138, 10, 248, 5, 138, 2, 29, 8
  db 138, 2, 248, 3, 0, 3, 138, 8, 0, 3, 248, 1, 0, 5, 248, 6
  db 0, 10, 248, 6, 0, 5, 248, 1, 0, 3, 248, 8, 0, 3, 248, 1

koopa:
  db 16, 16, 248, 6, 67, 4, 248, 11, 67, 6, 248, 10, 67, 2, 15, 2
  db 67, 2, 248, 10, 67, 2, 0, 1, 15, 1, 67, 2, 248, 10, 67, 2
  db 15, 2, 67, 2, 248, 11, 67, 4, 248, 8, 120, 12, 248, 3, 120, 9
  db 49, 2, 120, 3, 248, 1, 120, 3, 49, 2, 120, 5, 49, 3, 120, 5
  db 49, 3, 120, 6, 49, 2, 120, 6, 49, 2, 120, 11, 15, 2, 120, 12
  db 15, 18, 248, 1, 15, 14, 248, 2, 67, 2, 248, 3, 67, 4, 248, 3
  db 67, 2, 248, 1, 67, 3, 248, 3, 67, 4, 248, 3, 67, 3

mario_idle:
  db 16, 16, 248, 6, 40, 4, 248, 10, 114, 1, 40, 8, 248, 7, 114, 3
  db 88, 2, 15, 1, 88, 1, 248, 8, 114, 1, 88, 1, 114, 1, 88, 3
  db 15, 1, 88, 3, 248, 6, 114, 1, 88, 1, 114, 2, 88, 6, 248, 6
  db 114, 2, 88, 4, 114, 3, 248, 9, 88, 7, 248, 7, 40, 2, 32, 1
  db 40, 6, 248, 6, 40, 3, 32, 1, 40, 4, 32, 1, 40, 2, 248, 4
  db 88, 1, 40, 2, 248, 1, 32, 6, 40, 3, 248, 3, 88, 3, 248, 1
  db 32, 1, 43, 1, 32, 2, 43, 1, 32, 1, 248, 1, 40, 2, 88, 1
  db 248, 3, 88, 1, 248, 2, 32, 6, 248, 1, 88, 3, 248, 5, 32, 8
  db 248, 2, 88, 1, 248, 5, 32, 3, 248, 2, 32, 3, 248, 8, 114, 2
  db 248, 4, 114, 2, 248, 7, 114, 3, 248, 4, 114, 3, 248, 3

mario_jump:
  db 16, 16, 248, 6, 40, 4, 248, 10, 114, 1, 40, 8, 248, 7, 114, 3
  db 88, 2, 15, 1, 88, 1, 248, 8, 114, 1, 88, 1, 114, 1, 88, 3
  db 15, 1, 88, 3, 248, 1, 88, 2, 248, 3, 114, 1, 88, 1, 114, 2
  db 88, 6, 248, 1, 88, 2, 248, 3, 114, 2, 88, 4, 114, 3, 248, 1
  db 88, 1, 40, 1, 88, 1, 248, 5, 88, 7, 248, 1, 40, 2, 248, 3
  db 40, 4, 32, 1, 40, 2, 32, 1, 40, 4, 248, 2, 88, 1, 40, 5
  db 32, 1, 40, 3, 32, 1, 40, 3, 248, 2, 88, 2, 248, 2, 40, 1
  db 32, 6, 248, 3, 114, 1, 248, 1, 88, 1, 248, 3, 40, 1, 32, 1
  db 43, 1, 32, 2, 43, 1, 32, 1, 248, 1, 32, 1, 114, 2, 248, 3
  db 114, 1, 248, 1, 40, 1, 32, 8, 114, 2, 248, 3, 114, 2, 32, 7
  db 248, 7, 114, 2, 32, 6, 248, 11, 32, 3, 248, 24

mario_run1:
  db 16, 16, 248, 6, 40, 4, 248, 10, 114, 1, 40, 8, 248, 7, 114, 3
  db 88, 2, 15, 1, 88, 1, 248, 8, 114, 1, 88, 1, 114, 1, 88, 3
  db 15, 1, 88, 3, 248, 6, 114, 1, 88, 1, 114, 2, 88, 6, 248, 6
  db 114, 2, 88, 4, 114, 3, 248, 9, 88, 7, 248, 8, 40, 1, 32, 1
  db 40, 6, 248, 7, 40, 2, 32, 1, 40, 4, 32, 1, 40, 2, 248, 6
  db 40, 2, 32, 6, 40, 2, 248, 5, 88, 1, 40, 2, 32, 1, 43, 1
  db 32, 2, 43, 1, 32, 1, 40, 2, 88, 1, 248, 4, 88, 3, 32, 6
  db 40, 1, 88, 2, 248, 5, 88, 1, 248, 1, 32, 6, 248, 1, 88, 1
  db 248, 9, 32, 5, 248, 11, 114, 2, 248, 1, 114, 2, 248, 11, 114, 6
  db 248, 4

mario_run2:
  db 16, 16, 248, 6, 40, 4, 248, 10, 114, 1, 40, 8, 248, 7, 114, 3
  db 88, 2, 15, 1, 88, 1, 248, 8, 114, 1, 88, 1, 114, 1, 88, 3
  db 15, 1, 88, 3, 248, 6, 114, 1, 88, 1, 114, 2, 88, 6, 248, 6
  db 114, 2, 88, 4, 114, 3, 248, 9, 88, 7, 248, 6, 40, 3, 32, 1
  db 40, 6, 248, 4, 88, 1, 40, 4, 32, 1, 40, 4, 32, 1, 40, 3
  db 88, 4, 248, 3, 32, 6, 248, 1, 40, 3, 88, 2, 248, 4, 32, 1
  db 43, 1, 32, 2, 43, 1, 32, 1, 248, 4, 88, 1, 248, 4, 32, 7
  db 248, 3, 114, 1, 248, 4, 32, 10, 114, 2, 248, 3, 32, 3, 248, 5
  db 32, 3, 114, 2, 248, 3, 114, 2, 248, 14, 114, 3, 248, 11

mushroom:
  db 16, 16, 248, 20, 0, 8, 248, 7, 0, 2, 41, 2, 43, 3, 41, 1
  db 0, 2, 248, 5, 0, 2, 41, 2, 43, 4, 41, 2, 0, 2, 248, 3
  db 0, 2, 41, 3, 43, 5, 41, 2, 0, 2, 248, 2, 0, 1, 43, 1
  db 41, 2, 43, 6, 41, 3, 0, 1, 248, 1, 0, 2, 43, 5, 41, 3
  db 43, 4, 0, 3, 41, 1, 43, 4, 41, 5, 43, 4, 0, 2, 41, 3
  db 43, 2, 41, 5, 43, 4, 0, 2, 41, 3, 43, 3, 41, 2, 43, 4
  db 41, 2, 0, 2, 41, 2, 0, 10, 41, 2, 0, 5, 15, 2, 0, 1
  db 15, 2, 0, 1, 15, 2, 0, 4, 248, 1, 0, 2, 15, 3, 0, 1
  db 15, 2, 0, 1, 15, 3, 0, 2, 248, 3, 0, 1, 15, 10, 0, 1
  db 248, 4, 0, 2, 15, 8, 0, 2, 248, 5, 0, 10, 248, 3

shell:
  db 16, 16, 248, 20, 120, 8, 248, 7, 120, 10, 248, 5, 120, 2, 72, 3
  db 120, 3, 72, 2, 120, 2, 248, 4, 120, 1, 72, 3, 120, 4, 72, 3
  db 120, 1, 248, 3, 120, 3, 72, 2, 120, 5, 72, 2, 120, 2, 248, 2
  db 120, 11, 72, 1, 120, 2, 248, 2, 120, 14, 248, 2, 15, 3, 120, 8
  db 15, 3, 248, 2, 15, 14, 248, 1, 15, 2, 0, 2, 15, 8, 0, 2
  db 15, 4, 0, 2, 15, 8, 0, 2, 15, 18, 248, 1, 15, 14, 248, 3
  db 15, 12, 248, 5, 15, 10, 248, 3

;basically an array of adresses for the assets. index 0 means draw nthn (sky) everything else points to an asset
tileTable:
  dw 0
  dw dirtGrass
  dw dirt
  dw brick
  dw questionBlock
  dw coin
  dw stair

worldMap:
;     0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9
  db  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,5,5,5,5,5,5,5,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ; Row 0
  db  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ; Row 1
  db  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,3,3,3,3,3,3,3,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ; Row 2
  db  0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,5,5,0,0,0,0,0,0,0,0,0,0,5,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ; Row 3
  db  0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,3,3,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 ; Row 4
  db  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0,3,3,3,3,3,3,0,0,0,0,0,0,5,0,0,0,0,0,0,0,0,0,0,0,0,5,0,0,0,0,0,0,0,0 ; Row 5
  db  0,0,0,0,0,0,0,0,0,0,3,3,3,3,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,3,0,0,0,5,0,0,0,0,0,0,0,0,0,0,0,0,0,5,6,0,0,0,0,0,0,0,0 ; Row 6
  db  0,0,0,0,0,0,0,3,3,4,3,0,0,0,0,0,3,0,0,0,0,3,4,3,3,0,0,0,0,0,0,0,3,3,0,0,3,4,3,4,0,0,0,0,0,0,0,0,0,5,6,6,0,0,0,0,0,0,0,0 ; Row 7
  db  0,0,0,0,5,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,5,0,0,0,5,0,5,0,0,0,0,0,0,0,0,0,0,0,0,0,5,5,5,5,5,0,5,6,6,6,0,0,0,0,0,0,0,0 ; Row 8
  db  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6,6,6,6,0,0,0,0,0,0,0,0 ; Row 9
  db  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1 ; Row 10
  db  2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0,0,0,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2 ; Row 11

bufferSegment: dw 0

stackSpace: times 1024 db 0
stackTop:

programEnd:
