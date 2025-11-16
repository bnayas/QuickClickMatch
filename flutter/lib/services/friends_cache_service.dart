import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:quick_click_match/utils/debug_logger.dart';
import 'package:quick_click_match/utils/user_identity.dart';

typedef DocumentsDirectoryProvider = Future<Directory> Function();

class Friend {
  final String userId;
  final String userName;
  final DateTime addedAt;
  final bool isBlocked;
  final DateTime? lastSeen; // Track when friend was last seen online

  Friend({
    required this.userId,
    required this.userName,
    required this.addedAt,
    this.isBlocked = false,
    this.lastSeen,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      userId: json['userId'],
      userName: json['userName'],
      addedAt: DateTime.parse(json['addedAt']),
      isBlocked: json['isBlocked'] ?? false,
      lastSeen:
          json['lastSeen'] != null ? DateTime.parse(json['lastSeen']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'addedAt': addedAt.toIso8601String(),
      'isBlocked': isBlocked,
      'lastSeen': lastSeen?.toIso8601String(),
    };
  }

  Friend copyWith({
    String? userId,
    String? userName,
    DateTime? addedAt,
    bool? isBlocked,
    DateTime? lastSeen,
  }) {
    return Friend(
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      addedAt: addedAt ?? this.addedAt,
      isBlocked: isBlocked ?? this.isBlocked,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  // Helper to check if friend was seen recently (within last 24 hours)
  bool get wasRecentlyOnline {
    if (lastSeen == null) return false;
    final now = DateTime.now();
    final difference = now.difference(lastSeen!);
    return difference.inHours < 24;
  }
}

class FriendsCacheService {
  static const String _filePrefix = 'friends_cache';
  String? _currentUsername;
  static FriendsCacheService? _instance;

  List<Friend> _friends = [];
  File? _cacheFile;
  bool _isInitialized = false;
  DocumentsDirectoryProvider? _documentsDirectoryProvider;

  // Singleton pattern
  factory FriendsCacheService() {
    _instance ??= FriendsCacheService._internal();
    return _instance!;
  }

  @visibleForTesting
  static FriendsCacheService createForTest() {
    return FriendsCacheService._internal();
  }

  FriendsCacheService._internal();

  List<Friend> get friends => List.unmodifiable(_friends);
  List<Friend> get activeFriends =>
      _friends.where((f) => !f.isBlocked).toList();
  List<Friend> get blockedFriends =>
      _friends.where((f) => f.isBlocked).toList();
  List<Friend> get recentlyOnlineFriends =>
      activeFriends.where((f) => f.wasRecentlyOnline).toList();

  @visibleForTesting
  void setDocumentsDirectoryProvider(
      DocumentsDirectoryProvider? provider) {
    _documentsDirectoryProvider = provider;
  }

  Future<void> initialize(String dispalyName) async {
    if (_isInitialized && _currentUsername == dispalyName) return;
    _currentUsername = dispalyName;
    try {
      final directory = await (_documentsDirectoryProvider?.call() ??
          getApplicationDocumentsDirectory());
      _cacheFile =
          File('${directory.path}/${_filePrefix}_${dispalyName} .json');
      await _loadFromFile();
      _isInitialized = true;
      debugLog(
          'FriendsCacheService initialized with ${_friends.length} friends');
    } catch (e) {
      debugLog('Error initializing friends cache: $e');
      _isInitialized = true; // Mark as initialized even if loading failed
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize(_currentUsername ?? 'username');
    }
  }

  Future<void> _loadFromFile() async {
    if (_cacheFile == null || !await _cacheFile!.exists()) {
      debugLog('Friends cache file does not exist, starting with empty list');
      return;
    }

    try {
      final content = await _cacheFile!.readAsString();
      if (content.trim().isEmpty) {
        debugLog('Friends cache file is empty');
        return;
      }

      final List<dynamic> jsonList = json.decode(content);
      _friends = jsonList
          .map((json) => Friend.fromJson(json as Map<String, dynamic>))
          .toList();
      debugLog('Loaded ${_friends.length} friends from cache');
    } catch (e) {
      debugLog('Error loading friends from cache: $e');
      _friends = [];
    }
  }

  Future<bool> _saveToFile() async {
    await _ensureInitialized();

    if (_cacheFile == null) {
      debugLog('Cache file not initialized');
      return false;
    }

    try {
      final jsonList = _friends.map((friend) => friend.toJson()).toList();
      await _cacheFile!.writeAsString(json.encode(jsonList));
      debugLog('Saved ${_friends.length} friends to cache');
      return true;
    } catch (e) {
      debugLog('Error saving friends to cache: $e');
      return false;
    }
  }

  Future<bool> addFriend(String userId, String userName) async {
    await _ensureInitialized();

    if (!UserIdentityUtils.isRegisteredUserId(userId)) {
      debugLog('Skipping friend $userId - temporary IDs are not persisted');
      return false;
    }

    if (hasFriend(userId)) {
      debugLog('Friend $userId already exists');
      return false; // Friend already exists
    }

    final existingByNameIndex = _friends.indexWhere(
        (friend) => friend.userName.toLowerCase() == userName.toLowerCase());
    if (existingByNameIndex != -1) {
      final existing = _friends[existingByNameIndex];
      if (existing.userId != userId) {
        _friends[existingByNameIndex] = existing.copyWith(
          userId: userId,
          addedAt: DateTime.now(),
        );
        final success = await _saveToFile();
        if (success) {
          debugLog(
              'Updated friend ID for $userName from ${existing.userId} to $userId');
        }
        return success;
      } else {
        debugLog('Friend $userName ($userId) already up to date');
        return false;
      }
    }

    final friend = Friend(
      userId: userId,
      userName: userName,
      addedAt: DateTime.now(),
    );

    _friends.add(friend);
    final success = await _saveToFile();

    if (success) {
      debugLog('Added friend: $userName ($userId)');
    }

    return success;
  }

  Future<bool> removeFriend(String userId) async {
    await _ensureInitialized();

    final initialCount = _friends.length;
    _friends.removeWhere((friend) => friend.userId == userId);

    if (_friends.length < initialCount) {
      final success = await _saveToFile();
      if (success) {
        debugLog('Removed friend: $userId');
      }
      return success;
    }

    debugLog('Friend $userId not found for removal');
    return false;
  }

  Future<bool> blockFriend(String userId) async {
    await _ensureInitialized();

    final index = _friends.indexWhere((friend) => friend.userId == userId);
    if (index != -1) {
      _friends[index] = _friends[index].copyWith(isBlocked: true);
      final success = await _saveToFile();
      if (success) {
        debugLog('Blocked friend: $userId');
      }
      return success;
    }

    debugLog('Friend $userId not found for blocking');
    return false;
  }

  Future<bool> unblockFriend(String userId) async {
    await _ensureInitialized();

    final index = _friends.indexWhere((friend) => friend.userId == userId);
    if (index != -1) {
      _friends[index] = _friends[index].copyWith(isBlocked: false);
      final success = await _saveToFile();
      if (success) {
        debugLog('Unblocked friend: $userId');
      }
      return success;
    }

    debugLog('Friend $userId not found for unblocking');
    return false;
  }

  bool hasFriend(String userId) {
    return _friends.any((friend) => friend.userId == userId);
  }

  bool isFriendBlocked(String userId) {
    final friend = _friends.where((f) => f.userId == userId).firstOrNull;
    return friend?.isBlocked ?? false;
  }

  Friend? getFriend(String userId) {
    try {
      return _friends.firstWhere((friend) => friend.userId == userId);
    } catch (e) {
      return null;
    }
  }

  Future<bool> updateFriendName(String userId, String newName) async {
    await _ensureInitialized();

    final index = _friends.indexWhere((friend) => friend.userId == userId);
    if (index != -1) {
      _friends[index] = _friends[index].copyWith(userName: newName);
      final success = await _saveToFile();
      if (success) {
        debugLog('Updated friend name: $userId -> $newName');
      }
      return success;
    }

    debugLog('Friend $userId not found for name update');
    return false;
  }

  Future<bool> updateFriendLastSeen(String userId, DateTime? lastSeen) async {
    await _ensureInitialized();

    final index = _friends.indexWhere((friend) => friend.userId == userId);
    if (index != -1) {
      _friends[index] =
          _friends[index].copyWith(lastSeen: lastSeen ?? DateTime.now());
      final success = await _saveToFile();
      if (success) {
        debugLog('Updated friend last seen: $userId');
      }
      return success;
    }

    debugLog('Friend $userId not found for last seen update');
    return false;
  }

  // Get friends sorted by various criteria
  List<Friend> getFriendsSortedByName() {
    final activeFriends = this.activeFriends;
    activeFriends.sort((a, b) => a.userName.compareTo(b.userName));
    return activeFriends;
  }

  List<Friend> getFriendsSortedByLastSeen() {
    final activeFriends = this.activeFriends;
    activeFriends.sort((a, b) {
      if (a.lastSeen == null && b.lastSeen == null) return 0;
      if (a.lastSeen == null) return 1;
      if (b.lastSeen == null) return -1;
      return b.lastSeen!.compareTo(a.lastSeen!); // Most recent first
    });
    return activeFriends;
  }

  List<Friend> getFriendsSortedByAddedDate() {
    final activeFriends = this.activeFriends;
    activeFriends
        .sort((a, b) => b.addedAt.compareTo(a.addedAt)); // Most recent first
    return activeFriends;
  }

  // Search friends by name
  List<Friend> searchFriends(String query) {
    if (query.trim().isEmpty) return activeFriends;

    final lowercaseQuery = query.toLowerCase();
    return activeFriends
        .where((friend) =>
            friend.userName.toLowerCase().contains(lowercaseQuery) ||
            friend.userId.toLowerCase().contains(lowercaseQuery))
        .toList();
  }

  Future<bool> clearAllFriends() async {
    await _ensureInitialized();

    _friends.clear();
    final success = await _saveToFile();

    if (success) {
      debugLog('Cleared all friends');
    }

    return success;
  }

  // Get statistics
  Map<String, int> getStatistics() {
    return {
      'total': _friends.length,
      'active': activeFriends.length,
      'blocked': blockedFriends.length,
      'recentlyOnline': recentlyOnlineFriends.length,
    };
  }
}
