import 'constants.dart';

class GameBoardDimensions {
  final double screenHeight;
  final double screenWidth;

  GameBoardDimensions({required this.screenHeight, required this.screenWidth});

  bool get isWideScreen => screenWidth > 700;

  double calculateCellSize() {
    final totalSpacing =
        (GameConstants.boardSize - 1) * GameConstants.cellSpacing;
    final totalPadding = GameConstants.boardPadding * 2;

    // Define breakpoints for different screen sizes
    final isWideScreen = screenWidth > 700;
    final isExtraWideScreen = screenWidth > 1200;

    // Calculate available width based on screen size
    double availableWidth;
    if (isExtraWideScreen) {
      // For extra wide screens, reserve more space for the sidebar
      availableWidth = screenWidth - totalPadding - totalSpacing - 400;
    } else if (isWideScreen) {
      // For wide screens, reserve some space for the sidebar
      availableWidth = screenWidth - totalPadding - totalSpacing - 300;
    } else {
      // For mobile/tablet, use full width minus padding
      availableWidth = screenWidth - totalPadding - totalSpacing;
    }

    // Calculate available height
    // Reserve space for app bar, player info (if not in sidebar), and message toast
    final appBarHeight = 64.0; // Standard app bar height
    final playerInfoHeight = isWideScreen
        ? 0.0
        : 100.0; // Height of player info when at bottom
    final messageToastHeight = 60.0; // Height for message toast
    final bottomPadding = 20.0; // Additional bottom padding
    final availableHeight =
        screenHeight -
        appBarHeight -
        playerInfoHeight -
        messageToastHeight -
        bottomPadding;

    // Calculate cell size based on both width and height
    final widthBasedCellSize = availableWidth / GameConstants.boardSize;
    final heightBasedCellSize = availableHeight / GameConstants.boardSize;

    // Use the smaller of the two to ensure the board fits both dimensions
    final rawCellSize = widthBasedCellSize < heightBasedCellSize
        ? widthBasedCellSize
        : heightBasedCellSize;

    // Apply minimum and maximum constraints
    final minCellSize = 30.0; // Minimum cell size for playability
    final maxCellSize = 60.0; // Maximum cell size for aesthetics
    final cellSize = rawCellSize.clamp(minCellSize, maxCellSize);
    return cellSize;
  } // 9 rows in the game board
}
