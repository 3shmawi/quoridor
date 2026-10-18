import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  getDocs,
  collection,
  query,
  orderBy,
  limit,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
  writeBatch,
  Timestamp,
} from 'firebase/firestore';

/**
 * These run against the Firestore emulator and exercise firestore.rules
 * directly. They are the only thing that checks the rules at all: the Dart
 * suite covers the client, but the rules are the boundary that has to hold
 * even when the client is modified, so they need their own coverage.
 */

const ALICE = 'uid-alice';
const BOB = 'uid-bob';
const MALLORY = 'uid-mallory';

let testEnv;

const SEATS = {
  1: { position: { row: 8, col: 4 }, goal: 'top' },
  2: { position: { row: 0, col: 4 }, goal: 'bottom' },
  3: { position: { row: 4, col: 0 }, goal: 'right' },
  4: { position: { row: 4, col: 8 }, goal: 'left' },
};
const WALLS_FOR = { 2: 10, 3: 7, 4: 5 };

/** A board as GameState.toJson writes it, for [count] seats. */
function board({ currentPlayerId = 1, count = 2 } = {}) {
  const players = [];
  for (let id = 1; id <= count; id++) {
    players.push({
      id,
      position: { ...SEATS[id].position },
      wallsRemaining: WALLS_FOR[count],
      goal: SEATS[id].goal,
      name: `Player ${id}`,
      isAI: false,
    });
  }
  return {
    gameId: 'game-1',
    players,
    player1: players[0],
    player2: players[1],
    walls: [],
    currentPlayerId,
    status: 0,
    createdAt: 0,
    updatedAt: 0,
    moveHistory: [],
  };
}

/** [b] after the player to move plays [move], as GameService would. */
function play(b, move) {
  const next = structuredClone(b);
  const seat = b.currentPlayerId;
  const mover = next.players[seat - 1];
  if (move.type === 0) mover.position = move.newPosition;
  if (move.type === 1) {
    next.walls.push(move.wall);
    mover.wallsRemaining -= 1;
  }
  next.moveHistory.push({
    type: move.type,
    newPosition: move.newPosition ?? null,
    wall: move.wall ?? null,
    playerId: seat,
  });
  next.player1 = next.players[0];
  next.player2 = next.players[1];
  next.updatedAt = 1;
  next.currentPlayerId = (seat % next.players.length) + 1;
  return next;
}

const step = (row, col) => ({ type: 0, newPosition: { row, col } });
const wall = (row, col, orientation) => ({
  type: 1,
  wall: { position: { row, col }, orientation },
});
const pass = { type: 2 };

/** The update a client writes for [next], the board after move [count]. */
function moveWrite(next, count) {
  return {
    board: next,
    currentPlayerId: next.currentPlayerId,
    moveCount: count,
    updatedAt: serverTimestamp(),
  };
}

function player(uid, displayName) {
  return { uid, displayName, connected: true, lastSeen: 0 };
}

/** A game document as the client would write it. */
function waitingGame(creatorUid = ALICE) {
  return {
    roomCode: 'ABCDEF',
    status: 'waiting',
    players: { 1: player(creatorUid, 'Alice') },
    currentPlayerId: 1,
    moveCount: 0,
    board: board(),
    createdAt: 0,
    updatedAt: 0,
  };
}

function activeGame({ currentPlayerId = 1, moveCount = 0 } = {}) {
  return {
    roomCode: 'ABCDEF',
    status: 'active',
    players: { 1: player(ALICE, 'Alice'), 2: player(BOB, 'Bob') },
    currentPlayerId,
    moveCount,
    board: board({ currentPlayerId }),
    createdAt: 0,
    updatedAt: 0,
  };
}

/** Seeds a document bypassing the rules, for arranging test state. */
async function seed(path, data) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

function db(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'quoridor-rules-test',
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

describe('creating a game', () => {
  it('lets a signed-in player create a game seated as player 1', async () => {
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'games/new-1'), waitingGame(ALICE)),
    );
  });

  it('refuses an unauthenticated create', async () => {
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(anon, 'games/new-2'), waitingGame(ALICE)));
  });

  it('refuses a game seated as somebody else', async () => {
    // Claiming another player's uid would let you play on their behalf.
    await assertFails(
      setDoc(doc(db(ALICE), 'games/new-3'), waitingGame(BOB)),
    );
  });

  it('refuses a game that starts already active', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'games/new-4'), {
        ...waitingGame(ALICE),
        status: 'active',
      }),
    );
  });

  it('refuses a game that starts with moves already played', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'games/new-5'), {
        ...waitingGame(ALICE),
        moveCount: 7,
      }),
    );
  });

  it('refuses a malformed room code', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'games/new-6'), {
        ...waitingGame(ALICE),
        roomCode: 'TOOLONG',
      }),
    );
  });
});

