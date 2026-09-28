import 'package:flutter/widgets.dart';

import 'game_service.dart';
import 'online/online_game_service.dart';
import 'settings_service.dart';

/// Every piece of text the player sees.
///
/// A plain map per language rather than generated localisations: the app has
/// one screen and a drawer, and a map keeps the translation visible next to
/// the English rather than in a separate toolchain.
///
/// Look strings up with `context.l10n.someKey`, which rebuilds with the locale.
class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  static AppStrings of(BuildContext context) =>
      AppStrings(Localizations.localeOf(context));

  bool get isArabic => locale.languageCode == 'ar';

  Map<String, String> get _table => isArabic ? _ar : _en;

  String _get(String key) => _table[key] ?? _en[key] ?? key;

  /// Fills the single `%s` placeholder in [key]'s text.
  String _fill(String key, String value) => _get(key).replaceFirst('%s', value);

  // --- App ---------------------------------------------------------------
  String get appTitle => _get('appTitle');
  String get gotIt => _get('gotIt');
  String get copy => _get('copy');
  String get cancel => _get('cancel');

  // --- Game modes --------------------------------------------------------
  String get chooseGameMode => _get('chooseGameMode');
  String get playVsAI => _get('playVsAI');
  String get playVsAISubtitle => _get('playVsAISubtitle');
  String get playOnline => _get('playOnline');
  String get playOnlineSubtitle => _get('playOnlineSubtitle');
  String get twoPlayers => _get('twoPlayers');
  String get twoPlayersSubtitle => _get('twoPlayersSubtitle');

  // --- Status strip ------------------------------------------------------
  String get you => _get('you');
  String get ai => _get('ai');
  String get opponent => _get('opponent');
  String playerN(int n) => _fill('playerN', '$n');
  String get toPlay => _get('toPlay');
  String wallsCount(int n) => _fill('wallsCount', '$n');

  // --- Online ------------------------------------------------------------
  String get connecting => _get('connecting');
  String waitingForOpponentWithCode(String code) =>
      _fill('waitingForOpponentWithCode', code);
  String get waitingForOpponent => _get('waitingForOpponent');
  String hasGoneQuiet(String name) => _fill('hasGoneQuiet', name);
  String get lostContact => _get('lostContact');
  String get gameOverShort => _get('gameOverShort');
  String get yourTurn => _get('yourTurn');
  String isThinking(String name) => _fill('isThinking', name);
  String get onlineLobbyTitle => _get('onlineLobbyTitle');
  String get opponentSeesThisName => _get('opponentSeesThisName');
  String get startAGame => _get('startAGame');
  String get startAGameSubtitle => _get('startAGameSubtitle');
  String get createGame => _get('createGame');
  String get joinAGame => _get('joinAGame');
  String get codeHint => _get('codeHint');
  String get joinGame => _get('joinGame');
  String get gamesInProgress => _get('gamesInProgress');
  String versName(String name) => _fill('versName', name);
  String codeAndMoves(String code, int moves) =>
      _fill('codeAndMoves', code).replaceFirst('%m', '$moves');
  String get couldNotStart => _get('couldNotStart');
  String shareCodeToInvite(String code) => _fill('shareCodeToInvite', code);
  String get connectedGoodLuck => _get('connectedGoodLuck');
  String codeCopied(String code) => _fill('codeCopied', code);
  String get leftOnlineGame => _get('leftOnlineGame');
  String get leaveOnlineFirst => _get('leaveOnlineFirst');
  String get youWin => _get('youWin');
  String get opponentWins => _get('opponentWins');
  String get opponentMovedFirst => _get('opponentMovedFirst');

  // --- Online failures ---------------------------------------------------
  String get onlineUnavailable => _get('onlineUnavailable');
  String get gameNotFound => _get('gameNotFound');
  String get gameFull => _get('gameFull');
  String get alreadyJoined => _get('alreadyJoined');
  String get notYourTurn => _get('notYourTurn');
  String get backendError => _get('backendError');

  // --- Wall rejections ---------------------------------------------------
  String get wallOk => _get('wallOk');
  String get wallNoneLeft => _get('wallNoneLeft');
  String get wallOutOfBounds => _get('wallOutOfBounds');
  String get wallOverlaps => _get('wallOverlaps');
  String get wallCrosses => _get('wallCrosses');
  String get wallBlocksPlayer => _get('wallBlocksPlayer');

  // --- Drawer ------------------------------------------------------------
  String get gameControls => _get('gameControls');
  String get leaveOnlineGame => _get('leaveOnlineGame');
  String get leaveOnlineGameSubtitle => _get('leaveOnlineGameSubtitle');
  String get playOnlineSubtitleShort => _get('playOnlineSubtitleShort');
  String get newGame => _get('newGame');
  String get newGameSubtitle => _get('newGameSubtitle');
  String get saveGame => _get('saveGame');
  String get saveGameSubtitle => _get('saveGameSubtitle');
  String get togglePlayerMode => _get('togglePlayerMode');
  String get switchToTwoPlayers => _get('switchToTwoPlayers');
  String get switchToAI => _get('switchToAI');
  String get displayOptions => _get('displayOptions');
  String get showValidMoves => _get('showValidMoves');
  String get showValidMovesSubtitle => _get('showValidMovesSubtitle');
  String get darkMode => _get('darkMode');
  String get darkModeSubtitle => _get('darkModeSubtitle');
  String get soundEffects => _get('soundEffects');
  String get soundEffectsSubtitle => _get('soundEffectsSubtitle');
  String get soundUnavailable => _get('soundUnavailable');
  String get language => _get('language');
  String get languageSubtitle => _get('languageSubtitle');
  String get turnTimer => _get('turnTimer');
  String get turnTimerSubtitle => _get('turnTimerSubtitle');
  String get turnTimerOff => _get('turnTimerOff');
  String get turnTimerOffSubtitle => _get('turnTimerOffSubtitle');
  String turnTimerSeconds(int n) => _fill('turnTimerSeconds', '$n');
  String get turnTimerSecondsSubtitle => _get('turnTimerSecondsSubtitle');
  String get outOfTime => _get('outOfTime');

  String get aiDifficulty => _get('aiDifficulty');
  String get easy => _get('easy');
  String get easySubtitle => _get('easySubtitle');
  String get medium => _get('medium');
  String get mediumSubtitle => _get('mediumSubtitle');
  String get hard => _get('hard');
  String get hardSubtitle => _get('hardSubtitle');

  // --- Messages ----------------------------------------------------------
  String get newGameStarted => _get('newGameStarted');
  String get validMovesShown => _get('validMovesShown');
  String get validMovesHidden => _get('validMovesHidden');
  String get soundOn => _get('soundOn');
  String get soundOff => _get('soundOff');
  String difficultySetTo(String name) => _fill('difficultySetTo', name);
  String get switchedToAI => _get('switchedToAI');
  String get switchedToTwoPlayers => _get('switchedToTwoPlayers');
  String get aiModeActivated => _get('aiModeActivated');
  String get twoPlayerModeActivated => _get('twoPlayerModeActivated');
  String get signInToSave => _get('signInToSave');
  String get gameSaved => _get('gameSaved');
  String get gameSaveFailed => _get('gameSaveFailed');
  String get itsNotYourTurn => _get('itsNotYourTurn');
  String get invalidMove => _get('invalidMove');
  String get noWallsRemaining => _get('noWallsRemaining');
  String get invalidWallPlacement => _get('invalidWallPlacement');
  String get aiPlayedTheirMove => _get('aiPlayedTheirMove');

  // --- Game over ---------------------------------------------------------
  String get gameOverTitle => _get('gameOverTitle');
  String nameWins(String name) => _fill('nameWins', name);
  String get playAgainSuggestion => _get('playAgainSuggestion');
  String get notNow => _get('notNow');
  String get playAgain => _get('playAgain');

  // --- How to play -------------------------------------------------------
  String get howToPlay => _get('howToPlay');
  String get objective => _get('objective');
  String get objectiveBody => _get('objectiveBody');
  String get yourTurnSection => _get('yourTurnSection');
  String get yourTurnBody => _get('yourTurnBody');
  String get movement => _get('movement');
  String get movementBody => _get('movementBody');
  String get wallsSection => _get('wallsSection');
  String get wallsBody => _get('wallsBody');
  String get winning => _get('winning');
  String get winningBody => _get('winningBody');

  /// Exposed for the translation-parity test.
  static Map<String, String> get debugEnglish => _en;

  /// Exposed for the translation-parity test.
  static Map<String, String> get debugArabic => _ar;

  /// Exposed for the translation-parity test.
  static Set<String> get debugEnglishKeys => _en.keys.toSet();

  /// Exposed for the translation-parity test.
  static Set<String> get debugArabicKeys => _ar.keys.toSet();

  static const Map<String, String> _en = {
    'appTitle': 'Quoridor',
    'gotIt': 'Got it!',
    'copy': 'Copy',
    'cancel': 'Cancel',

    'chooseGameMode': 'Choose Game Mode',
    'playVsAI': 'Play vs AI',
    'playVsAISubtitle': 'Challenge our intelligent AI opponent',
    'playOnline': 'Play Online',
    'playOnlineSubtitle': 'Invite a friend with a code, or join theirs',
    'twoPlayers': 'Two Players',
    'twoPlayersSubtitle': 'Play with a friend on the same device',

    'you': 'You',
    'ai': 'AI',
    'opponent': 'Opponent',
    'playerN': 'Player %s',
    'toPlay': 'to play',
    'wallsCount': '%s walls',

    'connecting': 'Connecting…',
    'waitingForOpponentWithCode': 'Waiting for an opponent — code %s',
    'waitingForOpponent': 'Waiting for an opponent',
    'hasGoneQuiet': '%s has gone quiet',
    'lostContact': 'Lost contact with the game',
    'gameOverShort': 'Game over',
    'yourTurn': 'Your turn',
    'isThinking': '%s is thinking…',
    'onlineLobbyTitle': 'Play online',
    'opponentSeesThisName': 'Your opponent sees this name',
    'startAGame': 'Start a game',
    'startAGameSubtitle':
        'You get a six-character code. Share it and your friend joins.',
    'createGame': 'Create game',
    'joinAGame': 'Join a game',
    'codeHint': 'CODE',
    'joinGame': 'Join game',
    'gamesInProgress': 'Games in progress',
    'versName': 'vs %s',
    'codeAndMoves': 'Code %s · %m moves',
    'couldNotStart': 'Could not start the game',
    'shareCodeToInvite': 'Share code %s to invite a friend',
    'connectedGoodLuck': 'Connected — good luck',
    'codeCopied': 'Code %s copied',
    'leftOnlineGame': 'Left the online game',
    'leaveOnlineFirst': 'Leave the online game first',
    'youWin': 'You win!',
    'opponentWins': 'Your opponent wins',
    'opponentMovedFirst': 'Your opponent moved first',

    'onlineUnavailable': 'Online play is unavailable right now',
    'gameNotFound': 'No game found with that code',
    'gameFull': 'That game already has two players',
    'alreadyJoined': 'You are already in that game',
    'notYourTurn': 'It is not your turn',
    'backendError': 'Could not reach the game server',

    'wallOk': 'Wall can be placed here',
    'wallNoneLeft': 'You have no walls left',
    'wallOutOfBounds': 'Walls must sit between cells',
    'wallOverlaps': 'Another wall is already here',
    'wallCrosses': 'Walls cannot cross each other',
    'wallBlocksPlayer': 'This would leave a player with no way to their goal',

    'gameControls': 'Game Controls',
    'leaveOnlineGame': 'Leave Online Game',
    'leaveOnlineGameSubtitle': 'Return to playing on this device',
    'playOnlineSubtitleShort': 'Invite a friend with a code',
    'newGame': 'New Game',
    'newGameSubtitle': 'Start a fresh game',
    'saveGame': 'Save Game',
    'saveGameSubtitle': 'Save current progress',
    'togglePlayerMode': 'Toggle Player Mode',
    'switchToTwoPlayers': 'Switch to 2 players',
    'switchToAI': 'Switch to AI',
    'displayOptions': 'Display Options',
    'showValidMoves': 'Show Valid Moves',
    'showValidMovesSubtitle': 'Highlight possible moves',
    'darkMode': 'Dark Mode',
    'darkModeSubtitle': 'Toggle dark mode',
    'soundEffects': 'Sound Effects',
    'soundEffectsSubtitle': 'Move and wall sounds',
    'soundUnavailable': 'Unavailable on this device',
    'turnTimer': 'Turn Timer',
    'turnTimerSubtitle': 'How long each turn lasts',
    'turnTimerOff': 'No limit',
    'turnTimerOffSubtitle': 'Take as long as you like',
    'turnTimerSeconds': '%s seconds',
    'turnTimerSecondsSubtitle': 'A move is played for you if time runs out',
    'outOfTime': 'Out of time — a move was played for you',
    'language': 'Language',
    'languageSubtitle': 'العربية',
    'aiDifficulty': 'AI Difficulty',
    'easy': 'Easy',
    'easySubtitle': 'Looks one move ahead',
    'medium': 'Medium',
    'mediumSubtitle': 'Sees your reply',
    'hard': 'Hard',
    'hardSubtitle': 'Sets walls up in advance',

    'newGameStarted': 'New game started!',
    'validMovesShown': 'Valid moves shown',
    'validMovesHidden': 'Valid moves hidden',
    'soundOn': 'Sound on',
    'soundOff': 'Sound off',
    'difficultySetTo': 'Difficulty: %s',
    'switchedToAI': 'Switched to AI opponent',
    'switchedToTwoPlayers': 'Switched to human opponent',
    'aiModeActivated': 'Playing against AI',
    'twoPlayerModeActivated': 'Two player mode activated',
    'signInToSave': 'Please sign in to save game',
    'gameSaved': 'Game saved successfully!',
    'gameSaveFailed': 'Failed to save game',
    'itsNotYourTurn': "It's not your turn!",
    'invalidMove': 'Invalid move!',
    'noWallsRemaining': 'No walls remaining!',
    'invalidWallPlacement': 'Invalid wall placement!',
    'aiPlayedTheirMove': 'AI played their move',

    'gameOverTitle': 'Game Over!',
    'nameWins': '%s wins!',
    'playAgainSuggestion': 'Would you like to play again?',
    'notNow': 'Not Now',
    'playAgain': 'Play Again',

    'howToPlay': 'How to Play Quoridor',
    'objective': '🎯 Objective',
    'objectiveBody':
        'Be the first player to reach the opposite side of the board.',
    'yourTurnSection': '🎮 Your Turn',
    'yourTurnBody':
        'On each turn, either:\n• Move your pawn one space\n• Place a wall to block your opponent',
    'movement': '🚶 Movement',
    'movementBody':
        'Tap your pawn to pick it up. The squares you can reach are ringed in your colour — tap one to move there. You may jump over your opponent if they are in your way.',
    'wallsSection': '🧱 Walls',
    'wallsBody':
        'Each player has 10. Tap a gap between squares to line a wall up — it turns green if it can go there, red if it cannot. Tap the same spot again to place it. Aim slightly nearer the other gap to turn the wall.\n\nA wall may make your opponent\'s route longer, but never seal it off completely.',
    'winning': '🏆 Winning',
    'winningBody':
        'Player 1 (purple) starts at the bottom and wins by reaching the top row.\nPlayer 2 (teal) starts at the top and wins by reaching the bottom row.\n\nThe goal row of whoever is to play is tinted and flagged in their colour.',
  };

  /// Arabic. Carried over from the translation on the beta branches where the
  /// wording still applies, with the rest written for the screens as they are
  /// now. The old "winning" text was wrong in both languages — it had the goal
  /// rows the wrong way round — so it is corrected here.
  static const Map<String, String> _ar = {
    'appTitle': 'كوريدور',
    'gotIt': 'تمام',
    'copy': 'نسخ',
    'cancel': 'إلغاء',

    'chooseGameMode': 'اختر وضع اللعب',
    'playVsAI': 'ضد الكمبيوتر',
    'playVsAISubtitle': 'اتحدى خصم ذكي',
    'playOnline': 'لعب أونلاين',
    'playOnlineSubtitle': 'ادعُ صديقك بكود، أو ادخل بكوده',
    'twoPlayers': 'لاعبان',
    'twoPlayersSubtitle': 'العب مع صديق على نفس الجهاز',

    'you': 'أنت',
    'ai': 'الكمبيوتر',
    'opponent': 'الخصم',
    'playerN': 'اللاعب %s',
    'toPlay': 'دورك',
    'wallsCount': '%s حواجز',

    'connecting': 'جاري الاتصال…',
    'waitingForOpponentWithCode': 'في انتظار خصم — الكود %s',
    'waitingForOpponent': 'في انتظار خصم',
    'hasGoneQuiet': 'انقطع %s',
    'lostContact': 'انقطع الاتصال باللعبة',
    'gameOverShort': 'انتهت اللعبة',
    'yourTurn': 'دورك',
    'isThinking': '%s بيفكر…',
    'onlineLobbyTitle': 'لعب أونلاين',
    'opponentSeesThisName': 'خصمك هيشوف الاسم ده',
    'startAGame': 'ابدأ لعبة',
    'startAGameSubtitle': 'هتاخد كود من ٦ حروف. ابعته لصاحبك وهو يدخل بيه.',
    'createGame': 'إنشاء لعبة',
    'joinAGame': 'ادخل لعبة',
    'codeHint': 'الكود',
    'joinGame': 'دخول',
    'gamesInProgress': 'ألعاب جارية',
    'versName': 'ضد %s',
    'codeAndMoves': 'الكود %s · %m نقلة',
    'couldNotStart': 'تعذّر بدء اللعبة',
    'shareCodeToInvite': 'ابعت الكود %s لصاحبك',
    'connectedGoodLuck': 'اتصلنا — حظ موفق',
    'codeCopied': 'تم نسخ الكود %s',
    'leftOnlineGame': 'خرجت من اللعبة الأونلاين',
    'leaveOnlineFirst': 'اخرج من اللعبة الأونلاين الأول',
    'youWin': 'كسبت!',
    'opponentWins': 'خصمك كسب',
    'opponentMovedFirst': 'خصمك لعب قبلك',

    'onlineUnavailable': 'اللعب الأونلاين مش متاح دلوقتي',
    'gameNotFound': 'مفيش لعبة بالكود ده',
    'gameFull': 'اللعبة دي مكتملة بلاعبين',
    'alreadyJoined': 'إنت أصلاً في اللعبة دي',
    'notYourTurn': 'مش دورك',
    'backendError': 'تعذّر الوصول لخادم اللعبة',

    'wallOk': 'ينفع تحط الحاجز هنا',
    'wallNoneLeft': 'مفيش حواجز متبقية',
    'wallOutOfBounds': 'الحاجز لازم يكون بين المربعات',
    'wallOverlaps': 'فيه حاجز هنا بالفعل',
    'wallCrosses': 'الحواجز ماينفعش تتقاطع',
    'wallBlocksPlayer': 'ده هيقفل الطريق تماماً على لاعب',

    'gameControls': 'التحكم في اللعبة',
    'leaveOnlineGame': 'خروج من اللعبة الأونلاين',
    'leaveOnlineGameSubtitle': 'الرجوع للعب على الجهاز',
    'playOnlineSubtitleShort': 'ادعُ صديقك بكود',
    'newGame': 'لعبة جديدة',
    'newGameSubtitle': 'ابدأ من الأول',
    'saveGame': 'حفظ اللعبة',
    'saveGameSubtitle': 'احفظ التقدم الحالي',
    'togglePlayerMode': 'تبديل وضع اللاعب',
    'switchToTwoPlayers': 'التبديل للاعبين',
    'switchToAI': 'التبديل للكمبيوتر',
    'displayOptions': 'خيارات العرض',
    'showValidMoves': 'إظهار النقلات المتاحة',
    'showValidMovesSubtitle': 'تمييز المربعات اللي تقدر تروحها',
    'darkMode': 'الوضع الداكن',
    'darkModeSubtitle': 'تبديل الوضع الداكن',
    'soundEffects': 'المؤثرات الصوتية',
    'soundEffectsSubtitle': 'أصوات النقل والحواجز',
    'soundUnavailable': 'غير متاح على الجهاز ده',
    'turnTimer': 'مؤقت الدور',
    'turnTimerSubtitle': 'الدور الواحد بياخد قد إيه',
    'turnTimerOff': 'من غير وقت',
    'turnTimerOffSubtitle': 'خد وقتك زي ما تحب',
    'turnTimerSeconds': '%s ثانية',
    'turnTimerSecondsSubtitle': 'لو الوقت خلص هتتلعبلك نقلة',
    'outOfTime': 'الوقت خلص — اتلعبتلك نقلة',
    'language': 'اللغة',
    'languageSubtitle': 'English',
    'aiDifficulty': 'مستوى الكمبيوتر',
    'easy': 'سهل',
    'easySubtitle': 'بيشوف نقلة واحدة قدام',
    'medium': 'متوسط',
    'mediumSubtitle': 'بيحسب ردّك',
    'hard': 'صعب',
    'hardSubtitle': 'بيجهّز الحواجز بدري',

    'newGameStarted': 'بدأت لعبة جديدة',
    'validMovesShown': 'النقلات المتاحة ظاهرة',
    'validMovesHidden': 'النقلات المتاحة مخفية',
    'soundOn': 'الصوت شغال',
    'soundOff': 'الصوت مقفول',
    'difficultySetTo': 'المستوى: %s',
    'switchedToAI': 'اتحولت للعب ضد الكمبيوتر',
    'switchedToTwoPlayers': 'اتحولت للعب مع صديق',
    'aiModeActivated': 'اللعب ضد الكمبيوتر',
    'twoPlayerModeActivated': 'وضع اللاعبين اتفعّل',
    'signInToSave': 'سجّل الدخول عشان تحفظ اللعبة',
    'gameSaved': 'تم حفظ اللعبة',
    'gameSaveFailed': 'فشل حفظ اللعبة',
    'itsNotYourTurn': 'مش دورك!',
    'invalidMove': 'نقلة غير متاحة!',
    'noWallsRemaining': 'مفيش حواجز متبقية!',
    'invalidWallPlacement': 'مكان الحاجز غير متاح!',
    'aiPlayedTheirMove': 'الكمبيوتر لعب',

    'gameOverTitle': 'انتهت اللعبة!',
    'nameWins': '%s كسب!',
    'playAgainSuggestion': 'تحب تلعب تاني؟',
    'notNow': 'مش دلوقتي',
    'playAgain': 'العب تاني',

    'howToPlay': 'إزاي تلعب كوريدور',
    'objective': '🎯 الهدف',
    'objectiveBody': 'كن أول من يصل للجهة المقابلة من اللوحة.',
    'yourTurnSection': '🎮 دورك',
    'yourTurnBody':
        'كل دور، تختار واحدة من اتنين:\n• تحرّك بيدقك مربع واحد\n• تحط حاجز يعطّل خصمك',
    'movement': '🚶 الحركة',
    'movementBody':
        'دوس على بيدقك عشان تشيله. المربعات اللي تقدر توصلها هتتحوّط بلونك — دوس على واحد منها عشان تروح. وتقدر تقفز فوق خصمك لو واقف في طريقك.',
    'wallsSection': '🧱 الحواجز',
    'wallsBody':
        'كل لاعب معاه ١٠. دوس على المسافة بين مربعين عشان تصوّب الحاجز — هيبقى أخضر لو ينفع، وأحمر لو مش ينفع. دوس في نفس المكان تاني عشان تحطه. صوّب أقرب شوية للمسافة التانية عشان تلف الحاجز.\n\nالحاجز ممكن يطوّل طريق خصمك، بس عمره ما يقفله تماماً.',
    'winning': '🏆 الفوز',
    'winningBody':
        'اللاعب ١ (البنفسجي) بيبدأ من تحت وبيكسب لما يوصل الصف العلوي.\nاللاعب ٢ (الفيروزي) بيبدأ من فوق وبيكسب لما يوصل الصف السفلي.\n\nصف هدف اللي عليه الدور بيبقى ملوّن وعليه أعلام بلونه.',
  };
}

