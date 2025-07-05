import 'package:flame/components.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/widgets.dart';
import 'package:quoridor/flame/services/local_storage.dart';

abstract class GameSounds extends PositionComponent {
  static final Map<String, String> _soundAssets = {
    'move_p1': 'move_player1.wav',
    'move_p2': 'move_player2.wav',
    'wall_p1': 'wall_player1.wav',
    'wall_p2': 'wall_player2.wav',
    'win': 'win.wav',
  };

  static Future<void> preload() async {
    await FlameAudio.audioCache.loadAll(_soundAssets.values.toList());
  }

  static void triggerFeedback({String? soundKey}) async {
    if (CacheHelper.getData(key: "soundEnabled") == false) {
      return;
    }
    if (soundKey != null && _soundAssets.containsKey(soundKey)) {
      try {
        await FlameAudio.play(_soundAssets[soundKey]!);
      } catch (e) {
        debugPrint('Error playing sound: $e');
      }
    }
  }
}