describe('joining a game', () => {
  it('lets a second player take the empty seat', async () => {
    await seed('games/join-1', waitingGame(ALICE));
    await assertSucceeds(
      updateDoc(doc(db(BOB), 'games/join-1'), {
        'players.2': player(BOB, 'Bob'),
        status: 'active',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses joining with somebody else’s uid', async () => {
    await seed('games/join-2', waitingGame(ALICE));
    await assertFails(
      updateDoc(doc(db(MALLORY), 'games/join-2'), {
        'players.2': player(BOB, 'Bob'),
        status: 'active',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses joining a game that is already full', async () => {
    await seed('games/join-3', activeGame());
    await assertFails(
      updateDoc(doc(db(MALLORY), 'games/join-3'), {
        'players.2': player(MALLORY, 'Mallory'),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses a join that also displaces player 1', async () => {
    await seed('games/join-4', waitingGame(ALICE));
    await assertFails(
      updateDoc(doc(db(BOB), 'games/join-4'), {
        'players.1': player(BOB, 'Bob'),
        'players.2': player(BOB, 'Bob'),
        status: 'active',
        updatedAt: serverTimestamp(),
      }),
    );
  });
});

describe('three and four players', () => {
  const CAROL = 'uid-carol';
  const DAN = 'uid-dan';

  function tableOf(count, seated) {
    const players = {};
    seated.forEach((uid, i) => (players[i + 1] = player(uid, uid)));
    return {
      ...waitingGame(ALICE),
      playerCount: count,
      players,
      board: board({ count: Math.min(count, 4) }),
    };
  }

  it('lets a game be created for four', async () => {
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'games/four-1'), tableOf(4, [ALICE])),
    );
  });

  it('refuses a game for five', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'games/four-2'), tableOf(5, [ALICE])),
    );
  });

  it('keeps the game waiting until the last seat fills', async () => {
    await seed('games/four-3', tableOf(3, [ALICE]));
    // Going live with a seat still empty is refused...
    await assertFails(
      updateDoc(doc(db(BOB), 'games/four-3'), {
        'players.2': player(BOB, 'Bob'),
        status: 'active',
        updatedAt: serverTimestamp(),
      }),
    );
    // ...staying waiting is not.
    await assertSucceeds(
      updateDoc(doc(db(BOB), 'games/four-3'), {
        'players.2': player(BOB, 'Bob'),
        status: 'waiting',
        updatedAt: serverTimestamp(),
      }),
    );
    // The last seat takes it live.
    await assertSucceeds(
      updateDoc(doc(db(CAROL), 'games/four-3'), {
        'players.3': player(CAROL, 'Carol'),
        status: 'active',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses a seat past the game size', async () => {
    await seed('games/four-4', tableOf(3, [ALICE, BOB]));
    await assertFails(
      updateDoc(doc(db(DAN), 'games/four-4'), {
        'players.4': player(DAN, 'Dan'),
        status: 'waiting',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses taking a second seat', async () => {
    await seed('games/four-5', tableOf(4, [ALICE, BOB]));
    await assertFails(
      updateDoc(doc(db(BOB), 'games/four-5'), {
        'players.3': player(BOB, 'Bob'),
        status: 'waiting',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('lets seat three move on its turn only', async () => {
    const before = board({ count: 3, currentPlayerId: 3 });
    const live = {
      ...tableOf(3, [ALICE, BOB, CAROL]),
      status: 'active',
      currentPlayerId: 3,
      board: before,
    };
    await seed('games/four-6', live);
    const after = play(before, step(4, 1));
    await assertFails(
      updateDoc(doc(db(BOB), 'games/four-6'), moveWrite(after, 1)),
    );
    // After seat three comes seat one again.
    assert.equal(after.currentPlayerId, 1);
    await assertSucceeds(
      updateDoc(doc(db(CAROL), 'games/four-6'), moveWrite(after, 1)),
    );
  });

  it('lets a heartbeat touch only the caller’s own seat', async () => {
    const live = { ...tableOf(3, [ALICE, BOB, CAROL]), status: 'active' };
    await seed('games/four-7', live);
    await assertSucceeds(
      updateDoc(doc(db(CAROL), 'games/four-7'), {
        'players.3.connected': true,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(db(CAROL), 'games/four-7'), {
        'players.1.connected': false,
        updatedAt: serverTimestamp(),
      }),
    );
  });
});

describe('playing a move', () => {
  it('lets the player to move advance the counter by one', async () => {
    await seed('games/move-1', activeGame({ currentPlayerId: 1 }));
    await assertSucceeds(
      updateDoc(
        doc(db(ALICE), 'games/move-1'),
        moveWrite(play(board(), step(7, 4)), 1),
      ),
    );
  });

  it('refuses a move from the player whose turn it is not', async () => {
    await seed('games/move-2', activeGame({ currentPlayerId: 1 }));
    await assertFails(
      updateDoc(doc(db(BOB), 'games/move-2'), {
        board: board({ currentPlayerId: 1 }),
        currentPlayerId: 1,
        moveCount: 1,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses a move from somebody not in the game', async () => {
    await seed('games/move-3', activeGame({ currentPlayerId: 1 }));
    await assertFails(
      updateDoc(doc(db(MALLORY), 'games/move-3'), {
        board: board({ currentPlayerId: 2 }),
        currentPlayerId: 2,
        moveCount: 1,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses skipping the move counter forward', async () => {
    // The counter is the optimistic lock; jumping it would break the
    // guarantee that two clients cannot both write move N.
    await seed('games/move-4', activeGame({ currentPlayerId: 1 }));
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/move-4'), {
        board: board({ currentPlayerId: 2 }),
        currentPlayerId: 2,
        moveCount: 5,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses rewinding the move counter', async () => {
    await seed('games/move-5', activeGame({ currentPlayerId: 1, moveCount: 4 }));
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/move-5'), {
        board: board({ currentPlayerId: 2 }),
        currentPlayerId: 2,
        moveCount: 3,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses a move that also rewrites the seats', async () => {
    await seed('games/move-6', activeGame({ currentPlayerId: 1 }));
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/move-6'), {
        board: board({ currentPlayerId: 2 }),
        currentPlayerId: 2,
        moveCount: 1,
        'players.2': player(MALLORY, 'Mallory'),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses a move in a game that has finished', async () => {
    await seed('games/move-7', { ...activeGame(), status: 'finished' });
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/move-7'), {
        board: board({ currentPlayerId: 2 }),
        currentPlayerId: 2,
        moveCount: 1,
        updatedAt: serverTimestamp(),
      }),
    );
  });
});

describe('the board a move writes', () => {
  // Each case starts from a fresh two-player game, Alice (seat 1) to move.
  let n = 0;
  async function fresh(start = board()) {
    const path = `games/board-${++n}`;
    await seed(path, { ...activeGame(), board: start });
    return doc(db(ALICE), path);
  }

  it('accepts a step, a jump-length step, a wall and a pass', async () => {
    await assertSucceeds(updateDoc(await fresh(), moveWrite(play(board(), step(7, 4)), 1)));
    await assertSucceeds(updateDoc(await fresh(), moveWrite(play(board(), step(6, 4)), 1)));
    await assertSucceeds(updateDoc(await fresh(), moveWrite(play(board(), wall(4, 3, 0)), 1)));
    await assertSucceeds(updateDoc(await fresh(), moveWrite(play(board(), pass), 1)));
  });

  it('refuses a step of more than two squares', async () => {
    // Straight to the goal row from the start.
    await assertFails(updateDoc(await fresh(), moveWrite(play(board(), step(4, 4)), 1)));
  });

  it('refuses standing still and calling it a step', async () => {
    await assertFails(updateDoc(await fresh(), moveWrite(play(board(), step(8, 4)), 1)));
  });

  it('refuses stepping onto another pawn', async () => {
    const start = board();
    start.players[1].position = { row: 7, col: 4 };
    start.player2 = start.players[1];
    await assertFails(updateDoc(await fresh(start), moveWrite(play(start, step(7, 4)), 1)));
  });

  it('refuses moving somebody else’s pawn', async () => {
    const next = play(board(), step(7, 4));
    next.players[1].position = { row: 1, col: 4 };
    await assertFails(updateDoc(await fresh(), moveWrite(next, 1)));
  });

  it('refuses taking walls from somebody else', async () => {
    const next = play(board(), step(7, 4));
    next.players[1].wallsRemaining = 0;
    await assertFails(updateDoc(await fresh(), moveWrite(next, 1)));
  });

  it('refuses a wall that costs nothing', async () => {
    const next = play(board(), wall(4, 3, 0));
    next.players[0].wallsRemaining = 10;
    await assertFails(updateDoc(await fresh(), moveWrite(next, 1)));
  });

  it('refuses a wall with none left', async () => {
    const start = board();
    start.players[0].wallsRemaining = 0;
    const next = play(start, wall(4, 3, 0));
    next.players[0].wallsRemaining = 0;
    await assertFails(updateDoc(await fresh(start), moveWrite(next, 1)));
  });

  it('refuses a wall on the edge of the board', async () => {
    await assertFails(updateDoc(await fresh(), moveWrite(play(board(), wall(0, 3, 0)), 1)));
  });

  it('refuses a wall placed exactly on another', async () => {
    const start = board();
    start.walls.push({ position: { row: 4, col: 3 }, orientation: 0 });
    await assertFails(updateDoc(await fresh(start), moveWrite(play(start, wall(4, 3, 0)), 1)));
  });

  it('refuses taking a wall off the board', async () => {
    const start = board();
    start.walls.push({ position: { row: 4, col: 3 }, orientation: 0 });
    const next = play(start, step(7, 4));
    next.walls = [];
    await assertFails(updateDoc(await fresh(start), moveWrite(next, 1)));
  });

  it('refuses rewriting the history', async () => {
    const start = play(play(board(), step(7, 4)), step(1, 4));
    const path = `games/board-${++n}`;
    await seed(path, { ...activeGame({ moveCount: 2 }), board: start });
    const next = play(start, step(6, 4));
    next.moveHistory[0] = { ...next.moveHistory[0], newPosition: { row: 0, col: 0 } };
    await assertFails(updateDoc(doc(db(ALICE), path), moveWrite(next, 3)));
  });

  it('refuses keeping the turn', async () => {
    const next = play(board(), step(7, 4));
    next.currentPlayerId = 1;
    await assertFails(updateDoc(await fresh(), moveWrite(next, 1)));
  });

  it('refuses claiming a win short of the goal', async () => {
    const next = play(board(), step(7, 4));
    next.currentPlayerId = 1;
    next.status = 1;
    await assertFails(
      updateDoc(await fresh(), {
        ...moveWrite(next, 1),
        status: 'finished',
        outcome: { winner: 1, reason: 'goal' },
      }),
    );
  });

  it('accepts a win on reaching the goal, and not carrying on past it', async () => {
    const start = board();
    start.players[0].position = { row: 1, col: 0 };
    start.player1 = start.players[0];
    const won = play(start, step(0, 0));
    won.currentPlayerId = 1;
    won.status = 1;
    await assertSucceeds(
      updateDoc(await fresh(start), {
        ...moveWrite(won, 1),
        status: 'finished',
        outcome: { winner: 1, reason: 'goal' },
      }),
    );
    // Reaching the goal and playing on as if nothing happened is refused.
    await assertFails(updateDoc(await fresh(start), moveWrite(play(start, step(0, 0)), 1)));
  });
});

describe('moves the real client writes', () => {
  // Boards produced by GameService itself (see
  // test/online_rules_fixture_test.dart), so these prove the rules accept
  // what the game actually writes rather than what these tests think it
  // writes.
  const games = JSON.parse(
    readFileSync(new URL('./fixtures/real_games.json', import.meta.url), 'utf8'),
  );
  const UIDS = { 1: ALICE, 2: BOB, 3: 'uid-carol', 4: 'uid-dan' };

  for (const [name, boards] of Object.entries(games)) {
    it(`accepts every move of the ${name} game`, async () => {
      const count = boards[0].players.length;
      const seats = {};
      for (let seat = 1; seat <= count; seat++) seats[seat] = player(UIDS[seat], UIDS[seat]);
      const path = `games/real-${name}`;

      for (let i = 0; i + 1 < boards.length; i++) {
        const [before, after] = [boards[i], boards[i + 1]];
        await seed(path, {
          ...activeGame(),
          playerCount: count,
          players: seats,
          currentPlayerId: before.currentPlayerId,
          moveCount: i,
          board: before,
        });

        // What OnlineGameService.submitMove writes, in one transaction.
        const mover = UIDS[before.currentPlayerId];
        const store = db(mover);
        const write = {
          board: after,
          currentPlayerId: after.currentPlayerId,
          moveCount: i + 1,
          updatedAt: serverTimestamp(),
        };
        if (after.status !== 0) {
          write.status = 'finished';
          write.outcome = { winner: before.currentPlayerId, reason: 'goal' };
        }
        const batch = writeBatch(store);
        batch.set(doc(store, `${path}/moves/${String(i).padStart(6, '0')}`), {
          ...after.moveHistory[after.moveHistory.length - 1],
          submittedBy: mover,
          submittedAt: serverTimestamp(),
        });
        batch.update(doc(store, path), write);
        await assertSucceeds(batch.commit());
      }
    });
  }
});

describe('rematch', () => {
  async function setUpRematch(name, { status = 'finished', newSeat1 = BOB } = {}) {
    await seed(`games/${name}`, { ...activeGame(), status });
    await seed(`games/${name}-next`, {
      ...waitingGame(newSeat1),
      roomCode: 'NEXT22',
    });
    return doc(db(BOB), `games/${name}`);
  }
  const link = (name, by = 2) => ({
    rematch: { gameId: `${name}-next`, roomCode: 'NEXT22', by },
    updatedAt: serverTimestamp(),
  });

  it('lets a player link a rematch they created, once', async () => {
    const old = await setUpRematch('rm-1');
    await assertSucceeds(updateDoc(old, link('rm-1')));

    // A second game of Bob's cannot replace the link once it is there.
    await seed('games/rm-1-other', { ...waitingGame(BOB), roomCode: 'OTHER2' });
    await assertFails(
      updateDoc(old, {
        rematch: { gameId: 'rm-1-other', roomCode: 'OTHER2', by: 2 },
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses a rematch while the game is still on', async () => {
    const old = await setUpRematch('rm-2', { status: 'active' });
    await assertFails(updateDoc(old, link('rm-2')));
  });

  it('refuses linking a game the caller is not seated first in', async () => {
    const old = await setUpRematch('rm-3', { newSeat1: MALLORY });
    await assertFails(updateDoc(old, link('rm-3')));
  });

  it('refuses a rematch claimed for another seat', async () => {
    const old = await setUpRematch('rm-4');
    await assertFails(updateDoc(old, link('rm-4', 1)));
  });

  it('refuses a rematch link from outside the game', async () => {
    await setUpRematch('rm-5', { newSeat1: MALLORY });
    await assertFails(
      updateDoc(doc(db(MALLORY), 'games/rm-5'), link('rm-5', 0)),
    );
  });

  it('refuses smuggling other changes in with the link', async () => {
    const old = await setUpRematch('rm-6');
    await assertFails(
      updateDoc(old, { ...link('rm-6'), outcome: { winner: 2, reason: 'goal' } }),
    );
  });
});

describe('presence', () => {
  it('lets a player refresh their own heartbeat', async () => {
    await seed('games/presence-1', activeGame());
    await assertSucceeds(
      updateDoc(doc(db(ALICE), 'games/presence-1'), {
        'players.1.connected': true,
        'players.1.lastSeen': serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses touching the opponent’s presence', async () => {
    await seed('games/presence-2', activeGame());
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/presence-2'), {
        'players.2.connected': false,
        'players.2.lastSeen': serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses smuggling a board change into a heartbeat', async () => {
    // The heartbeat runs every few seconds, so it must not become a way
    // around the turn and counter rules.
    await seed('games/presence-3', activeGame({ currentPlayerId: 2 }));
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/presence-3'), {
        'players.1.lastSeen': serverTimestamp(),
        board: board({ currentPlayerId: 1 }),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses smuggling a counter change into a heartbeat', async () => {
    await seed('games/presence-4', activeGame({ currentPlayerId: 2 }));
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/presence-4'), {
        'players.1.lastSeen': serverTimestamp(),
        moveCount: 99,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses a heartbeat from a non-player', async () => {
    await seed('games/presence-5', activeGame());
    await assertFails(
      updateDoc(doc(db(MALLORY), 'games/presence-5'), {
        'players.1.lastSeen': serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
  });
});

describe('moves subcollection', () => {
  it('lets a player append a move under their own uid', async () => {
    await seed('games/log-1', activeGame());
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'games/log-1/moves/000000'), {
        type: 0,
        newPosition: { row: 7, col: 4 },
        playerId: 1,
        submittedBy: ALICE,
        submittedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses a move logged by somebody not in the game', async () => {
    await seed('games/log-5', activeGame());
    await assertFails(
      setDoc(doc(db(MALLORY), 'games/log-5/moves/000000'), {
        type: 0,
        newPosition: { row: 7, col: 4 },
        playerId: 1,
        submittedBy: MALLORY,
        submittedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses logging a move out of turn or at the wrong index', async () => {
    await seed('games/log-6', activeGame({ currentPlayerId: 1, moveCount: 3 }));
    const entry = (uid, playerId) => ({
      type: 0,
      newPosition: { row: 7, col: 4 },
      playerId,
      submittedBy: uid,
      submittedAt: serverTimestamp(),
    });
    await assertFails(setDoc(doc(db(BOB), 'games/log-6/moves/000003'), entry(BOB, 2)));
    await assertFails(setDoc(doc(db(ALICE), 'games/log-6/moves/000007'), entry(ALICE, 1)));
    await assertSucceeds(setDoc(doc(db(ALICE), 'games/log-6/moves/000003'), entry(ALICE, 1)));
  });

  it('refuses appending a move attributed to somebody else', async () => {
    await seed('games/log-2', activeGame());
    await assertFails(
      setDoc(doc(db(ALICE), 'games/log-2/moves/000000'), {
        type: 0,
        newPosition: { row: 7, col: 4 },
        playerId: 2,
        submittedBy: BOB,
        submittedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses editing a recorded move', async () => {
    // The move log is the record of what happened; it is append-only.
    await seed('games/log-3', activeGame());
    await seed('games/log-3/moves/000000', {
      type: 0,
      newPosition: { row: 7, col: 4 },
      playerId: 1,
      submittedBy: ALICE,
    });
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/log-3/moves/000000'), {
        newPosition: { row: 0, col: 4 },
      }),
    );
  });

  it('refuses deleting a recorded move', async () => {
    await seed('games/log-4', activeGame());
    await seed('games/log-4/moves/000000', {
      type: 0,
      playerId: 1,
      submittedBy: ALICE,
    });
    await assertFails(deleteDoc(doc(db(ALICE), 'games/log-4/moves/000000')));
  });
});

describe('reading and deleting', () => {
  it('lets a player read their own game', async () => {
    await seed('games/read-1', activeGame());
    await assertSucceeds(getDoc(doc(db(ALICE), 'games/read-1')));
  });

  it('refuses reading somebody else’s active game', async () => {
    await seed('games/read-2', activeGame());
    await assertFails(getDoc(doc(db(MALLORY), 'games/read-2')));
  });

  it('lets anyone signed in read a waiting game, so codes can be looked up', async () => {
    await seed('games/read-3', waitingGame(ALICE));
    await assertSucceeds(getDoc(doc(db(MALLORY), 'games/read-3')));
  });

  it('refuses deleting a game', async () => {
    await seed('games/read-4', activeGame());
    await assertFails(deleteDoc(doc(db(ALICE), 'games/read-4')));
  });
});

describe('chat', () => {
  /** A message as the client writes it. */
  const message = (seat, uid, code = 'laugh') => ({
    seat,
    uid,
    code,
    sentAt: serverTimestamp(),
  });

  it('lets a player send a reaction from their own seat', async () => {
    await seed('games/chat-1', activeGame());
    await assertSucceeds(
      setDoc(doc(db(BOB), 'games/chat-1/chat/m1'), message(2, BOB, 'scared')),
    );
  });

  it('lets the players read the chat, newest first', async () => {
    await seed('games/chat-2', activeGame());
    await seed('games/chat-2/chat/m1', { seat: 1, uid: ALICE, code: 'hello', sentAt: 0 });
    await assertSucceeds(
      getDocs(
        query(
          collection(db(BOB), 'games/chat-2/chat'),
          orderBy('sentAt', 'desc'),
          limit(50),
        ),
      ),
    );
  });

  it('keeps the chat from anyone outside the game', async () => {
    await seed('games/chat-3', activeGame());
    await assertFails(getDocs(collection(db(MALLORY), 'games/chat-3/chat')));
    await assertFails(
      setDoc(doc(db(MALLORY), 'games/chat-3/chat/m1'), message(1, MALLORY)),
    );
  });

  it('refuses speaking for somebody else’s seat', async () => {
    await seed('games/chat-4', activeGame());
    await assertFails(
      setDoc(doc(db(ALICE), 'games/chat-4/chat/m1'), message(2, ALICE)),
    );
    await assertFails(
      setDoc(doc(db(ALICE), 'games/chat-4/chat/m2'), message(1, BOB)),
    );
  });

  it('refuses a reaction that is not one of the fixed set', async () => {
    await seed('games/chat-5', activeGame());
    await assertFails(
      setDoc(doc(db(ALICE), 'games/chat-5/chat/m1'), message(1, ALICE, 'you are bad')),
    );
    await assertFails(
      setDoc(doc(db(ALICE), 'games/chat-5/chat/m2'), {
        ...message(1, ALICE),
        text: 'free text smuggled alongside',
      }),
    );
  });

  it('refuses a message dated by the sender', async () => {
    await seed('games/chat-6', activeGame());
    await assertFails(
      setDoc(doc(db(ALICE), 'games/chat-6/chat/m1'), { ...message(1, ALICE), sentAt: 0 }),
    );
  });

  it('lets the players chat after the game is over', async () => {
    await seed('games/chat-7', { ...activeGame(), status: 'finished' });
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'games/chat-7/chat/m1'), message(1, ALICE, 'goodGame')),
    );
  });

  it('never lets a sent message be changed or taken back', async () => {
    await seed('games/chat-8', activeGame());
    await seed('games/chat-8/chat/m1', { seat: 1, uid: ALICE, code: 'laugh', sentAt: 0 });
    await assertFails(updateDoc(doc(db(ALICE), 'games/chat-8/chat/m1'), { code: 'love' }));
    await assertFails(deleteDoc(doc(db(ALICE), 'games/chat-8/chat/m1')));
  });

  /** A typed message as the client writes it. */
  const typed = (seat, uid, text) => ({
    seat,
    uid,
    code: 'text',
    text,
    sentAt: serverTimestamp(),
  });

  it('lets a player type a short message, in any language', async () => {
    await seed('games/chat-9', activeGame());
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'games/chat-9/chat/m1'), typed(1, ALICE, 'مقصدش دي وربنا 😅')),
    );
    // The app's limit of eighty characters fits, whatever they are.
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'games/chat-9/chat/m2'), typed(1, ALICE, 'ب'.repeat(80))),
    );
    await assertSucceeds(
      setDoc(doc(db(ALICE), 'games/chat-9/chat/m3'), typed(1, ALICE, '😅'.repeat(80))),
    );
  });

  it('refuses a typed message that is empty or too long', async () => {
    await seed('games/chat-10', activeGame());
    await assertFails(
      setDoc(doc(db(ALICE), 'games/chat-10/chat/m1'), typed(1, ALICE, '')),
    );
    await assertFails(
      setDoc(doc(db(ALICE), 'games/chat-10/chat/m2'), typed(1, ALICE, 'a'.repeat(161))),
    );
    await assertFails(
      setDoc(doc(db(ALICE), 'games/chat-10/chat/m3'), typed(1, ALICE, 42)),
    );
  });

  it('refuses words smuggled onto a quick reaction', async () => {
    await seed('games/chat-11', activeGame());
    await assertFails(
      setDoc(doc(db(ALICE), 'games/chat-11/chat/m1'), {
        ...message(1, ALICE, 'laugh'),
        text: 'extra',
      }),
    );
  });

  it('refuses typing as somebody else, or from outside the game', async () => {
    await seed('games/chat-12', activeGame());
    await assertFails(
      setDoc(doc(db(ALICE), 'games/chat-12/chat/m1'), typed(2, ALICE, 'hi')),
    );
    await assertFails(
      setDoc(doc(db(MALLORY), 'games/chat-12/chat/m2'), typed(1, MALLORY, 'hi')),
    );
  });
});

describe('the host\u2019s turn limit', () => {
  it('lets the host pick one of the limits the app offers', async () => {
    for (const seconds of [0, 15, 30, 60]) {
      await assertSucceeds(
        setDoc(doc(db(ALICE), `games/limit-ok-${seconds}`), {
          ...waitingGame(),
          turnSeconds: seconds,
        }),
      );
    }
  });

  it('refuses a limit the app does not offer', async () => {
    await assertFails(
      setDoc(doc(db(ALICE), 'games/limit-bad'), { ...waitingGame(), turnSeconds: 1 }),
    );
  });

  it('refuses a joiner changing it', async () => {
    await seed('games/limit-join', { ...waitingGame(), turnSeconds: 15 });
    await assertFails(
      updateDoc(doc(db(BOB), 'games/limit-join'), {
        'players.2': player(BOB, 'Bob'),
        status: 'active',
        turnSeconds: 60,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      updateDoc(doc(db(BOB), 'games/limit-join'), {
        'players.2': player(BOB, 'Bob'),
        status: 'active',
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it('refuses changing it along with a move', async () => {
    await seed('games/limit-move', { ...activeGame(), turnSeconds: 15 });
    const next = play(board(), step(7, 4));
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/limit-move'), {
        ...moveWrite(next, 1),
        turnSeconds: 0,
      }),
    );
    await assertSucceeds(
      updateDoc(doc(db(ALICE), 'games/limit-move'), moveWrite(next, 1)),
    );
  });
});

describe('leaving a two-player game', () => {
  /** An active game where Bob last reported in [agoSeconds] ago. */
  const withBobLastSeen = (agoSeconds) => {
    const game = activeGame();
    game.players[2] = {
      ...game.players[2],
      lastSeen: Timestamp.fromMillis(Date.now() - agoSeconds * 1000),
    };
    return game;
  };
  const ending = (winner, reason) => ({
    status: 'finished',
    outcome: { winner, reason },
    updatedAt: serverTimestamp(),
  });

  it('lets a player resign, handing the win to the other', async () => {
    await seed('games/resign-1', activeGame());
    await assertSucceeds(
      updateDoc(doc(db(ALICE), 'games/resign-1'), ending(2, 'resign')),
    );
  });

  it('refuses resigning in one\u2019s own favour, or from outside', async () => {
    await seed('games/resign-2', activeGame());
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/resign-2'), ending(1, 'resign')),
    );
    await assertFails(
      updateDoc(doc(db(MALLORY), 'games/resign-2'), ending(1, 'resign')),
    );
  });

  it('refuses smuggling a board change into a resignation', async () => {
    await seed('games/resign-3', activeGame());
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/resign-3'), {
        ...ending(2, 'resign'),
        moveCount: 5,
      }),
    );
  });

  it('lets the win be claimed from a player gone for over a minute', async () => {
    await seed('games/claim-1', withBobLastSeen(120));
    await assertSucceeds(
      updateDoc(doc(db(ALICE), 'games/claim-1'), ending(1, 'timeout')),
    );
  });

  it('refuses claiming from a player who reported in recently', async () => {
    await seed('games/claim-2', withBobLastSeen(10));
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/claim-2'), ending(1, 'timeout')),
    );
  });

  it('refuses claiming when there is no server time to go by', async () => {
    // A seat written at join carries the client's own number, not a
    // server timestamp.
    await seed('games/claim-3', activeGame());
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/claim-3'), ending(1, 'timeout')),
    );
  });

  it('refuses claiming for the other player, or from a finished game', async () => {
    await seed('games/claim-4', withBobLastSeen(120));
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/claim-4'), ending(2, 'timeout')),
    );
    await seed('games/claim-5', { ...withBobLastSeen(120), status: 'finished' });
    await assertFails(
      updateDoc(doc(db(ALICE), 'games/claim-5'), ending(1, 'timeout')),
    );
  });
});

describe('draws', () => {
  const offer = (by, atMove = 0) => ({
    drawOffer: { by, atMove },
    updatedAt: serverTimestamp(),
  });
  const accept = {
    status: 'finished',
    outcome: { reason: 'draw' },
    updatedAt: serverTimestamp(),
  };
  const decline = { 'drawOffer.declined': true, updatedAt: serverTimestamp() };

  it('lets a player offer a draw, as themselves, at the current move', async () => {
    await seed('games/draw-1', activeGame());
    await assertSucceeds(updateDoc(doc(db(ALICE), 'games/draw-1'), offer(1)));
  });

  it('refuses an offer made for the other player, or at another move', async () => {
    await seed('games/draw-2', activeGame());
    await assertFails(updateDoc(doc(db(ALICE), 'games/draw-2'), offer(2)));
    await assertFails(updateDoc(doc(db(ALICE), 'games/draw-2'), offer(1, 3)));
    await assertFails(updateDoc(doc(db(MALLORY), 'games/draw-2'), offer(1)));
  });

  it('allows one offer per move', async () => {
    await seed('games/draw-3', {
      ...activeGame(),
      drawOffer: { by: 1, atMove: 0, declined: true },
    });
    await assertFails(updateDoc(doc(db(ALICE), 'games/draw-3'), offer(1)));
    await assertFails(updateDoc(doc(db(BOB), 'games/draw-3'), offer(2)));
    await seed('games/draw-4', {
      ...activeGame({ moveCount: 1, currentPlayerId: 2 }),
      drawOffer: { by: 1, atMove: 0, declined: true },
    });
    await assertSucceeds(updateDoc(doc(db(ALICE), 'games/draw-4'), offer(1, 1)));
  });

  it('lets the other player accept, ending the game with no winner', async () => {
    await seed('games/draw-5', { ...activeGame(), drawOffer: { by: 1, atMove: 0 } });
    await assertFails(updateDoc(doc(db(ALICE), 'games/draw-5'), accept));
    await assertSucceeds(updateDoc(doc(db(BOB), 'games/draw-5'), accept));
  });

  it('refuses accepting an offer that lapsed or was declined', async () => {
    await seed('games/draw-6', {
      ...activeGame({ moveCount: 1, currentPlayerId: 2 }),
      drawOffer: { by: 1, atMove: 0 },
    });
    await assertFails(updateDoc(doc(db(BOB), 'games/draw-6'), accept));
    await seed('games/draw-7', {
      ...activeGame(),
      drawOffer: { by: 1, atMove: 0, declined: true },
    });
    await assertFails(updateDoc(doc(db(BOB), 'games/draw-7'), accept));
  });

  it('refuses a "draw" that names a winner, or with no offer at all', async () => {
    await seed('games/draw-8', { ...activeGame(), drawOffer: { by: 1, atMove: 0 } });
    await assertFails(
      updateDoc(doc(db(BOB), 'games/draw-8'), {
        ...accept,
        outcome: { reason: 'draw', winner: 2 },
      }),
    );
    await seed('games/draw-9', activeGame());
    await assertFails(updateDoc(doc(db(BOB), 'games/draw-9'), accept));
  });

  it('lets only the other player decline, and only that', async () => {
    await seed('games/draw-10', { ...activeGame(), drawOffer: { by: 1, atMove: 0 } });
    await assertFails(updateDoc(doc(db(ALICE), 'games/draw-10'), decline));
    await assertFails(
      updateDoc(doc(db(BOB), 'games/draw-10'), { ...decline, 'drawOffer.by': 2 }),
    );
    await assertSucceeds(updateDoc(doc(db(BOB), 'games/draw-10'), decline));
  });
});

describe('reporting a chat message', () => {
  /** A report of [messageId], as OnlineGameCodec.encodeReport writes it. */
  const report = (gameId, messageId, overrides = {}) => ({
    gameId,
    messageId,
    reporterUid: ALICE,
    reporterSeat: 1,
    reportedUid: BOB,
    reportedSeat: 2,
    code: 'text',
    text: 'you are bad',
    reportedAt: serverTimestamp(),
    ...overrides,
  });

  async function arrange(gameId) {
    await seed(`games/${gameId}`, activeGame());
    await seed(`games/${gameId}/chat/m1`, {
      seat: 2, uid: BOB, code: 'text', text: 'you are bad', sentAt: 0,
    });
    await seed(`games/${gameId}/chat/m2`, { seat: 2, uid: BOB, code: 'angry', sentAt: 0 });
    await seed(`games/${gameId}/chat/m3`, { seat: 1, uid: ALICE, code: 'laugh', sentAt: 0 });
  }

  it('lets a player report what the other player wrote', async () => {
    await arrange('report-1');
    await assertSucceeds(setDoc(doc(db(ALICE), 'reports/r1'), report('report-1', 'm1')));
  });

  it('lets a player report a reaction, which has no text', async () => {
    await arrange('report-2');
    const { text, ...face } = report('report-2', 'm2', { code: 'angry' });
    await assertSucceeds(setDoc(doc(db(ALICE), 'reports/r2'), face));
  });

  it('refuses a report that misquotes the message', async () => {
    await arrange('report-3');
    await assertFails(
      setDoc(doc(db(ALICE), 'reports/r3'), report('report-3', 'm1', { text: 'something worse' })),
    );
    // Nor can a reaction be reported as typed words.
    await assertFails(setDoc(doc(db(ALICE), 'reports/r3b'), report('report-3', 'm2')));
  });

  it('refuses a report of a message that does not exist', async () => {
    await arrange('report-4');
    await assertFails(setDoc(doc(db(ALICE), 'reports/r4'), report('report-4', 'nope')));
  });

  it('refuses a report blaming the wrong sender', async () => {
    await arrange('report-5');
    await assertFails(
      setDoc(doc(db(BOB), 'reports/r5'), report('report-5', 'm3', {
        reporterUid: BOB, reporterSeat: 2, reportedUid: ALICE, reportedSeat: 1, code: 'laugh', text: 'x',
      })),
    );
    await assertFails(
      setDoc(doc(db(ALICE), 'reports/r5b'), report('report-5', 'm1', { reportedUid: MALLORY })),
    );
  });

  it('refuses reporting yourself, or as somebody else', async () => {
    await arrange('report-6');
    const { text, ...own } = report('report-6', 'm3', { reportedUid: ALICE, reportedSeat: 1, code: 'laugh' });
    await assertFails(setDoc(doc(db(ALICE), 'reports/r6'), own));
    await assertFails(setDoc(doc(db(BOB), 'reports/r6b'), report('report-6', 'm1')));
  });

  it('refuses a report from outside the game', async () => {
    await arrange('report-7');
    await assertFails(
      setDoc(doc(db(MALLORY), 'reports/r7'), report('report-7', 'm1', { reporterUid: MALLORY })),
    );
  });

  it('refuses extra fields and a back-dated report', async () => {
    await arrange('report-8');
    await assertFails(
      setDoc(doc(db(ALICE), 'reports/r8'), { ...report('report-8', 'm1'), note: 'ban him' }),
    );
    await assertFails(
      setDoc(doc(db(ALICE), 'reports/r8b'), report('report-8', 'm1', { reportedAt: Timestamp.fromMillis(0) })),
    );
  });

  it('keeps reports write-once and out of the app', async () => {
    await arrange('report-9');
    await seed('reports/r9', { gameId: 'report-9', reporterUid: ALICE });
    await assertFails(getDoc(doc(db(ALICE), 'reports/r9')));
    await assertFails(updateDoc(doc(db(ALICE), 'reports/r9'), { gameId: 'x' }));
    await assertFails(deleteDoc(doc(db(ALICE), 'reports/r9')));
  });
});
