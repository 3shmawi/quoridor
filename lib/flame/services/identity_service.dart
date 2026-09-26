import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'firebase_service.dart';

/// Who this device is, for the purposes of an online game.
///
/// Online play needs an identity that survives an app restart so a player can
/// rejoin a game in progress. Anonymous auth gives exactly that: Firebase
/// issues a uid on first launch and keeps it for the install, with no sign-up
/// to put in front of someone who only wants to play a board game.
///
/// The identity is deliberately thin. It is not an account, it does not carry
/// personal data, and it is lost if the app is reinstalled — which is
/// acceptable while there is nothing to lose but an in-progress game.
class IdentityService {
  IdentityService._();

  static final IdentityService instance = IdentityService._();

  /// Adjectives and nouns for a friendly default name, so an opponent sees
  /// "Swift Fox" rather than a 28-character uid.
  static const List<String> _adjectives = [
    'Swift',
    'Clever',
    'Bold',
    'Quiet',
    'Bright',
    'Keen',
    'Nimble',
    'Steady',
  ];

  static const List<String> _nouns = [
    'Fox',
    'Heron',
    'Otter',
    'Falcon',
    'Marten',
    'Ibex',
    'Lynx',
    'Crane',
  ];

  final ValueNotifier<LocalIdentity?> identity = ValueNotifier<LocalIdentity?>(
    null,
  );

  Future<LocalIdentity?>? _pending;

  /// The current identity, or null when the device has none yet.
  LocalIdentity? get current => identity.value;

  bool get isSignedIn => identity.value != null;

  /// Signs in anonymously if needed and returns the resulting identity.
  ///
  /// Returns null when Firebase is unavailable, which leaves local play
  /// entirely unaffected. Concurrent calls share one sign-in.
  Future<LocalIdentity?> ensureSignedIn() {
    final existing = identity.value;
    if (existing != null) return Future.value(existing);
    return _pending ??= _signIn();
  }

  Future<LocalIdentity?> _signIn() async {
    try {
      if (!FirebaseService.isReady) return null;

      final auth = FirebaseAuth.instance;
      var user = auth.currentUser;
      user ??= (await auth.signInAnonymously()).user;
      if (user == null) return null;

      // Give first-time players a readable name. Firebase stores it, so it
      // survives restarts without any local persistence of our own.
      var displayName = user.displayName;
      if (displayName == null || displayName.isEmpty) {
        displayName = generateDisplayName();
        try {
          await user.updateDisplayName(displayName);
        } catch (error) {
          // A name we could not persist is still usable for this session.
          debugPrint('IdentityService: could not store display name: $error');
        }
      }

      final result = LocalIdentity(uid: user.uid, displayName: displayName);
      identity.value = result;
      return result;
    } catch (error) {
      debugPrint('IdentityService: anonymous sign-in failed: $error');
      return null;
    } finally {
      _pending = null;
    }
  }

  /// Builds a random two-word name, e.g. "Nimble Otter".
  @visibleForTesting
  static String generateDisplayName([Random? random]) {
    final rng = random ?? Random();
    final adjective = _adjectives[rng.nextInt(_adjectives.length)];
    final noun = _nouns[rng.nextInt(_nouns.length)];
    return '$adjective $noun';
  }
}

/// This device's identity in an online game.
@immutable
class LocalIdentity {
  final String uid;
  final String displayName;

  const LocalIdentity({required this.uid, required this.displayName});

  @override
  bool operator ==(Object other) =>
      other is LocalIdentity &&
      other.uid == uid &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(uid, displayName);

  @override
  String toString() => 'LocalIdentity($displayName, $uid)';
}
