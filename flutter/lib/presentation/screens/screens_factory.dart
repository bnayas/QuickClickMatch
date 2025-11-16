import 'package:flutter/foundation.dart' show kIsWeb;
import 'game_screen.dart';
import 'platforms/mobile/mobile_game_screen.dart';

class ScreenFactory {
  static GameScreenState createGameScreenState() {
    if (kIsWeb) {
      return createMobileGameScreenState();
    } else {
      return createMobileGameScreenState();
    }
  }
}
