; enemy states: 0 = dead, 1 = walking, 2 = idle shell, 3 = sliding shell, 4 = squished goomba

; loops through all enemies and draws the active ones on screen
drawEnemies:
  ; we need two indexing registers because half arrays are dw and half are db
  XOR SI, SI ; byte index for arrays like state, type and timer
  XOR DI, DI ; word index for arrays like x, y and vel
  MOV CX, MAX_ENEMIES

.loopEnemy:
  CMP BYTE [enemyState + SI], 0
  JE .nextEnemy ; 0 means dead so dont draw

  ; convert worldX to screenX so we can skip enemies outside the screen
  MOV AX, [enemyX + DI]
  SUB AX, [cameraX]
  CMP AX, -16 ; only skip if completely off screen (right edge of enemy out of screen)
  JLE .nextEnemy ; completely off left edge (even its right side is hidden)
  CMP AX, SCREEN_WIDTH
  JGE .nextEnemy ; completely off right edge

  MOV [drawStartX], AX
  MOV AX, [enemyY + DI]
  MOV [drawStartY], AX

  CMP BYTE [enemyType + SI], 0
  JNE .isKoopa

  MOV BX, goomba
  CMP BYTE [enemyState + SI], 1
  JE .draw
  MOV BX, gooma_squish ; state 4 for goomba means squished flat
  JMP .draw

.isKoopa:
  MOV BX, koopa
  CMP BYTE [enemyState + SI], 1
  JE .draw
  MOV BX, shell ; state 2 (idle) or 3 (sliding) both use shell sprite

.draw:
  CALL drawAsset ; drawAsset saves all registers so our loop stays safe
.nextEnemy:
  INC SI
  ADD DI, 2
  LOOP .loopEnemy
  RET


; updates timers and horizontal patrol for all active enemies
updateEnemies:
  XOR SI, SI
  XOR DI, DI
  MOV CX, MAX_ENEMIES
.loop:
  CMP BYTE [enemyState + SI], 0
  JE .next

  ; state 4 is squished goomba, wait for timer to finish then remove it
  CMP BYTE [enemyState + SI], 4
  JNE .checkTimer
  DEC BYTE [enemyTimer + SI]
  JNZ .next ; still squished on ground, dont move it
  MOV BYTE [enemyState + SI], 0 ; timer finished so delete goomba
  JMP .next

.checkTimer:
  ; brief timer after mario kicks a shell so it doesnt hurt him right away
  CMP BYTE [enemyTimer + SI], 0
  JE .move
  DEC BYTE [enemyTimer + SI]

.move:
  CALL moveEnemyX

.next:
  INC SI
  ADD DI, 2
  LOOP .loop
  RET


; moves enemy and flips direction if it hits a wall or map edge
moveEnemyX:
  PUSH CX ; saving CX and SI because getTile overwrites both
  PUSH SI

  MOV CX, [enemyVelX + DI]
  CMP CX, 0
  JE .done ; stationary shell doesnt move horizontally

  ; check if next x goes out of world bounds
  MOV AX, [enemyX + DI]
  ADD AX, CX
  CMP AX, 0
  JL .bounce
  CMP AX, (MAPCOLUMNS * 16) - 16
  JG .bounce

  MOV BX, AX
  CMP CX, 0
  JL .checkLeft
  ADD BX, 13 ; right edge with 3px inset
  JMP .checkWall
.checkLeft:
  ADD BX, 2 ; left edge with 2px inset

.checkWall:
  MOV AX, [enemyY + DI]
  ADD AX, 8
  CALL getTile
  POP SI ; get our enemy index back right after getTile
  PUSH SI
  CMP AL, 0 ; 0 is sky so keep walking
  JE .applyMove
  CMP AL, 5 ; 5 is coin so walk right through it
  JE .applyMove

.bounce:
  NEG WORD [enemyVelX + DI] ; hit a solid block so turn around
  JMP .done
.applyMove:
  MOV AX, [enemyVelX + DI]
  ADD [enemyX + DI], AX
.done:
  POP SI
  POP CX
  RET


; checks if mario overlaps any active enemy using 16x16 box collision
checkEnemiesCollision:
  CMP BYTE [invulnerabilityTimer], 0
  JE .startCollisionLoop
  DEC BYTE [invulnerabilityTimer]
.startCollisionLoop:
  XOR SI, SI
  XOR DI, DI
  MOV CX, MAX_ENEMIES
.loop:
  MOV AL, [enemyState + SI]
  CMP AL, 0
  JE .nextEnemy
  CMP AL, 4
  JE .nextEnemy ; dont collide with squished goombas while they fade out

  ; if any of the 4 gaps exist, mario and enemy arent touching
  MOV AX, [marioWorldX]
  ADD AX, 15
  CMP AX, [enemyX + DI]
  JL .nextEnemy

  MOV BX, [enemyX + DI]
  ADD BX, 15
  CMP [marioWorldX], BX
  JG .nextEnemy

  MOV AX, [marioWorldY]
  ADD AX, 15
  CMP AX, [enemyY + DI]
  JL .nextEnemy

  MOV BX, [enemyY + DI]
  ADD BX, 15
  CMP [marioWorldY], BX
  JG .nextEnemy

  CALL onMarioHitEnemy
  CMP AL, 1
  JE .done ; mario died and level reset, no point checking other enemies

