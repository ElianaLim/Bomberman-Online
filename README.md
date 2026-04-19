# Bomberman Online

A multiplayer **Bomberman** clone built using a **thick-server, thin-client** architecture. All game logic runs on the server; clients receive state updates and render them in real time. The project was developed for CS 150 (Programming Languages), 1st Semester AY 2025-2026 at the University of the Philippines Diliman.

Two complete implementations were built — one in **Dart** (using Flutter + Flame) and one in **Haskell** (using Miso) — with a shared JSON-over-WebSocket protocol. Cross-pairing (any client ↔ any server) is supported up to Phase 4; see [Branches](#branches) below.

> **LLM Attribution:** This project made use of LLMs (Claude, ChatGPT) during development. Prompt logs are in [llm-dart.pdf](https://drive.google.com/file/d/11bo0F-6ioywxWLuxIBMjbbPVvPiEumvf/view?usp=sharing) and [llm-haskell.pdf](https://drive.google.com/file/d/1RE6sDbvJdc7Rxg1AAMYzlMtQql-oemXT/view?usp=sharing) as required by course policy.

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

### Core (both Dart and Haskell)
- 15×13 grid with hard (indestructible) and soft (destructible) blocks
- Smooth sub-cell player movement with collision detection against blocks and bombs
- Bomb planting (Spacebar), 3-second fuse, 1-second explosion with chain reactions
- Soft blocks destroyed by explosions; walking into lingering explosions eliminates the player
- **Powerups** drop from destroyed soft blocks (10% chance each): Fire Up, Bomb Up, Speed Up
- 2–4 player LAN multiplayer over WebSockets + JSON; configurable port and player count
- Configurable countdown timer (30–600 seconds)
- Randomly generated soft blocks (40% spawn chance per free cell)
- Distinct sprites for all four players; sound effects for explosions, death, powerups, win/lose/draw
- Win/draw logic with a 1-second delay after elimination; simultaneous elimination results in a draw

### Dart only (Phase 5 bonus)
- In-game lobby menu — no command-line flags needed
- **Host** flow: configure port, number of players (2–5), and timer; lobby shows connected players; all must confirm before starting
- **Join** flow: enter host IP and port; lobby shown on successful connection
- 3-second countdown ("3 / 2 / 1") before gameplay
- Full directional walking animations, animated bombs, explosions, powerups, and soft-block destruction

---

## Architecture

<!-- ```text
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
``` -->

**TODO: Architecture Diagram**

The server is the single source of truth. Clients only send input events (move, plant bomb) and render whatever state they receive.

---

## Prerequisites

### Dart

- **Flutter SDK** (includes Dart) — install via [flutter.dev](https://docs.flutter.dev/get-started/install)
  - Dart SDK ≥ 3.9.2 is required (bundled with Flutter)
- Verify your setup: `flutter doctor`
- Install dependencies: `cd dart_project && flutter pub get`

### Haskell

- **GHC 9.12.x** and **Cabal 3.14+** — install via [GHCup](https://www.haskell.org/ghcup/)
  ```bash
  ghcup install ghc 9.12
  ghcup install cabal 3.14
  ghcup set ghc 9.12
  ```
- Build dependencies (run once per project):
  ```bash
  cd haskell-project/haskell-server && cabal build
  cd haskell-project/haskell-client && cabal build
  ```
- The Haskell client runs as a local web server in dev mode — open the printed URL in a browser after starting it.

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

| Layer                | Dart                                        | Haskell                              |
|----------------------|---------------------------------------------|--------------------------------------|
| Game engine (client) | Flame 1.34                                  | Miso (via GHCJS or jsaddle-warp)     |
| Networking (server)  | `shelf`, `shelf_web_socket`, `shelf_router` | `websockets`                         |
| Networking (client)  | `web_socket_channel`                        | `Miso.Subscription.WebSocket` (browser WebSocket API via jsaddle-warp / GHCJS) |
| Serialization        | `dart:convert` (built-in JSON)              | `aeson`                              |
| Audio                | `flame_audio`                               | Web Audio API via JSaddle FFI        |
| UI                   | Flutter widgets + Flame overlays            | Miso HTML + Canvas                   |

---

## Team

| Member              | Part 2 Option          | Pair                          | Video |
|---------------------|------------------------|-------------------------------|-------|
| Fan Anjelo Gabrielli | Option 2: Teleport    | Haskell Server + Dart Client  | [Watch](https://drive.google.com/file/d/1Yhlzh3FrZ2RhqVLJZy4uGCptKG16Vutc/view?usp=sharing) |
| Eliana Mari Lim     | Option 1: Five Players | Dart Server + Any Client      | [Watch](https://drive.google.com/file/d/1TjtiRRnijR0s0vgArfg0Bc4C75Eo4HQb/view?usp=sharing) |
| Jon Gabrel Mayuyu   | Option 6: Reverse Movement | Dart Server + Dart Client | [Watch](https://drive.google.com/file/d/1q1DUo54Qp2CRD-12WYTMSlK-XFhI9wz9/view?usp=drive_link) |
| Charlize Sim        | Option 4: Vest (Haskell) | Dart Server + Dart Client   | [Watch](https://drive.google.com/file/d/1aC46SyjXrVA07QhbN2XM1IyeHF4d5dPt/view?usp=sharing) |
