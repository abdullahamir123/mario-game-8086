; ============================================================
; NON-BLOCKING PC SPEAKER AUDIO ENGINE (PIT Channel 2 / Port 61h)
; Runs frame-by-frame at 70 Hz VGA sync without freezing gameplay
; ============================================================

initSound:
  CALL resetMusic
  RET

resetMusic:
  CALL speakerOff
  MOV WORD [bgmPtr], bgmOverworld
  MOV BYTE [bgmTimer], 0
  MOV WORD [sfxPtr], 0
  MOV BYTE [sfxTimer], 0
  RET

; Input: SI = pointer to sound effect table (dw divisor, dw frames, ..., 0xFFFF)
playSound:
  MOV [sfxPtr], SI
  MOV BYTE [sfxTimer], 0
  CALL updateSfx
  RET

; Called once per frame in gameLoop (70 Hz)
updateSound:
  PUSH AX
  PUSH DX
  PUSH SI
  CMP WORD [sfxPtr], 0
  JNE .runSfx
  CMP BYTE [bgmEnabled], 1
  JNE .muted
  CALL updateBgm
  JMP .exit
.runSfx:
  CALL updateSfx
  JMP .exit
.muted:
  CALL speakerOff
.exit:
  POP SI
  POP DX
  POP AX
  RET

; --- NON-BLOCKING SOUND EFFECT PLAYER ---
updateSfx:
  CMP WORD [sfxPtr], 0
  JE .done

  CMP BYTE [sfxTimer], 0
  JE .nextNote

  DEC BYTE [sfxTimer]
  JZ .nextNote
.done:
  RET

.nextNote:
  MOV SI, [sfxPtr]
  MOV AX, [SI]          ; PIT divisor (0xFFFF = end of SFX, 0 = rest)
  CMP AX, 0xFFFF
  JE .endSfx

  MOV DL, [SI + 2]      ; duration in frames (low byte)
  MOV [sfxTimer], DL
  ADD WORD [sfxPtr], 4

  CMP AX, 0
  JE .rest
  CALL setSpeakerDivisor
  RET

.rest:
  CALL speakerOff
  RET

.endSfx:
  MOV WORD [sfxPtr], 0
  MOV BYTE [sfxTimer], 0
  CALL speakerOff
  RET

; --- NON-BLOCKING BACKGROUND MUSIC PLAYER ---
updateBgm:
  CMP BYTE [bgmTimer], 0
  JE .nextNote

  DEC BYTE [bgmTimer]
  JZ .nextNote

  ; 1-frame staccato gap at the end of every note so repeated notes bounce
  CMP BYTE [bgmTimer], 1
  JNE .done
  CALL speakerOff
.done:
  RET

.nextNote:
  MOV SI, [bgmPtr]
  MOV AX, [SI]          ; PIT divisor (0xFFFF = loop back to start, 0 = rest)
  CMP AX, 0xFFFF
  JNE .play

  MOV SI, bgmOverworld
  MOV [bgmPtr], SI
  MOV AX, [SI]

.play:
  MOV DL, [SI + 2]      ; duration in frames (low byte)
  MOV [bgmTimer], DL
  ADD WORD [bgmPtr], 4

  CMP AX, 0
  JE .rest
  CALL setSpeakerDivisor
  RET

.rest:
  CALL speakerOff
  RET

; --- HARDWARE PIT CHANNEL 2 + PORT 61h ROUTINES ---
; Input: AX = PIT divisor (1193180 / Frequency_Hz)
setSpeakerDivisor:
  PUSH AX
  MOV AL, 0xB6          ; PIT Channel 2, lobyte/hibyte, square wave mode 3
  OUT 0x43, AL
  POP AX
  OUT 0x42, AL          ; send low byte
  MOV AL, AH
  OUT 0x42, AL          ; send high byte

  IN AL, 0x61
  OR AL, 0x03           ; turn on bits 0 & 1 (enable speaker gate + data)
  OUT 0x61, AL
  RET

speakerOff:
  IN AL, 0x61
  AND AL, 0xFC          ; clear bits 0 & 1 (guaranteed silence, never gets stuck)
  OUT 0x61, AL
  RET