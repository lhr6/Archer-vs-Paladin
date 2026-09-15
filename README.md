# Archer vs. Paladin — a Godot 4 mini action game

A small 3D third-person archer prototype built in **Godot 4.7** (Forward+, Jolt physics).
You play Erika the Archer; the Paladin enemy chases, attacks, and uses a whirlwind
cleave that knocks you back.

中文说明见 [`LICENSE_CN.md`](LICENSE_CN.md)。

## Features

- Bow aiming, charge shot, dodge roll, jump
- Global speed modes: **Tab** cycles 1x / 1.5x / 2x (affects animation speed, movement, gravity, timers)
- **F** melee kick — hit-stun with knockback on the Paladin
- Paladin AI: chase, sword attack, and a two-stage whirlwind cleave (gap-slash + ground crack + player launch)
- Procedurally generated brick floor texture and a few 3D combat sound effects

## Controls

| Key | Action |
|---|---|
| WASD | Move |
| Mouse | Aim camera |
| Right mouse (hold) | Draw / charge bow; release to shoot |
| Left mouse | Punch |
| F | Kick (knockback stun) |
| Shift | Dodge roll |
| Space | Jump |
| Tab | Cycle game speed 1x / 1.5x / 2x |

## License

Project code and self-made assets: **CC0 1.0** — see [`LICENSE`](LICENSE).
Character models are © Adobe Inc. (Mixamo) and remain subject to the Mixamo EULA.
Full attribution: [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
