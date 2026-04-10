# Bomberman Online

A multiplayer **Bomberman** clone built using a **thick-server, thin-client** architecture. All game logic runs on the server; clients receive state updates and render them in real time. The project was developed for CS 150 (Programming Languages), 1st Semester AY 2025-2026 at the University of the Philippines Diliman.

Two complete implementations were built — one in **Dart** (using Flutter + Flame) and one in **Haskell** (using Miso) — with a shared JSON-over-WebSocket protocol. Cross-pairing (any client ↔ any server) is supported up to Phase 4; see [Branches](#branches) below.

> **LLM Attribution:** This project made use of LLMs (Claude, ChatGPT) during development. Prompt logs are in [`llm-dart.pdf`](llm-dart.pdf) and [`llm-haskell.pdf`](llm-haskell.pdf) as required by course policy.

---

## Phases Accomplished

| Implementation  | Highest Phase |
|-----------------|---------------|
| Dart Server     | **Phase 5**   |
| Dart Client     | **Phase 5**   |
| Haskell Server  | **Phase 4**   |
| Haskell Client  | **Phase 4**   |

Phase scoring reference: Phase 3 = 100/100, Phase 4 = 110/100, Phase 5 = 120/100 (bonus).

---

## Branches & Tags

| Ref | Type | Contents | Cross-pairing |
|-----|------|----------|---------------|
| `main` (this branch) | branch | Dart Phase 5 + Haskell Phase 4 | **No** — the Dart Phase 5 lobby protocol is incompatible with the Haskell Phase 4 client/server |
| `phase-4` | tag | Dart Phase 4 + Haskell Phase 4 | **Yes** — both implementations share the same Phase 4 JSON-over-WebSocket protocol |

> To run any Dart client against any Haskell server (or vice versa), check out the **`phase-4` tag**:
> ```bash
> git checkout phase-4
> ```

---

## Features

### Phase 1 — Single-machine game
- 15×13 grid with hard (indestructible) and soft (destructible) blocks
- Smooth sub-cell player movement with collision detection against blocks and bombs
- Bomb planting (Spacebar), 3-second fuse, 1-second explosion with chain reactions
- Soft blocks destroyed by explosions; walking into lingering explosions eliminates the player
- 1-minute countdown timer (mm:ss); game ends on player death or timer expiry
- Game-over screen with movement/bomb input disabled

### Phase 2 — Client–server split via WebSockets
- Server and client are separate programs communicating over WebSockets + JSON
- Server listens on port 15000; client connects to `ws://127.0.0.1:15000`
- Players can walk through each other (no player–player collision)
- **Powerups** drop from destroyed soft blocks (10% chance each):
  - 🔥 **Fire Up** — increases explosion range by 1
  - 💣 **Bomb Up** — increases maximum active bombs by 1
  - ⚡ **Speed Up** — increases movement speed
- Spacebar must be released and re-pressed between bombs
- Unique sprites for all game entities; sound effects for explosions, death, and powerup collection

### Phase 3 — Two-player LAN multiplayer
- Game waits for exactly 2 clients before starting; further connections are rejected
- First client is P1, second is P2 — each with a distinct sprite color palette and label
- Playable over LAN (configurable server IP and port via command-line arguments)
- Win/draw logic: 1-second delay after a player is eliminated before declaring a winner; simultaneous elimination results in a draw
- Win, lose, and draw sound effects

### Phase 4 — 2–4 player support with configurable settings
- Server accepts 2, 3, or 4 players (validated; invalid values abort startup)
- Timer duration is configurable (30–600 seconds, validated)
- Soft blocks are **randomly generated** — each free cell has a 40% spawn chance
- Player sprites for all four players are easily distinguishable

### Phase 5 (Dart only, bonus) — In-game lobby menu
- No command-line flags needed; the program opens a menu on startup
- **Host** flow: configure port, number of players (2–5), and timer; lobby shows connected players; all must confirm before the game starts
- **Join** flow: enter host IP and port; lobby shown on successful connection
- The hosting player is automatically assigned P1
- 3-second countdown ("3 / 2 / 1") before gameplay; movement and bombs disabled during countdown
- Full directional walking animations, animated bombs, explosions, powerups, and soft-block destruction

---

## Architecture

```text
                         ┌─────────────────────────────────────┐
                         │         AUTHORITATIVE SERVER        │
                         │   (either Dart Server or Haskell)   │
                         │                                     │
                         │  ┌───────────────────────────────┐  │
                         │  │ Lobby / Session Manager       │  │
                         │  │ - accepts players             │  │
                         │  │ - assigns player IDs          │  │
                         │  │ - starts match                │  │
                         │  └───────────────┬───────────────┘  │
                         │                  │                  │
                         │  ┌───────────────▼───────────────┐  │
                         │  │ Game Logic / Rules Engine     │  │
                         │  │ - movement & collision        │  │
                         │  │ - bombs & explosions          │  │
                         │  │ - powerups                    │  │
                         │  │ - timer / win / draw logic    │  │
                         │  └───────────────┬───────────────┘  │
                         │                  │                  │
                         │  ┌───────────────▼───────────────┐  │
                         │  │ WebSocket / JSON Handler      │  │
                         │  │ - receives input events       │  │
                         │  │ - broadcasts game state       │  │
                         │  └───────────────────────────────┘  │
                         └─────────────────────────────────────┘
                                         ▲
                         JSON InputEvent │ │ JSON GameState
                                         │ ▼
        ┌──────────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐
        │     Dart Client      │   │    Haskell Client    │   │   More Clients...    │
        │   Flutter + Flame    │   │    Miso + Canvas     │   │   up to match limit   │
        │ - sends player input │   │ - sends player input │   │ - sends player input  │
        │ - renders game state │   │ - renders game state │   │ - renders game state  │
        └──────────────────────┘   └──────────────────────┘   └──────────────────────┘
```

The server is the single source of truth. Clients only send input events (move, plant bomb) and render whatever state they receive.

---

## Running the Game

### Dart (Phase 5 — built-in lobby menu)

```bash
cd dart_project
flutter run -d <device>   # e.g., -d chrome or -d linux
```

On startup, choose **Host** or **Join** from the menu and follow the prompts.

---

### Haskell (Phase 4 — command-line arguments)

**Server:**
```bash
cd haskell-project/haskell-server
# <num_players> <timer_seconds> --host <port>
cabal run . -- 2 60 --host 15000
```

**Client (each player in a separate terminal):**
```bash
cd haskell-project/haskell-client

# connect with IP and port flags
cabal run . -- --ip 127.0.0.1 --port 15000

# or serve locally via browser (open http://localhost:11111)
PORT=11111 cabal run . -- 127.0.0.1 15000
```

> **Note:** The Haskell client uses jsaddle-warp during development to serve the Miso app locally in the browser.

---

### Cross-pairing (any server ↔ any client)

> **Note:** Cross-pairing only works at the **`phase-4` tag**. On `main`, the Dart Phase 5 lobby protocol is incompatible with the Haskell Phase 4 implementation. Run `git checkout phase-4` before running the commands below.

Both Phase 4 implementations share the same JSON-over-WebSocket protocol, so any combination works — e.g., Haskell server with Dart client:

```bash
# Terminal 1 — Haskell server
cd haskell-project/haskell-server && cabal run . -- 2 60 --host 15000

# Terminal 2 — Dart client (enter 127.0.0.1 and 15000 in the Join menu)
cd dart_project && flutter run
```

---

## Controls

| Action              | Key        |
|---------------------|------------|
| Move                | Arrow keys |
| Plant bomb          | Spacebar   |
| Teleport (Part 2 demo) | T       |

---

## Technologies

| Layer           | Dart                           | Haskell                        |
|-----------------|--------------------------------|--------------------------------|
| Game engine     | Flame 1.34                     | Miso (compiled to JS)          |
| Networking      | `web_socket_channel`, Shelf    | `websockets`, `warp`           |
| Serialization   | `dart:convert` (JSON)          | `aeson`                        |
| Audio           | `flame_audio`                  | JSaddle FFI (`Audio` API)      |
| UI              | Flutter widgets + Flame overlays | Miso HTML + Canvas           |

---

## Team

| Member              | Part 2 Option          | Pair                          | Video |
|---------------------|------------------------|-------------------------------|-------|
| Fan Anjelo Gabrielli | Option 2: Teleport    | Haskell Server + Dart Client  | [Watch](https://drive.google.com/file/d/1Yhlzh3FrZ2RhqVLJZy4uGCptKG16Vutc/view?usp=sharing) |
| Eliana Mari Lim     | Option 1: Five Players | Dart Server + Any Client      | [Watch](https://drive.google.com/file/d/1TjtiRRnijR0s0vgArfg0Bc4C75Eo4HQb/view?usp=sharing) |
| Jon Gabrel Mayuyu   | Option 6: Reverse Movement | Dart Server + Dart Client | [Watch](https://drive.google.com/file/d/1q1DUo54Qp2CRD-12WYTMSlK-XFhI9wz9/view?usp=drive_link) |
| Charlize Sim        | Option 4: Vest (Haskell) | Dart Server + Dart Client   | [Watch](https://drive.google.com/file/d/1aC46SyjXrVA07QhbN2XM1IyeHF4d5dPt/view?usp=sharing) |
