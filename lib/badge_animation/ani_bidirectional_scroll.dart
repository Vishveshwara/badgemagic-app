import 'package:badgemagic/badge_animation/animation_abstract.dart';

class BidirectionalScrollAnimation extends BadgeAnimation {
  @override
  void processAnimation(int badgeHeight, int badgeWidth, int animationIndex,
      List<List<bool>> processGrid, List<List<bool>> canvas) {
    final newWidth = processGrid[0].length;
    final newHeight = processGrid.length;

    final totalPhaseDuration = newWidth + badgeWidth;
    final currentPhase = (animationIndex ~/ totalPhaseDuration) % 2;
    final phaseOffset = animationIndex % totalPhaseDuration;

    for (int i = 0; i < badgeHeight; i++) {
      for (int j = 0; j < badgeWidth; j++) {
        int sourceCol;
        bool flip = false;

        if (currentPhase == 0) {
          // Left-to-right animation (original orientation)
          sourceCol = newWidth - phaseOffset + j;
        } else {
          // Right-to-left animation (flipped orientation)
          sourceCol = j + phaseOffset - badgeWidth;
          flip = true;
        }

        if (sourceCol >= 0 && sourceCol < newWidth) {
          // Flip the column index if in return phase
          final actualCol = flip ? newWidth - 1 - sourceCol : sourceCol;
          canvas[i][j] = processGrid[i % newHeight][actualCol];
        } else {
          canvas[i][j] = false;
        }
      }
    }
  }
}
