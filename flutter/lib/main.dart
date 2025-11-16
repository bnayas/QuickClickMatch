import 'package:flutter/material.dart';
import 'package:quick_click_match/app.dart';
import 'package:quick_click_match/default_deck_import.dart';
import 'package:quick_click_match/services/sound_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ensureDefaultDecksExist();
  await SoundService.instance.initialize();
  runApp(const App());
}
