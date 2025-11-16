import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_click_match/services/friends_cache_service.dart';

String _cacheFilePath(Directory dir, String username) =>
    '${dir.path}/friends_cache_${username} .json';

void main() {
  late FriendsCacheService service;
  late Directory tempDir;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('friends_cache_service_test');
    service = FriendsCacheService.createForTest();
    service.setDocumentsDirectoryProvider(() async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Friend Model Tests', () {
    test('should create Friend from JSON correctly', () {
      final json = {
        'userId': 'user123',
        'userName': 'John Doe',
        'addedAt': '2023-01-15T10:30:00.000Z',
        'isBlocked': false,
      };

      final friend = Friend.fromJson(json);

      expect(friend.userId, equals('user123'));
      expect(friend.userName, equals('John Doe'));
      expect(
          friend.addedAt, equals(DateTime.parse('2023-01-15T10:30:00.000Z')));
      expect(friend.isBlocked, equals(false));
    });

    test('should convert Friend to JSON correctly', () {
      final friend = Friend(
        userId: 'user123',
        userName: 'John Doe',
        addedAt: DateTime.parse('2023-01-15T10:30:00.000Z'),
        isBlocked: true,
      );

      final json = friend.toJson();

      expect(json['userId'], equals('user123'));
      expect(json['userName'], equals('John Doe'));
      expect(json['addedAt'], equals('2023-01-15T10:30:00.000Z'));
      expect(json['isBlocked'], equals(true));
    });

    test('should handle missing isBlocked field in JSON (defaults to false)',
        () {
      final json = {
        'userId': 'user123',
        'userName': 'John Doe',
        'addedAt': '2023-01-15T10:30:00.000Z',
      };

      final friend = Friend.fromJson(json);

      expect(friend.isBlocked, equals(false));
    });

    test('should create copy with modified fields', () {
      final original = Friend(
        userId: 'user123',
        userName: 'John Doe',
        addedAt: DateTime.parse('2023-01-15T10:30:00.000Z'),
        isBlocked: false,
      );

      final modified = original.copyWith(
        userName: 'Jane Doe',
        isBlocked: true,
      );

      expect(modified.userId, equals(original.userId));
      expect(modified.addedAt, equals(original.addedAt));
      expect(modified.userName, equals('Jane Doe'));
      expect(modified.isBlocked, equals(true));
    });
  });

  group('FriendsCacheService Tests', () {
    group('Initialization', () {
      test('should initialize with empty list when file does not exist',
          () async {
        await service.initialize('init_user');

        expect(service.friends, isEmpty);
        expect(service.activeFriends, isEmpty);
        expect(service.blockedFriends, isEmpty);
      });

      test('should load friends from existing file', () async {
        final testData = [
          {
            'userId': 'user1',
            'userName': 'Alice',
            'addedAt': '2023-01-15T10:30:00.000Z',
            'isBlocked': false,
          },
          {
            'userId': 'user2',
            'userName': 'Bob',
            'addedAt': '2023-01-16T10:30:00.000Z',
            'isBlocked': true,
          },
        ];

        final cacheFile = File(_cacheFilePath(tempDir, 'load_user'));
        await cacheFile.writeAsString(json.encode(testData));

        await service.initialize('load_user');

        expect(service.friends.length, equals(2));
        expect(service.blockedFriends.length, equals(1));
        expect(service.getFriend('user2')?.userName, equals('Bob'));
      });
    });

    group('Friend Management', () {
      test('should add friend successfully', () async {
        final result = await service.addFriend('user123', 'John Doe');

        expect(result, isTrue);
        expect(service.friends.length, equals(1));
        expect(service.friends.first.userId, equals('user123'));
        expect(service.friends.first.userName, equals('John Doe'));
        expect(service.friends.first.isBlocked, isFalse);
      });

      test('should not persist guest users', () async {
        final result = await service.addFriend('guest_123', 'Guest Kid');

        expect(result, isFalse);
        expect(service.friends, isEmpty);
      });

      test('should not add duplicate friend', () async {
        await service.addFriend('user123', 'John Doe');
        final result = await service.addFriend('user123', 'John Doe');

        expect(result, isFalse);
        expect(service.friends.length, equals(1));
      });

      test('should remove friend', () async {
        await service.addFriend('user123', 'John Doe');
        expect(service.friends.length, equals(1));

        await service.removeFriend('user123');

        expect(service.friends, isEmpty);
      });

      test('should block friend', () async {
        await service.addFriend('user123', 'John Doe');

        await service.blockFriend('user123');

        final friend = service.getFriend('user123');
        expect(friend?.isBlocked, isTrue);
        expect(service.activeFriends.length, equals(0));
        expect(service.blockedFriends.length, equals(1));
      });

      test('should unblock friend', () async {
        await service.addFriend('user123', 'John Doe');
        await service.blockFriend('user123');

        await service.unblockFriend('user123');

        final friend = service.getFriend('user123');
        expect(friend?.isBlocked, isFalse);
        expect(service.activeFriends.length, equals(1));
        expect(service.blockedFriends.length, equals(0));
      });

      test('should update friend name', () async {
        await service.addFriend('user123', 'John Doe');

        await service.updateFriendName('user123', 'Jane Doe');

        final friend = service.getFriend('user123');
        expect(friend?.userName, equals('Jane Doe'));
      });
    });

    group('Friend Queries', () {
      setUp(() async {
        await service.addFriend('user1', 'Alice');
        await service.addFriend('user2', 'Bob');
        await service.addFriend('user3', 'Charlie');
        await service.blockFriend('user2');
      });

      test('should check if friend exists', () {
        expect(service.hasFriend('user1'), isTrue);
        expect(service.hasFriend('user999'), isFalse);
      });

      test('should get friend by userId', () {
        final friend = service.getFriend('user1');

        expect(friend, isNotNull);
        expect(friend!.userId, equals('user1'));
        expect(friend.userName, equals('Alice'));
      });

      test('should return null for non-existent friend', () {
        final friend = service.getFriend('user999');
        expect(friend, isNull);
      });

      test('should check if friend is blocked', () {
        expect(service.isFriendBlocked('user1'), isFalse);
        expect(service.isFriendBlocked('user2'), isTrue);
        expect(service.isFriendBlocked('user999'), isFalse);
      });

      test('should return active friends only', () {
        final activeFriends = service.activeFriends;

        expect(activeFriends.length, equals(2));
        expect(activeFriends.any((f) => f.userId == 'user1'), isTrue);
        expect(activeFriends.any((f) => f.userId == 'user3'), isTrue);
        expect(activeFriends.any((f) => f.userId == 'user2'), isFalse);
      });

      test('should return blocked friends only', () {
        final blockedFriends = service.blockedFriends;

        expect(blockedFriends.length, equals(1));
        expect(blockedFriends.first.userId, equals('user2'));
      });

      test('should return all friends including blocked', () {
        final allFriends = service.friends;

        expect(allFriends.length, equals(3));
      });
    });

    group('Edge Cases and Error Handling', () {
      test('should handle operations on non-existent friends gracefully',
          () async {
        await service.removeFriend('nonexistent');
        await service.blockFriend('nonexistent');
        await service.unblockFriend('nonexistent');
        await service.updateFriendName('nonexistent', 'New Name');

        expect(service.friends.length, equals(0));
      });

      test('should handle empty userId', () async {
        final result = await service.addFriend('', 'Empty User');

        expect(result, isFalse);
        expect(service.hasFriend(''), isFalse);
      });

      test('should handle empty userName', () async {
        final result = await service.addFriend('user123', '');

        expect(result, isTrue);
        final friend = service.getFriend('user123');
        expect(friend?.userName, equals(''));
      });
    });

    group('Data Persistence Simulation', () {
      test('should maintain data consistency after operations', () async {
        await service.addFriend('user1', 'Alice');
        await service.addFriend('user2', 'Bob');
        await service.addFriend('user3', 'Charlie');

        await service.blockFriend('user1');
        await service.updateFriendName('user2', 'Robert');
        await service.removeFriend('user3');

        expect(service.friends.length, equals(2));
        expect(service.activeFriends.length, equals(1));
        expect(service.blockedFriends.length, equals(1));

        final alice = service.getFriend('user1');
        final bob = service.getFriend('user2');

        expect(alice?.isBlocked, isTrue);
        expect(bob?.userName, equals('Robert'));
        expect(service.getFriend('user3'), isNull);
      });
    });
  });

  group('Integration-like Tests', () {
    test('should handle complex friend management workflow', () async {
      expect(await service.addFriend('alice123', 'Alice Smith'), isTrue);
      expect(await service.addFriend('bob456', 'Bob Jones'), isTrue);
      expect(await service.addFriend('charlie789', 'Charlie Brown'), isTrue);

      expect(await service.addFriend('alice123', 'Alice Smith'), isFalse);

      await service.blockFriend('bob456');
      expect(service.isFriendBlocked('bob456'), isTrue);
      expect(service.activeFriends.length, equals(2));

      await service.updateFriendName('alice123', 'Alice Johnson');
      expect(service.getFriend('alice123')?.userName, equals('Alice Johnson'));

      await service.unblockFriend('bob456');
      expect(service.activeFriends.length, equals(3));

      await service.removeFriend('charlie789');
      expect(service.friends.length, equals(2));
      expect(service.hasFriend('charlie789'), isFalse);

      expect(service.friends.length, equals(2));
      expect(service.activeFriends.length, equals(2));
      expect(service.blockedFriends.length, equals(0));
    });
  });
}
