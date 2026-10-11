import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quoridor/flame/constants.dart';
import 'package:quoridor/flame/game/quoridor_game.dart';
import 'package:quoridor/flame/models/game_state.dart';
import 'package:quoridor/flame/services/audio/audio_out.dart';
import 'package:quoridor/flame/services/audio_service.dart';
import 'package:quoridor/flame/services/game_service.dart';

/// Records what would have been played.
class FakeAudioOut implements AudioOut {
  final played = <Sfx>[];
  final volumes = <double>[];
  int preloads = 0;

  @override
  Future<void> preload() async => preloads++;

  @override
  void play(Sfx sfx, {double volume = 1}) {
    played.add(sfx);
    volumes.add(volume);
  }

  @override
  void stopAll() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScaledAudio', () {
    test('muted plays nothing', () {
      final fake = FakeAudioOut();
      ScaledAudio(fake, loudness: () => 0).play(Sfx.move1);
      expect(fake.played, isEmpty);
    });

    test('reads the loudness on every play', () {
      final fake = FakeAudioOut();
      var loudness = 1.0;
      final audio = ScaledAudio(fake, loudness: () => loudness);

      audio.play(Sfx.move1);
      loudness = 0.5;
      audio.play(Sfx.move1);

      expect(fake.volumes, [1.0, 0.5]);
    });

    test('drops sounds too quiet to hear', () {
      final fake = FakeAudioOut();
      ScaledAudio(fake, loudness: () => 0.01).play(Sfx.move1);
      expect(fake.played, isEmpty);
    });
  });

  group('the game', () {
    late FakeAudioOut fake;
    late QuoridorGame game;

    setUp(() async {
      fake = FakeAudioOut();
      AudioService.instance.debugOut = fake;
      AudioService.instance.enabled.value = true;
      game = QuoridorGame();
      await game.onLoad();
    });

    GameState start() =>
        GameStateFactory.createNewGame(player2IsAI: false, gameId: 'g');

    test('one move plays one sound, for the seat that moved', () {
      final moved = GameService.executeMove(
        start(),
        const GameMove.pawnMove(Position(7, 4), 1),
      );
      game.updateGameState(start());
      game.updateGameState(moved);
      expect(fake.played, [Sfx.move1]);

      // The same state arriving again -- a server echo, a rebuild -- is not a
      // new move and must not sound again.
      game.updateGameState(moved);
      expect(fake.played, [Sfx.move1]);
    });

    test('sound off plays nothing', () {
      AudioService.instance.enabled.value = false;
      game.updateGameState(start());
      game.updateGameState(
        GameService.executeMove(
          start(),
          const GameMove.pawnMove(Position(7, 4), 1),
        ),
      );
      expect(fake.played, isEmpty);
    });

    test('every seat has its own move and wall sound', () {
      expect({for (var s = 1; s <= 4; s++) Sfx.move(s)}, hasLength(4));
      expect({for (var s = 1; s <= 4; s++) Sfx.wall(s)}, hasLength(4));
    });
  });

  group('assets', () {
    test('every effect exists and is a short 16-bit WAV', () {
      for (final sfx in Sfx.values) {
        final file = File('assets/sounds/${sfx.file}');
        expect(file.existsSync(), isTrue, reason: sfx.file);

        final bytes = file.readAsBytesSync();
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        // Bits per sample sit at byte 34 of a canonical WAV header. 24-bit
        // files are what the old set had, and low-latency Android players
        // cannot decode them.
        expect(bytes[34], 16, reason: sfx.file);
        expect(bytes.length, lessThan(200 * 1024), reason: sfx.file);
      }
    });

    test('the sounds folder is listed in pubspec.yaml', () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('assets/sounds/'),
      );
    });

    test('only the backend imports an audio package', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('audioplayers_out.dart')) continue;
        final source = entity.readAsStringSync();
        if (source.contains('package:audioplayers') ||
            source.contains('package:flame_audio')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty);
    });
  });
}
