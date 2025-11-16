import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AmbientTrack { menu, game }

class SoundService extends ChangeNotifier {
  SoundService._internal();

  static final SoundService _instance = SoundService._internal();
  static SoundService get instance => _instance;

  static const _prefsVolume = 'sound.volume';
  static const _prefsEffects = 'sound.effects.enabled';
  static const _prefsAmbient = 'sound.music.enabled';

  final AudioPlayer _ambientPlayer = AudioPlayer(playerId: 'ambient');

  double _effectsVolume = 0.7;
  bool _effectsEnabled = true;
  bool _ambientEnabled = true;
  AmbientTrack? _currentAmbientTrack;
  bool _isInitialized = false;

  double get effectsVolume => _effectsVolume;
  bool get effectsEnabled => _effectsEnabled;
  bool get ambientEnabled => _ambientEnabled;
  bool get isInitialized => _isInitialized;
  double get _ambientVolume => (_effectsVolume * 0.6).clamp(0.0, 1.0);
  bool get _canPlayAmbient => _ambientEnabled;

  Future<void> initialize() async {
    if (_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    _effectsVolume = prefs.getDouble(_prefsVolume) ?? 0.7;
    _effectsEnabled = prefs.getBool(_prefsEffects) ?? true;
    _ambientEnabled = prefs.getBool(_prefsAmbient) ?? true;
    await _ambientPlayer.setReleaseMode(ReleaseMode.stop);
    await _ambientPlayer.setVolume(_ambientVolume);
    _currentAmbientTrack ??= AmbientTrack.menu;
    _isInitialized = true;
    await _startAmbientTrack();
    notifyListeners();
  }

  Future<void> setEffectsVolume(double value) async {
    _ensureInitialized();
    _effectsVolume = value.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefsVolume, _effectsVolume);
    await _updateAmbientVolume();
    notifyListeners();
  }

  Future<void> setEffectsEnabled(bool value) async {
    _ensureInitialized();
    if (_effectsEnabled == value) return;
    _effectsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEffects, _effectsEnabled);
    notifyListeners();
  }

  Future<void> setAmbientEnabled(bool value) async {
    _ensureInitialized();
    if (_ambientEnabled == value) return;
    _ambientEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAmbient, _ambientEnabled);
    if (!value) {
      await _ambientPlayer.stop();
    } else {
      await _startAmbientTrack();
    }
    notifyListeners();
  }

  Future<void> playAmbient(AmbientTrack track) async {
    _ensureInitialized();
    _currentAmbientTrack = track;
    if (!_canPlayAmbient) {
      await _ambientPlayer.stop();
      return;
    }
    await _startAmbientTrack();
  }

  Future<void> stopAmbient() async {
    await _ambientPlayer.stop();
    await _ambientPlayer.release();
    _currentAmbientTrack = null;
  }

  Future<void> playCardFlip() => _playEffect('audio/card_flip.webm');
  Future<void> playSuccess() => _playEffect('audio/match_success.webm');
  Future<void> playMismatch() => _playEffect('audio/mismatch.webm');
  Future<void> playTap() => _playEffect('audio/card_flip.webm');

  Future<void> _playEffect(String assetPath) async {
    _ensureInitialized();
    if (!_effectsEnabled) return;
    final player = AudioPlayer();
    unawaited(player.play(AssetSource(assetPath), volume: _effectsVolume));
    player.onPlayerComplete.first.then((_) => player.dispose());
  }

  void _ensureInitialized() {
    assert(
        _isInitialized, 'SoundService.initialize must be awaited before use');
  }

  Future<void> _startAmbientTrack() async {
    final track = _currentAmbientTrack;
    if (track == null || !_canPlayAmbient) return;

    final source = switch (track) {
      AmbientTrack.menu => AssetSource('audio/ambient_loop.webm'),
      AmbientTrack.game => AssetSource('audio/ambient_loop.webm'),
    };

    await _ambientPlayer.stop();
    await _ambientPlayer.setReleaseMode(ReleaseMode.loop);
    await _ambientPlayer.setVolume(_ambientVolume);
    await _ambientPlayer.play(source);
  }

  Future<void> _updateAmbientVolume() async {
    if (_currentAmbientTrack == null) return;
    await _ambientPlayer.setVolume(_ambientVolume);
  }
}
