import 'package:flutter_localization/flutter_localization.dart';

final FlutterLocalization localization = FlutterLocalization.instance;

mixin AppLocale {
  /// keys
  static const String title = 'title';
  static const String gameOver = 'gameOver';
  static const String wins = 'wins';
  static const String playAgainSuggestion = 'playAgainSuggestion';
  static const String notNow = 'notNow';
  static const String playAgain = 'playAgain';
  static const String howToPlay = 'howToPlay';
  static const String objective = 'objective';
  static const String objectiveDescription = 'objectiveDescription';
  static const String yourTurn = 'yourTurn';
  static const String yourTurnDescription = 'yourTurnDescription';
  static const String movement = 'movement';
  static const String movementDescription = 'movementDescription';
  static const String walls = 'walls';
  static const String wallsDescription = 'wallsDescription';
  static const String winning = 'winning';
  static const String winningDescription = 'winningDescription';
  static const String gotIt = 'gotIt';
  static const String chooseGameMode = 'chooseGameMode';
  static const String playVsAI = 'playVsAI';
  static const String challengeOurIntelligentAIOpponent =
      'challengeOurIntelligentAIOpponent';
  static const String twoPlayers = 'twoPlayers';
  static const String playWithAFriendOnTheSameDevice =
      'playWithAFriendOnTheSameDevice';
  static const String wallsLeft = 'wallsLeft';
  static const String player1 = 'player1';
  static const String player2 = 'player2';
  static const String vertical = 'vertical';
  static const String horizontal = 'horizontal';
  static const String aiDifficulty = 'aiDifficulty';
  static const String easy = 'easy';
  static const String medium = 'medium';
  static const String hard = 'hard';
  static const String easyDescription = 'easyDescription';
  static const String mediumDescription = 'mediumDescription';
  static const String hardDescription = 'hardDescription';
  static const String displayOptions = 'displayOptions';
  static const String showValidMoves = 'showValidMoves';
  static const String highlightPossibleMoves = 'highlightPossibleMoves';
  static const String soundEnabled = 'soundEnabled';
  static const String soundEnabledSubtitles = 'soundEnabledSubtitles';
  static const String darkMode = 'darkMode';
  static const String toggleDarkMode = 'toggleDarkMode';
  static const String englishMode = 'englishMode';
  static const String toggleLanguageMode = 'toggleLanguageMode';
  static const String gameControls = 'gameControls';
  static const String newGame = 'newGame';
  static const String startAFreshGame = 'startAFreshGame';
  static const String saveGame = 'saveGame';
  static const String saveCurrentProgress = 'saveCurrentProgress';
  static const String togglePlayerMode = 'togglePlayerMode';
  static const String switchToTwoPlayers = 'switchToTwoPlayers';
  static const String switchToAI = 'switchToAI';
  static const String pleaseLogInToSaveGame = 'pleaseLogInToSaveGame';
  static const String gameSavedSuccessfullyWithId =
      'gameSavedSuccessfullyWithId';
  static const String failedToSaveGame = 'failedToSaveGame';

  static const String gameStateNotInitialized = 'gameStateNotInitialized';
  static const String pleaseWait = 'pleaseWait';
  static const String difficultySetTo = 'difficultySetTo';
  static const String validMovesHighlighted = 'validMovesHighlighted';
  static const String validMovesHidden = 'validMovesHidden';
  static const String switchedToAI = 'switchedToAI';
  static const String switchedToTwoPlayers = 'switchedToTwoPlayers';
  static const String aiPlayedTheirMove = 'aiPlayedTheirMove';
  static const String itsNotYourTurn = 'itsNotYourTurn';
  static const String invalidMove = 'invalidMove';
  static const String noWallsRemaining = 'noWallsRemaining';
  static const String invalidWallPlacement = 'invalidWallPlacement';
  static const String moveFailed = 'moveFailed';
  static const String newGameStarted = 'newGameStarted';
  static const String aiModeActivated = 'aiModeActivated';
  static const String twoPlayerModeActivated = 'twoPlayerModeActivated';

  /// English locale
  static const Map<String, dynamic> en = {
    title: 'Quoridor - Strategic Board Game',
    gameOver: 'Game Over!',
    wins: 'wins!',
    notNow: 'Not Now',
    playAgainSuggestion: 'Would you like to play again?',
    playAgain: 'Play Again',
    howToPlay: 'How to Play Quoridor',
    objective: 'Objective',
    objectiveDescription:
        'Be the first player to reach the opposite side of the board.',
    yourTurn: 'Your Turn',
    yourTurnDescription:
        'On each turn, either:\n• Move your pawn one space\n• Place a wall to block your opponent',
    movement: 'Movement',
    movementDescription:
        'Move up, down, left, or right. Jump over your opponent if they\'re in your way.',
    walls: 'Walls',
    wallsDescription:
        'Each player has 10 walls. Place them strategically but don\'t completely block your opponent\'s path.',
    winning: 'Winning',
    winningDescription:
        'Player 1 (purple) wins by reaching the bottom row.\nPlayer 2 (teal) wins by reaching the top row.',
    chooseGameMode: 'Choose Game Mode',
    playVsAI: 'Play vs AI',
    challengeOurIntelligentAIOpponent: 'Challenge our intelligent AI opponent',
    twoPlayers: 'Two Players',
    playWithAFriendOnTheSameDevice: 'Play with a friend on the same device',
    wallsLeft: 'walls left',
    player1: 'Player 1',
    player2: 'Player 2',
    vertical: 'Vertical',
    aiDifficulty: 'AI Difficulty',
    horizontal: 'Horizontal',
    easy: 'Easy',
    medium: 'Medium',
    hard: 'Hard',
    easyDescription: 'Beginner-friendly AI',
    mediumDescription: 'Balanced challenge',
    hardDescription: 'Expert-level AI',
    displayOptions: 'Display Options',
    showValidMoves: 'Show Valid Moves',
    highlightPossibleMoves: 'Highlight possible moves',
    soundEnabled: 'Sound Enabled',
    soundEnabledSubtitles: 'Enable sound effects in the game',
    darkMode: 'Dark Mode',
    toggleDarkMode: 'Toggle dark mode',
    englishMode: 'English Mode',
    toggleLanguageMode: 'Toggle language mode',
    gameControls: 'Game Controls',
    newGame: 'New Game',
    startAFreshGame: 'Start a fresh game',
    saveGame: 'Save Game',
    saveCurrentProgress: 'Save current progress',
    togglePlayerMode: 'Toggle Player Mode',
    switchToTwoPlayers: 'Switch to 2 players',
    switchToAI: 'Switch to AI',
    pleaseLogInToSaveGame: 'Please log in to save the game',
    gameSavedSuccessfullyWithId: 'Game saved successfully with ID: %a',
    failedToSaveGame: 'Failed to save game. Please try again.',
    gotIt: 'Got it!',
    gameStateNotInitialized:
        'Game state has not been initialized yet. Please wait for the game to load.',
    pleaseWait: 'Please wait',
    difficultySetTo: 'Difficulty set to %a',
    validMovesHighlighted: 'Valid moves highlighted',
    validMovesHidden: 'Valid moves hidden',
    switchedToAI: 'Switched to AI opponent',
    switchedToTwoPlayers: 'Switched to human opponent',
    aiPlayedTheirMove: 'AI played their move',
    itsNotYourTurn: 'It\'s not your turn!',
    invalidMove: 'Invalid move!',
    noWallsRemaining: 'No walls remaining!',
    invalidWallPlacement: 'Invalid wall placement!',
    moveFailed: 'Move failed: %a',
    newGameStarted: 'New game started!',
    aiModeActivated: 'AI mode activated',
    twoPlayerModeActivated: 'Two player mode activated',
  };

  /// Arabic locale
  static const Map<String, dynamic> ar = {
    title: 'كوريدور - لعبة استراتيجية',
    gameOver: 'لقد فاز اللاعب',
    wins: 'لقد فاز اللاعب',
    notNow: 'لا الآن',
    playAgainSuggestion: 'هل تريد العب مرة أخرى؟',
    playAgain: 'العب مرة أخرى',
    howToPlay: 'كيفية اللعب في كوريدور',
    objective: 'الهدف',
    objectiveDescription: 'كون اللاعب الأول للوصول إلى الجانب المقابل لللوحة.',
    yourTurn: 'لعبك',
    yourTurnDescription:
        'في كل لعبة، يمكنك إما:\n• التحرك بمسافة واحدة\n• وضع حاجز لمنع اللاعب الآخر',
    movement: 'التحرك',
    movementDescription:
        'التحرك لأعلى، أسفل، يسار أو يمين. أو أن تقفز للأعلى أو الأسفل أو اليسار أو اليمين إذا كان هناك حاجز في الطريق.',
    walls: 'الحواجز',
    wallsDescription:
        'يحتوي كل لاعب على 10 حواجز. وضعها بشكل مستراتيجي ولكن لا تقم بحظر الطريق بالكامل.',
    winning: 'الفوز',
    winningDescription:
        'اللاعب 1 (البنفسجي) يفوز بالوصول إلى الصف السفلي.\nاللاعب 2 (الأزرق) يفوز بالوصول إلى الصف العلوي.',
    chooseGameMode: 'اختر وضع اللعبة',
    playVsAI: 'العب ضد الذكاء الصنعي',
    challengeOurIntelligentAIOpponent: 'تحدي الذكاء الصناعي الذي يتمتع بالذكاء',
    twoPlayers: 'لاعبان',
    playWithAFriendOnTheSameDevice: 'العب مع صديق على نفس الجهاز',
    wallsLeft: 'الحواجز المتبقية',
    player1: 'اللاعب 1',
    player2: 'اللاعب 2',
    vertical: 'عمودي',
    aiDifficulty: 'صعوبة الذكاء الصناعي',
    horizontal: 'أفقي',
    easy: 'سهل',
    medium: 'متوسط',
    hard: 'صعب',
    easyDescription: 'ذكاء صناعي سهل',
    mediumDescription: 'تحدي متوازن',
    hardDescription: 'ذكاء صناعي متقدم',
    displayOptions: 'خيارات العرض',
    showValidMoves: 'اظهار الحركات الممكنة',
    highlightPossibleMoves: 'تمييز الحركات الممكنة',
    soundEnabled: 'الصوت مفعل',
    soundEnabledSubtitles: 'تفعيل الصوت في اللعبة',
    darkMode: 'الوضع الداكن',
    toggleDarkMode: 'تبديل الوضع الداكن',
    englishMode: 'الوضع الانجليزي',
    toggleLanguageMode: 'تبديل اللغة',
    gameControls: 'تحكم في اللعبة',
    newGame: 'لعبة جديدة',
    startAFreshGame: 'لعبة جديدة',
    saveGame: 'حفظ اللعبة',
    saveCurrentProgress: 'حفظ اللعبة الحالية',
    togglePlayerMode: 'تبديل وضع اللاعب',
    switchToTwoPlayers: 'تبديل إلى 2 لاعب',
    switchToAI: 'تبديل إلى الذكاء الصناعي',
    pleaseLogInToSaveGame: 'يرجى تسجيل الدخول لحفظ اللعبة',
    gameSavedSuccessfullyWithId: 'تم حفظ اللعبة بنجاح بالمعرف: %a',
    failedToSaveGame: 'فشل حفظ اللعبة. يرجى المحاولة مرة أخرى.',
    gotIt: 'حسنا!',
    gameStateNotInitialized:
        'لم يتم تهيئة الحالة اللعبية بعد. يرجى الإنتظار حتى يتم تحميل اللعبة.',
    pleaseWait: 'يرجى الإنتظار',
    difficultySetTo: 'تم تعيين الصعوبة إلى %a',
    validMovesHighlighted: 'تمييز الحركات الممكنة',
    validMovesHidden: 'تم إخفاء الحركات الممكنة',
    switchedToAI: 'تم التبديل إلى الذكاء الصناعي',
    switchedToTwoPlayers: 'تم التبديل إلى لاعبين',
    aiPlayedTheirMove: 'تمت إعادة اللعب من قبل الذكاء الصناعي',
    itsNotYourTurn: 'ليس وقتك للعب!',
    invalidMove: 'حركة غير متاحة!',
    noWallsRemaining: 'لا توجد حواجز متبقية!',
    invalidWallPlacement: 'وضع الحاجز غير متاح!',
    moveFailed: 'فشل الحركة: %a',
    newGameStarted: 'تم بدء اللعبة الجديدة!',
    aiModeActivated: 'تم تفعيل وضع الذكاء الصناعي',
    twoPlayerModeActivated: 'تم تفعيل وضع اللاعبين',
  };
}