.nextEnemy:
  INC SI
  ADD DI, 2
  LOOP .loop

.done:
  RET


; decides if mario kicked a shell, stomped an enemy, or got hurt
; returns 1 if mario died and 0 if he didnt
onMarioHitEnemy:
  ; state 2 is always an idle koopa shell, so kick it away from mario
  CMP BYTE [enemyState + SI], 2
  JNE .checkStomp

  MOV BYTE [enemyState + SI], 3 ; turn into deadly sliding shell
  MOV BYTE [enemyTimer + SI], 10 ; short break so shell doesnt hit mario right as he kicks
  MOV AX, [marioWorldX]
  CMP AX, [enemyX + DI]
  JL .kickRight
  MOV WORD [enemyVelX + DI], -3 ; mario is on right so kick left
  JMP .survived
.kickRight:
  MOV WORD [enemyVelX + DI], 3 ; mario is on left so kick right
  JMP .survived

.checkStomp:
  ; must be falling and marios feet near top half of enemy
  CMP WORD [marioVelY], 0
  JLE .notStomp
  MOV AX, [marioWorldY]
  ADD AX, 6
  CMP AX, [enemyY + DI]
  JG .notStomp

  ; bounce mario up and give 100 score
  MOV WORD [marioVelY], -32
  MOV BYTE [isOnGround], 0
  ADD WORD [score], 100
  PUSH SI
  MOV SI, sfxStomp
  CALL playSound
  POP SI

  CMP BYTE [enemyType + SI], 0
  JNE .stompKoopa
  MOV BYTE [enemyState + SI], 4 ; goomba gets squished and waits 30 frames
  MOV BYTE [enemyTimer + SI], 30
  JMP .survived
.stompKoopa:
  MOV BYTE [enemyState + SI], 2 ; koopa or moving shell becomes idle shell
  MOV WORD [enemyVelX + DI], 0
  JMP .survived
.notStomp:
  ; if sliding shell was just kicked, ignore hit until grace timer hits 0
  CMP BYTE [enemyState + SI], 3
  JNE .hurtMario
  CMP BYTE [enemyTimer + SI], 0
  JG .survived
.hurtMario:
  CMP BYTE [invulnerabilityTimer], 0
  JG .survived 
  CMP WORD [superMario], 0 
  JE .marioDied
  MOV WORD [superMario], 0 
  MOV BYTE [invulnerabilityTimer], 90
  PUSH SI
  MOV SI, sfxBump
  CALL playSound
  POP SI
  JMP .survived
.marioDied:
  CALL resetLevel ; lose a life
  MOV AL, 1
  RET
.survived:
  XOR AL, AL
  RET


; checks if any sliding shell (state 3) hits other active enemies
checkShellCollisions:
  XOR SI, SI ; shell byte index
  XOR DI, DI ; shell word index
  MOV CX, MAX_ENEMIES

.outerLoop:
  CMP BYTE [enemyState + SI], 3
  JNE .nextI ; only sliding shells can kill other enemies

  PUSH CX ; save outer loop count before inner loop uses CX
  XOR BX, BX ; target byte index
  XOR BP, BP ; target word index
  MOV CX, MAX_ENEMIES

.innerLoop:
  CMP BX, SI
  JE .nextJ ; dont collide shell with itself
  CMP BYTE [enemyState + BX], 0
  JE .nextJ ; target is already dead
  CMP BYTE [enemyState + BX], 4
  JE .nextJ ; skip squished goomba so it doesnt get double killed

  CALL resolveShellHit

.nextJ:
  INC BX
  ADD BP, 2
  LOOP .innerLoop

  POP CX

.nextI:
  INC SI
  ADD DI, 2
  LOOP .outerLoop
  RET


; checks horizontal 16x16 collision between sliding shell (SI/DI) and target (BX/BP)
; note: using DS: with BP because BP normally defaults to SS segment
resolveShellHit:
  MOV AX, [enemyX + DI]
  ADD AX, 15
  CMP AX, [DS:enemyX + BP]
  JL .done

  MOV AX, [DS:enemyX + BP]
  ADD AX, 15
  CMP [enemyX + DI], AX
  JG .done

  ; shell hit target enemy so kill it and give 100 score
  MOV BYTE [enemyState + BX], 0
  ADD WORD [score], 100
.done:
  RET


; resets all enemies back to their starting positions/states
resetEnemies:
  XOR SI, SI
  XOR DI, DI
  MOV CX, MAX_ENEMIES
.loop:
  MOV AL, [initialEnemyState + SI]
  MOV [enemyState + SI], AL
  MOV AL, [initialEnemyType + SI]
  MOV [enemyType + SI], AL
  MOV BYTE [enemyTimer + SI], 0

  MOV AX, [initialEnemyX + DI]
  MOV [enemyX + DI], AX
  MOV AX, [initialEnemyY + DI]
  MOV [enemyY + DI], AX
  MOV AX, [initialEnemyVelX + DI]
  MOV [enemyVelX + DI], AX

  INC SI
  ADD DI, 2
  LOOP .loop
  RET
