import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

class GameCelebrate extends StatelessWidget {
  const GameCelebrate({
    required this.child,
    required this.confettiController,
    super.key,
  });

  final Widget child;
  final ConfettiController confettiController;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: confettiController,
            blastDirection: pi / 2,
            maxBlastForce: 5,
            minBlastForce: 2,
            emissionFrequency: 0.05,
            numberOfParticles: 50,
            gravity: 0.1,
            shouldLoop: false,
            colors: const [
              Colors.green,
              Colors.blue,
              Colors.pink,
              Colors.orange,
              Colors.purple,
              Colors.yellow,
            ],
          ),
        ),
        // Bottom Right Confetti
        Align(
          alignment: Alignment.bottomRight,
          child: ConfettiWidget(
            confettiController: confettiController,
            blastDirection: -pi / 4,
            maxBlastForce: 5,
            minBlastForce: 2,
            emissionFrequency: 0.05,
            numberOfParticles: 50,
            gravity: 0.1,
            shouldLoop: false,
            colors: const [
              Colors.green,
              Colors.blue,
              Colors.pink,
              Colors.orange,
              Colors.purple,
              Colors.yellow,
            ],
          ),
        ),
        // Bottom Left Confetti
        Align(
          alignment: Alignment.bottomLeft,
          child: ConfettiWidget(
            confettiController: confettiController,
            blastDirection: -3 * pi / 4,
            maxBlastForce: 5,
            minBlastForce: 2,
            emissionFrequency: 0.05,
            numberOfParticles: 50,
            gravity: 0.1,
            shouldLoop: false,
            colors: const [
              Colors.green,
              Colors.blue,
              Colors.pink,
              Colors.orange,
              Colors.purple,
              Colors.yellow,
            ],
          ),
        ),
      ],
    );
  }
}
