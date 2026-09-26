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
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
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

/** A minimal board, enough for the rules to see a well-formed document. */
function board({ currentPlayerId = 1 } = {}) {
  return {
    gameId: 'game-1',
    player1: { id: 1, position: { row: 8, col: 4 }, wallsRemaining: 10, goalRow: 0, name: 'Alice', isAI: false },
    player2: { id: 2, position: { row: 0, col: 4 }, wallsRemaining: 10, goalRow: 8, name: 'Bob', isAI: false },
    walls: [],
    currentPlayerId,
    status: 0,
    createdAt: 0,
    updatedAt: 0,
    moveHistory: [],
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

describe('playing a move', () => {
  it('lets the player to move advance the counter by one', async () => {
    await seed('games/move-1', activeGame({ currentPlayerId: 1 }));
    await assertSucceeds(
      updateDoc(doc(db(ALICE), 'games/move-1'), {
        board: board({ currentPlayerId: 2 }),
        currentPlayerId: 2,
        moveCount: 1,
        updatedAt: serverTimestamp(),
      }),
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
