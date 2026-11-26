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
  ; 0x19 is scancode for 'P'

  CMP BYTE [keyDown + 0x19], 1   
  JNE .notPaused
  CALL pauseMenu

.notPaused:
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
  MOV WORD [currentMarioTable], marioTableInverted; makes mario drawing turn left when drawn
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
  MOV WORD [currentMarioTable], marioTable; makes mario drawing turn right when drawn
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
  JE NEAR .noHorizontalMove ; 0 whole pixels to move this frame
  JL NEAR .tryMoveLeft ; negative means moving left
  JMP .tryMoveRight ; positive means moving right

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
  CMP AL, 0;coin
  JE .checkBottomLeftStep
  CMP AL, 5;sky
  JE .checkBottomLeftStep
  CMP AL, 17;mushroom
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
  CMP AL, 17
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
  CMP AL, 17
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
  CMP AL, 17
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
  CMP BYTE [jumpWasDown], 1
  JE .noJump  
  MOV BYTE [jumpWasDown], 1 ; prevents holding jump in air too

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
  AND BX, 7  ; keep remainder (0 to 7) in sub-pixel accumulator
  MOV [marioSubY], BX
  ADD WORD [marioWorldY], AX  ; move mario up or down by whole pixels
  CMP WORD [marioWorldY], SCREEN_HEIGHT
  JL .notPitFall
  CALL resetLevel
  ret
.notPitFall:
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
  CMP AL, 17
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
  CMP AL, 17
  JE .clearTile
  JMP .blocked

.clearTile:
  JMP .inAir;had to add because of short jumps gettign out of range
.blocked:

.hitHead:
; mario bonked his head on a solid block above him
; push his head down to the bottom edge of the block so he doesnt clip inside
  CMP AL, 4; check if the block he bonked is question block
  JNE .notQuestionBlock
  MOV BYTE [worldMap + SI], 7; turn questionblock into usedquestion
  CALL randomNum
  CMP AL, 0 ;we get back 0 to 3 between in AL using the randcom func we want 25 percent chance so we check if 0
  JE .mushroom
  MOV BYTE [worldMap + SI - MAPCOLUMNS], 5
  JMP .notQuestionBlock
.mushroom:
  MOV BYTE [worldMap + SI - MAPCOLUMNS], 17

.notQuestionBlock:
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
  CMP AL, 17
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
  JE .inAir
  CMP AL, 5; check if coin
  JE .inAir
  CMP AL, 17
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

randomNum:
  XOR AX, AX
  INT 1AH
  MOV AL, DL
  AND AL, 00000011B
  ret
