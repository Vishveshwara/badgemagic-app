import 'package:badgemagic/badge_animation/animation_abstract.dart';

class LinearScrollAnimation extends BadgeAnimation {
  @override
  void processAnimation(int badgeHeight, int badgeWidth, int animationIndex,
      List<List<bool>> processGrid, List<List<bool>> canvas) {
    final newWidth = processGrid[0].length;
    final newHeight = processGrid.length;

    // Calculate the full animation cycle duration
    final totalPhaseDuration = newWidth + badgeWidth;

    // Determine current phase (0 = left-to-right, 1 = right-to-left)
    final currentPhase = (animationIndex ~/ totalPhaseDuration) % 2;

    // Calculate offset within current phase
    final phaseOffset = animationIndex % totalPhaseDuration;

    for (int i = 0; i < badgeHeight; i++) {
      for (int j = 0; j < badgeWidth; j++) {
        int sourceCol;

        if (currentPhase == 0) {
          // Left-to-right animation
          sourceCol = newWidth - phaseOffset + j;
        } else {
          // Right-to-left animation
          sourceCol = j + phaseOffset - badgeWidth;
        }

        // Handle bounds checking
        if (sourceCol >= 0 && sourceCol < newWidth) {
          canvas[i][j] = processGrid[i % newHeight][sourceCol];
        } else {
          canvas[i][j] = false;
        }
      }
    }
  }
}
