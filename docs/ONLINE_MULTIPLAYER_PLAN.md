# Online multiplayer — design plan

Status: **phases 0, 1 and 2 are implemented; phase 3 onwards is still a plan.**

Online play is now reachable from the app: a player can create a game, share a
six-character code, have a friend join it, play a full game, and rejoin one in
progress. Clocks, resign and draw are not built. The sections below describe
the whole design; see [Implementation status](#implementation-status) for what
is built and what has and has not been verified.

## 1. What we are building

Two people on different devices play one game of Quoridor in real time.

In scope for v1:

- Play a friend via a share link / room code.
- Random matchmaking into a public queue.
- Live board sync with a visible "opponent is thinking" state.
- Reconnect into a game in progress after a crash, backgrounding, or network drop.
- Resign, offer draw, and a per-move clock.

Explicitly out of scope for v1: ranked ladders, ELO, spectators, chat,
tournaments, cross-platform friend lists. Each is easy to add later on the same
data model; none of them is needed to learn whether people want to play online
at all.

## 2. Why this is a good moment

The app is on both stores and has ~200 installs with no marketing behind it.
That is a small number in absolute terms but it is entirely organic, which
makes it a usable signal: people are finding a Quoridor app and installing it.
The single biggest reason a board game like this gets uninstalled is having
nobody to play against, and right now the only opponent is the AI.

It also means we should keep v1 cheap. 200 users does not justify running
dedicated game servers.

## 3. Firebase vs Supabase

| | Firebase | Supabase |
|---|---|---|
| Already in this project | **Yes** — `firebase_core`, `firebase_auth`, `cloud_firestore` are dependencies, `firebase_options.dart` and `firebase.json` are committed, and the project `quoridor-290f6` exists | No — new project, new SDK, new auth flow |
| Realtime model | Firestore snapshot listeners, or Realtime Database for low-latency state | Postgres logical replication over WebSocket |
| Anonymous auth | First-class, one call, already a dependency | Supported |
| Server-side validation | Cloud Functions (TypeScript) | Edge Functions (Deno) or Postgres functions in PL/pgSQL |
| Authorization | Security Rules (custom DSL) | Row Level Security (SQL policies) |
| Querying for matchmaking | Weak — no real joins, no transactional `SELECT ... FOR UPDATE` | **Strong** — real SQL, real transactions |
| Free tier for our size | Comfortable | Comfortable |
| Cost shape at scale | Per document read/write — chatty listeners get expensive | Per compute hour — more predictable |

**Recommendation: Firebase.**

The deciding factor is not that Firebase is better in the abstract — for
matchmaking specifically, Supabase's real transactions are a genuinely nicer
fit. It is that Firebase is already wired into this app. Auth, config, and the
save/resume path in `FirebaseService` all exist. Choosing Supabase means
carrying two backends or doing a migration before writing a single line of
multiplayer, and neither is worth it to avoid one awkward matchmaking query.

Revisit this if we later want server-authoritative ranked play with real
analytics — at that point Postgres earns its keep.

## 4. Architecture

### 4.1 The central question: who validates a move?

Three options:

1. **Trusted client.** Each client applies its own move and writes the result.
   Simple, zero server code, and completely open to a modified client writing
   an illegal board.
2. **Mutually verifying clients.** Each client validates the opponent's move
   locally with `GameService.isValidMove` and refuses to advance on an illegal
   one. A cheater cannot force an honest client to accept an illegal board;
   they can only desync and get dropped.
3. **Server authoritative.** Clients submit *intents*; a Cloud Function holds
   the rules, validates, and writes the new state. Clients cannot write game
   documents at all.

**Plan: ship v1 on (2), design the data model so (3) is a drop-in upgrade.**

Option 2 gets us online play without porting the rule engine, and for a casual
friend-vs-friend game it is proportionate. The upgrade path matters though, so
from day one clients must submit **moves, not boards** (see 4.3). When we move
to (3), the Cloud Function starts consuming the same move documents and the
client write permission is revoked in Security Rules — no data migration.

The honest cost of deferring: a determined cheater can desync a public
matchmaking game. That is acceptable while there is no ranking to protect, and
it is the main reason ranked play is out of scope for v1.

### 4.2 What the current code already gives us

The existing code is in better shape for this than it might look:

- `GameState`, `Player`, `Wall`, `Position` and `GameMove` all already have
  `toJson`/`fromJson`. The wire format is essentially written.
- `GameService` is pure and static — no UI, no globals, no Flame types. The
  same functions validate a local move, a remote move, and (after a TypeScript
  port) a server-side move.
- `GameService.validateWallPlacement` returns a typed reason, so a rejected
  remote move can be reported precisely instead of failing silently.
- Sound is now driven off `moveHistory` diffs in `QuoridorGame`, so a move that
  arrives from the network plays its effect with no extra work.

The pieces that do **not** yet exist: a turn owner concept (the game currently
assumes both players are on this device), a clock, and any notion of a local
player identity.

### 4.3 Data model (Firestore)

```
/games/{gameId}
  status:        'waiting' | 'active' | 'finished' | 'abandoned'
  createdAt:     Timestamp
  updatedAt:     Timestamp
  players: {
    '1': { uid, displayName, connected: bool, lastSeen: Timestamp },
    '2': { uid, displayName, connected: bool, lastSeen: Timestamp }
  }
  currentPlayerId: 1 | 2
  moveCount:     int          // monotonic; doubles as the optimistic-lock token
  board:         { ...GameState.toJson() }   // derived cache, see below
  clock:         { '1': millisRemaining, '2': millisRemaining, updatedAt }
  outcome:       { winner: 1|2|null, reason: 'goal'|'resign'|'timeout'|'draw' }

/games/{gameId}/moves/{index}     // index is zero-padded, so ordering is lexical
  ...GameMove.toJson()
  submittedBy:   uid
  submittedAt:   Timestamp
```

Two deliberate choices:

- **`moves` is the source of truth; `board` is a cache.** Replaying the move
  list reconstructs any position, which gives us reconnect, move history, and a
  server-authoritative upgrade for free. `board` exists so a joining client
  renders immediately without replaying 60 documents.
- **`moveCount` is the optimistic lock.** A move is submitted in a transaction
  that asserts `moveCount == n` and writes move `n`. Two clients racing on the
  same turn cannot both win; the loser retries and discovers it is no longer
  their turn.

### 4.4 Move submission flow

```
local player taps "Place wall"
  → GameService.validateWallPlacement   (already runs today, unchanged)
  → optimistic local apply, board shows the wall immediately
  → Firestore transaction:
        assert games/{id}.currentPlayerId == me
        assert games/{id}.moveCount == n
        write  games/{id}/moves/{n}
        update games/{id}: board, currentPlayerId, moveCount = n+1, clock
  → on rejection: roll back to the last confirmed board, show why
```

The receiving client listens on the game document, sees `moveCount` advance,
re-validates the new move against its own state with `GameService`, applies it,
and re-renders. If validation fails, it stops and reports a desync rather than
rendering a board it believes is illegal.

### 4.5 Matchmaking

Firestore has no transactional queue primitive, so:

- **Private games (build first).** Creator writes `/games/{id}` with
  `status: 'waiting'` and a 6-character room code. The friend looks the code
  up and joins in a transaction that asserts slot 2 is still empty. No queue,
  no contention, and it covers the "play with a friend" case that is most of
  the value.
- **Public queue (build second).** A `/queue/{uid}` document per waiting
  player. A Cloud Function triggered on queue writes pairs two entries and
  creates the game. Pairing in a Function rather than on clients avoids the
  race where three clients all believe they matched with each other.

### 4.6 Presence, reconnect, and clocks

- Each client heartbeats `players.{n}.lastSeen` every 10s while in a game.
- A client whose `lastSeen` is older than 30s is shown as disconnected; the
  opponent sees "Opponent disconnected — 60s to reconnect".
- Reconnect is just re-attaching the listener: the board document plus the
  move list fully describe the game.
- **Clocks must be server-referenced.** Store deadlines as Firestore
  timestamps, not client-side countdowns, and let a scheduled Function settle
  a game whose deadline has passed. Client-side clocks will drift and will be
  trivially cheatable.

### 4.7 Security Rules sketch

```
match /games/{gameId} {
  allow read:   if isPlayer(gameId);
  allow create: if request.auth != null && isWellFormedNewGame();
  allow update: if isPlayer(gameId)
                && onlyTurnFieldsChanged()
                && request.resource.data.moveCount == resource.data.moveCount + 1
                && resource.data.currentPlayerId == playerNumberOf(request.auth.uid);

  match /moves/{index} {
    allow read:   if isPlayer(gameId);
    allow create: if isPlayer(gameId) && index == string(resource.data.moveCount);
    allow update, delete: if false;   // moves are immutable
  }
}
```

Rules enforce *structure and turn order*, not *Quoridor rules* — expressing
pathfinding in the Rules DSL is not realistic. Rule enforcement is the client's
job in v1 and the Cloud Function's job in v2.

## 5. Client work

New:

- `lib/flame/services/online_game_service.dart` — session lifecycle, listeners,
  transactional move submission.
- `lib/flame/models/online_session.dart` — who am I, whose turn, connection
  state, clock.
- Lobby UI: create / join by code / find opponent / rejoin game in progress.

Changed:

- `QuoridorGame` needs a `localPlayerId`. Today `GameManager.canPlayerMove`
  answers "is it this player's turn", which is the same question for a hotseat
  game but not for an online one — an online client must also refuse input when
  it is the *opponent's* turn even though that turn is "active".
- `GamePage` needs a connection banner and a surface for resign/draw.
- `GameStateFactory.createNewGame` generates a local `gameId`; online games take
  theirs from the server.

Unchanged: the board rendering, the wall interaction added in this change, the
rule engine, and the audio service. That is the point of the split.

## 6. Phasing

| Phase | Deliverable | Rough size | Status |
|---|---|---|---|
| 0 | Anonymous auth on launch; stable per-device identity | small | **done** |
| 1 | Data model, Security Rules, `OnlineGameService`, private room codes | large | **done** |
| 2 | Lobby UI, reconnect, presence | medium | **done** |
| 3 | Clocks, resign, draw, timeout settlement Function | medium | next |
| 4 | Public matchmaking queue + pairing Function | medium | |
| 5 | Cloud Function move validation (TypeScript rule port) + revoke client writes | large | |
| 6 | Ranked play, ELO — only once 5 is done | — | |

Phases 0–2 are the smallest thing that is actually playable with a friend, and
are what I would ship and measure before committing to the rest.

## 7. Risks

- **Rule-port drift (phase 5).** Two implementations of Quoridor's rules, in
  Dart and TypeScript, will disagree eventually. Mitigation: a shared JSON
  corpus of positions and expected legality, run in both test suites.
- **Firestore listener cost.** Each client listening to a game document pays a
  read per move. At our size this is free; at 100k games/day it is not. Measure
  before it matters, and move hot state to Realtime Database if it does.
- **Abandoned games.** People close the app mid-game. Without a scheduled
  cleanup Function, `waiting` and `active` games accumulate forever. Build the
  TTL cleanup in the same phase as the clock, not later.
- **Deferred anti-cheat.** Known and accepted for v1, as long as ranked play
  waits for phase 5.

## Implementation status

### Built (phases 0, 1 and 2)

| Piece | Where |
|---|---|
| Anonymous auth, stable device identity, generated display name | `lib/flame/services/identity_service.dart` |
| Room codes: generation, normalizing, validation | `lib/flame/services/online/room_code.dart` |
| Session model, seat resolution, turn ownership | `lib/flame/models/online_session.dart` |
| Wire format for games and moves | `lib/flame/services/online/online_game_codec.dart` |
| Create / join / watch / submit move / abandon | `lib/flame/services/online/online_game_service.dart` |
| Security Rules and the room-code index | `firestore.rules`, `firestore.indexes.json` |
| `localPlayerId` so the board refuses input on the opponent's turn | `lib/flame/game/quoridor_game.dart` |
| Session lifecycle, presence heartbeat, connection state | `lib/flame/services/online/online_game_controller.dart` |
| Create / join by code / rejoin in progress | `lib/flame/pages/online_lobby_page.dart` |
| Online banner, turn gating, leave game | `lib/flame/pages/game_page.dart` |
| Security Rules tests against the emulator | `test/rules/` |

Decisions worth recording, because the code now depends on them:

- **Room code alphabet excludes `I`, `L` and `0`.** Codes get read aloud, so
  `normalize` folds a typed `0` onto `O` and a typed `I` or `L` onto `1`. A
  player who mishears a code still joins the right game.
- **Seat 2 is written with the dotted path `players.2`.** Writing a nested
  `players` map would replace the whole object and wipe player 1.
- **Move documents are zero-padded to six digits.** Lexical ordering is the
  only ordering Firestore gives for free, and this makes it match play order.
- **`moveCount` is asserted inside the transaction**, not read beforehand.
  That assertion is the entire concurrency story: two clients cannot both
  write move N.
- **The rules are checked twice**, by the submitting client before the write
  and again by the receiving client when the move arrives. Security Rules
  cannot express pathfinding, so they enforce structure and turn order only.
- **The local board follows the server, not the tap.** A move is not applied
  optimistically: it is submitted, and the board changes when the change comes
  back. A refused move therefore never appears to have happened, which is what
  keeps two clients from drifting apart.
- **The heartbeat is its own Security Rule.** Presence writes land every ten
  seconds, so `isValidPresenceUpdate` pins them to the writer's own seat and
  forbids them touching the board, status, turn or counter — otherwise the
  heartbeat would be a way around every other rule. Four tests cover that.
- **Presence timeout is three missed heartbeats** (35s against a 10s beat), so
  one slow round trip does not show a false "opponent away".

### What has actually been verified

Being precise about this matters, because the gap is real:

- **Verified.** The Security Rules, against the Firestore emulator — 30 tests
  covering creates, joins, moves, the move counter, presence, the append-only
  move log, and reads by non-players. These run in CI.
- **Verified.** The pure client layers: room codes, seat and turn resolution,
  the wire format. 62 Dart tests in total.
- **Verified.** That the lobby and the game screen render, and that local play
  is unaffected.
- **Not verified.** The end-to-end flow against a live Firestore: create, share
  the code, join from a second device, play a game to a win. The client
  transactions are exercised only by the rules tests' stand-ins, not by the Dart
  code itself. **This needs a real two-device run before anyone would call it
  shippable.**

### Not built yet

- **Clocks.** Deliberately left out rather than half-implemented: they must be
  server-referenced to be either fair or cheat-resistant, which is phase 3.
- **Resign and draw.** `abandon` exists as a blunt instrument; the proper
  outcome flow is phase 3.
- **Abandoned-game cleanup.** Nothing removes games nobody returns to.
- **Public matchmaking**, server-side validation, ranked play — phases 4 to 6.

### Deploying the rules

The rules are not live until they are pushed to the project:

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

Until then the project's existing rules apply, and online play will be refused.
Anonymous authentication must also be enabled in the Firebase console
(Authentication → Sign-in method → Anonymous).

### Running the rules tests

```bash
cd test/rules && npm install && cd ../..
npx firebase-tools emulators:exec --only firestore \
  --project quoridor-rules-test "cd test/rules && npm test"
```

Requires Node and a JRE, since the Firestore emulator runs on the JVM.
