# Super Mario (8086 Assembly)

A Super Mario clone written from scratch in 16-bit x86 NASM assembly for MS-DOS, running in VGA Mode 13h (`320x200`, 256 colors).

## Features

- Side-scrolling tilemap (`160x12` tiles) with camera tracking
- Smooth sub-pixel movement, sprinting, gravity, and variable jump height
- Question blocks with coins and Super Mario mushrooms
- Goombas and Koopa Troopas (stompable, kickable shells that take out other enemies)
- Custom `INT 09h` keyboard handler for simultaneous key presses
- Double-buffered VGA rendering locked to 70 Hz vertical retrace
- Title screen, HUD (`COINS`, `SCORE`, `LIVES`), pause menu, game over, and flagpole win sequence

## Controls

| Action | Key |
|---|---|
| Move Left | `A` / `Left Arrow` |
| Move Right | `D` / `Right Arrow` |
| Sprint | Hold `Left Shift` |
| Jump | `W` / `Space` / `Up Arrow` |
| Pause | `P` |
| Start / Replay | `Enter` |
| Quit | `Esc` |

## Project Structure

```text
.
├── mario.asm          # Entry point (.COM), DOS memory setup, INT 09h handler, main game loop
└── mario/
    ├── ui.asm         # HUD, sky fill, menus (start, pause, game over, win), 1x/2x text rendering
    ├── render.asm     # Backbuffer blitting, VSync, RLE asset renderer, tilemap, camera, flagpole
    ├── player.asm     # Input handling, sub-pixel physics, gravity, tile & ?-block collisions
    ├── enemies.asm    # Enemy patrol, Goomba/Koopa state machine, stomp & shell collisions
    └── data.asm       # Game state, level map (worldMap / initialworldMap), RLE sprite/tile data
```

## Build & Run

### Requirements

- [NASM](https://www.nasm.us/)
- [DOSBox-X](https://dosbox-x.com/) (or any MS-DOS environment)

### Assemble

```bash
nasm -f bin mario.asm -o mario.com
```

