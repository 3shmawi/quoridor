/// Every sound effect the game plays.
///
/// [voices] is how many copies of a sound may ring at once. A move or a wall
/// is one event per turn, so two lets the AI's reply start while the player's
/// own move is still ringing out; the win fanfare plays once.
enum Sfx {
  move1('move_1.wav'),
  move2('move_2.wav'),
  move3('move_3.wav'),
  move4('move_4.wav'),
  wall1('wall_1.wav'),
  wall2('wall_2.wav'),
  wall3('wall_3.wav'),
  wall4('wall_4.wav'),
  win('win.wav', voices: 1),

  /// A chat message from another player popping up.
  chat('chat.wav', voices: 1);

  const Sfx(this.file, {this.voices = 2});

  /// File name under `assets/sounds/`.
  final String file;

  final int voices;

  /// Asset path as the audio package resolves it, relative to `assets/`.
  String get asset => 'sounds/$file';

  static const _moves = [move1, move2, move3, move4];
  static const _walls = [wall1, wall2, wall3, wall4];

  /// The pawn step for [seat]; every seat has its own pitch.
  static Sfx move(int seat) => _moves[(seat - 1) % _moves.length];

  /// The wall placement for [seat].
  static Sfx wall(int seat) => _walls[(seat - 1) % _walls.length];
}