extension WallRejectionText on AppStrings {
  /// The player-facing reason a wall was refused.
  String wallRejection(WallRejection rejection) {
    switch (rejection) {
      case WallRejection.none:
        return wallOk;
      case WallRejection.noWallsLeft:
        return wallNoneLeft;
      case WallRejection.outOfBounds:
        return wallOutOfBounds;
      case WallRejection.overlaps:
        return wallOverlaps;
      case WallRejection.crosses:
        return wallCrosses;
      case WallRejection.blocksPlayer:
        return wallBlocksPlayer;
    }
  }

  /// The player-facing reason an online action did not go through.
  String onlineFailure(OnlineFailure failure) {
    switch (failure) {
      case OnlineFailure.unavailable:
        return onlineUnavailable;
      case OnlineFailure.gameNotFound:
        return gameNotFound;
      case OnlineFailure.gameFull:
        return gameFull;
      case OnlineFailure.alreadyJoined:
        return alreadyJoined;
      case OnlineFailure.notYourTurn:
        return notYourTurn;
      case OnlineFailure.staleMove:
        return opponentMovedFirst;
      case OnlineFailure.illegalMove:
        return invalidMove;
      case OnlineFailure.backendError:
        return backendError;
    }
  }
}

/// `context.l10n.playOnline` reads better at the call site than passing the
/// table around.
extension AppStringsX on BuildContext {
  AppStrings get l10n => AppStrings.of(this);
}

/// Text direction for the current setting, for anything built outside a
/// [Localizations] scope.
TextDirection get currentTextDirection =>
    SettingsService.instance.isArabic ? TextDirection.rtl : TextDirection.ltr;
