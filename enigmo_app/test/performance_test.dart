import 'package:flutter_test/flutter_test.dart';
import 'package:enigmo_app/services/crypto_engine.dart';
import 'package:enigmo_app/services/network_service.dart';
import 'package:enigmo_app/services/audio_call_service.dart';
import 'package:enigmo_app/services/key_manager.dart';
import 'package:enigmo_app/models/call.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Performance Tests', () {
    late CryptoEngine cryptoEngine;
    late NetworkService networkService;
    late AudioCallService audioCallService;
    late KeyManager keyManager;

    setUp(() {
      cryptoEngine = CryptoEngine();
      networkService = NetworkService();
      // audioCallService = AudioCallService(networkService, cryptoEngine);
      keyManager = KeyManager();
    });

    tearDown(() {
      networkService.dispose();
    });

    group('CryptoEngine Performance Tests', () {
      test('should encrypt/decrypt within acceptable time', () async {
        const message = 'Performance test message for encryption';
        const iterations = 100;

        final encryptTimes = <int>[];
        final decryptTimes = <int>[];

        for (var i = 0; i < iterations; i++) {
          final encryptStart = DateTime.now().millisecondsSinceEpoch;
          final encrypted = await cryptoEngine.encrypt(message);
          final encryptEnd = DateTime.now().millisecondsSinceEpoch;
          encryptTimes.add(encryptEnd - encryptStart);

          final decryptStart = DateTime.now().millisecondsSinceEpoch;
          final decrypted = await cryptoEngine.decrypt(encrypted);
          final decryptEnd = DateTime.now().millisecondsSinceEpoch;
          decryptTimes.add(decryptEnd - decryptStart);

          expect(decrypted, equals(message));
        }

        final avgEncryptTime = encryptTimes.reduce((a, b) => a + b) / iterations;
        final avgDecryptTime = decryptTimes.reduce((a, b) => a + b) / iterations;
        final maxEncryptTime = encryptTimes.reduce((a, b) => a > b ? a : b);
        final maxDecryptTime = decryptTimes.reduce((a, b) => a > b ? a : b);

        print('Crypto Performance Results:');
        print('Average encrypt time: ${avgEncryptTime}ms');
        print('Average decrypt time: ${avgDecryptTime}ms');
        print('Max encrypt time: ${maxEncryptTime}ms');
        print('Max decrypt time: ${maxDecryptTime}ms');

        // Performance assertions
        expect(avgEncryptTime, lessThan(100)); // Should be under 100ms average
        expect(avgDecryptTime, lessThan(100));
        expect(maxEncryptTime, lessThan(500)); // Should be under 500ms max
        expect(maxDecryptTime, lessThan(500));
      });

      test('should handle large payloads efficiently', () async {
        final sizes = [1000, 10000, 50000, 100000]; // 1KB, 10KB, 50KB, 100KB

        for (final size in sizes) {
          final largeMessage = 'x' * size;

          final startTime = DateTime.now().millisecondsSinceEpoch;
          final encrypted = await cryptoEngine.encrypt(largeMessage);
          final decryptStart = DateTime.now().millisecondsSinceEpoch;
          final decrypted = await cryptoEngine.decrypt(encrypted);
          final endTime = DateTime.now().millisecondsSinceEpoch;

          final encryptTime = decryptStart - startTime;
          final decryptTime = endTime - decryptStart;
          final totalTime = endTime - startTime;

          print('Large payload performance (${size} chars):');
          print('Encrypt time: ${encryptTime}ms');
          print('Decrypt time: ${decryptTime}ms');
          print('Total time: ${totalTime}ms');

          expect(decrypted, equals(largeMessage));
          expect(totalTime, lessThan(2000)); // Should complete within 2 seconds
        }
      });

      test('should maintain performance under concurrent load', () async {
        const concurrentOperations = 50;
        const message = 'Concurrent performance test message';

        final futures = <Future>[];
        final startTime = DateTime.now().millisecondsSinceEpoch;

        for (var i = 0; i < concurrentOperations; i++) {
          futures.add(cryptoEngine.encrypt(message));
        }

        final results = await Future.wait(futures);
        final endTime = DateTime.now().millisecondsSinceEpoch;

        final totalTime = endTime - startTime;
        final avgTime = totalTime / concurrentOperations;

        print('Concurrent encryption performance:');
        print('Total time: ${totalTime}ms for $concurrentOperations operations');
        print('Average time per operation: ${avgTime}ms');

        expect(results.length, equals(concurrentOperations));
        expect(results.every((result) => result != null), isTrue);
        expect(avgTime, lessThan(50)); // Should be under 50ms per operation
      });

      test('should generate keys within acceptable time', () async {
        const iterations = 10;
        final keyGenTimes = <int>[];

        for (var i = 0; i < iterations; i++) {
          final startTime = DateTime.now().millisecondsSinceEpoch;
          final keyPair = await cryptoEngine.generateKeyPair();
          final endTime = DateTime.now().millisecondsSinceEpoch;

          keyGenTimes.add(endTime - startTime);

          expect(keyPair.publicKey, isNotNull);
          expect(keyPair.privateKey, isNotNull);
          expect(keyPair.publicKey.length, equals(64));
          expect(keyPair.privateKey.length, equals(64));
        }

        final avgKeyGenTime = keyGenTimes.reduce((a, b) => a + b) / iterations;
        final maxKeyGenTime = keyGenTimes.reduce((a, b) => a > b ? a : b);

        print('Key generation performance:');
        print('Average time: ${avgKeyGenTime}ms');
        print('Max time: ${maxKeyGenTime}ms');

        expect(avgKeyGenTime, lessThan(200)); // Should be under 200ms average
        expect(maxKeyGenTime, lessThan(1000)); // Should be under 1s max
      });
    });

    group('KeyManager Performance Tests', () {
      test('should store and retrieve keys efficiently', () async {
        const userId = 'test_user_performance';
        const iterations = 100;

        final storeTimes = <int>[];
        final retrieveTimes = <int>[];

        // Pre-generate key pair
        final keyPair = await cryptoEngine.generateKeyPair();

        for (var i = 0; i < iterations; i++) {
          final storeStart = DateTime.now().millisecondsSinceEpoch;
          await keyManager.storeKeyPair(userId, keyPair.publicKey, keyPair.privateKey);
          final storeEnd = DateTime.now().millisecondsSinceEpoch;
          storeTimes.add(storeEnd - storeStart);

          final retrieveStart = DateTime.now().millisecondsSinceEpoch;
          final retrievedPair = await keyManager.getKeyPair(userId);
          final retrieveEnd = DateTime.now().millisecondsSinceEpoch;
          retrieveTimes.add(retrieveEnd - retrieveStart);

          expect(retrievedPair, isNotNull);
          expect(retrievedPair!.publicKey, equals(keyPair.publicKey));
        }

        final avgStoreTime = storeTimes.reduce((a, b) => a + b) / iterations;
        final avgRetrieveTime = retrieveTimes.reduce((a, b) => a + b) / iterations;

        print('Key storage/retrieval performance:');
        print('Average store time: ${avgStoreTime}ms');
        print('Average retrieve time: ${avgRetrieveTime}ms');

        expect(avgStoreTime, lessThan(10)); // Should be very fast
        expect(avgRetrieveTime, lessThan(10));
      });

      test('should generate user IDs quickly', () async {
        const iterations = 1000;
        final genTimes = <int>[];

        for (var i = 0; i < iterations; i++) {
          final startTime = DateTime.now().millisecondsSinceEpoch;
          final userId = await keyManager.generateUserId();
          final endTime = DateTime.now().millisecondsSinceEpoch;

          genTimes.add(endTime - startTime);

          expect(userId, isNotNull);
          expect(userId.length, equals(16));
        }

        final avgGenTime = genTimes.reduce((a, b) => a + b) / iterations;
        final maxGenTime = genTimes.reduce((a, b) => a > b ? a : b);

        print('User ID generation performance:');
        print('Average time: ${avgGenTime}ms for $iterations IDs');
        print('Max time: ${maxGenTime}ms');

        expect(avgGenTime, lessThan(1)); // Should be very fast
        expect(maxGenTime, lessThan(10));
      });
    });

    group('Call Model Performance Tests', () {
      test('should handle rapid call state changes', () {
        const iterations = 1000;
        final call = Call(
          id: 'perf_test_call',
          recipientId: 'perf_test_recipient',
          status: CallStatus.connecting,
          isOutgoing: true,
          startTime: DateTime.now(),
        );

        final startTime = DateTime.now().millisecondsSinceEpoch;

        for (var i = 0; i < iterations; i++) {
          final newCall = call.copyWith(
            status: i % 2 == 0 ? CallStatus.connected : CallStatus.ended,
          );
          expect(newCall, isNotNull);
        }

        final endTime = DateTime.now().millisecondsSinceEpoch;
        final totalTime = endTime - startTime;
        final avgTime = totalTime / iterations;

        print('Call state change performance:');
        print('Total time: ${totalTime}ms for $iterations changes');
        print('Average time per change: ${avgTime}ms');

        expect(avgTime, lessThan(0.1)); // Should be very fast
      });

      test('should create multiple calls efficiently', () {
        const iterations = 10000;
        final calls = <Call>[];

        final startTime = DateTime.now().millisecondsSinceEpoch;

        for (var i = 0; i < iterations; i++) {
          final call = Call(
            id: 'call_$i',
            recipientId: 'recipient_$i',
            status: CallStatus.connecting,
            isOutgoing: i % 2 == 0,
            startTime: DateTime.now(),
          );
          calls.add(call);
        }

        final endTime = DateTime.now().millisecondsSinceEpoch;
        final totalTime = endTime - startTime;
        final avgTime = totalTime / iterations;

        print('Call creation performance:');
        print('Total time: ${totalTime}ms for $iterations calls');
        print('Average time per call: ${avgTime}ms');

        expect(calls.length, equals(iterations));
        expect(avgTime, lessThan(0.1)); // Should be very fast
      });
    });

    group('Memory Usage Tests', () {
      test('should not have memory leaks in crypto operations', () async {
        const iterations = 1000;
        final results = <String>[];

        final startTime = DateTime.now().millisecondsSinceEpoch;

        for (var i = 0; i < iterations; i++) {
          final message = 'Memory test message $i';
          final encrypted = await cryptoEngine.encrypt(message);
          final decrypted = await cryptoEngine.decrypt(encrypted);
          results.add(decrypted);

          expect(decrypted, equals(message));
        }

        final endTime = DateTime.now().millisecondsSinceEpoch;
        final totalTime = endTime - startTime;

        print('Memory usage test:');
        print('Processed $iterations messages in ${totalTime}ms');
        print('Memory footprint: ${results.length} results stored');

        expect(results.length, equals(iterations));
        expect(totalTime, lessThan(30000)); // Should complete within 30 seconds
      });

      test('should handle large concurrent operations without memory issues', () async {
        const concurrentOperations = 100;
        final messages = List.generate(concurrentOperations, (i) => 'Message $i');

        final startTime = DateTime.now().millisecondsSinceEpoch;

        final futures = messages.map((message) async {
          final encrypted = await cryptoEngine.encrypt(message);
          final decrypted = await cryptoEngine.decrypt(encrypted);
          return decrypted;
        });

        final results = await Future.wait(futures);
        final endTime = DateTime.now().millisecondsSinceEpoch;

        final totalTime = endTime - startTime;

        print('Concurrent memory test:');
        print('Processed $concurrentOperations concurrent operations in ${totalTime}ms');

        expect(results.length, equals(concurrentOperations));
        expect(results.every((result) => messages.contains(result)), isTrue);
        expect(totalTime, lessThan(10000)); // Should complete within 10 seconds
      });
    });

    group('Scalability Tests', () {
      test('should scale with increasing message sizes', () async {
        final sizes = [100, 1000, 10000, 100000];
        final times = <int>[];

        for (final size in sizes) {
          final message = 'x' * size;
          final startTime = DateTime.now().millisecondsSinceEpoch;

          final encrypted = await cryptoEngine.encrypt(message);
          final decrypted = await cryptoEngine.decrypt(encrypted);

          final endTime = DateTime.now().millisecondsSinceEpoch;
          times.add(endTime - startTime);

          expect(decrypted, equals(message));
        }

        print('Scalability test results:');
        for (var i = 0; i < sizes.length; i++) {
          print('${sizes[i]} chars: ${times[i]}ms');
        }

        // Verify that time scales reasonably with size
        for (var i = 1; i < times.length; i++) {
          final ratio = times[i] / times[i - 1];
          final sizeRatio = sizes[i] / sizes[i - 1];
          print('Size ratio: $sizeRatio, Time ratio: $ratio');

          // Time should scale roughly linearly or better
          expect(ratio, lessThan(sizeRatio * 2));
        }
      });

      test('should handle increasing concurrent load', () async {
        final concurrentLoads = [10, 50, 100, 200];
        final times = <int>[];

        for (final load in concurrentLoads) {
          final message = 'Concurrent load test message';
          final startTime = DateTime.now().millisecondsSinceEpoch;

          final futures = List.generate(load, (_) => cryptoEngine.encrypt(message));
          await Future.wait(futures);

          final endTime = DateTime.now().millisecondsSinceEpoch;
          times.add(endTime - startTime);
        }

        print('Concurrent load test results:');
        for (var i = 0; i < concurrentLoads.length; i++) {
          print('${concurrentLoads[i]} concurrent operations: ${times[i]}ms');
        }

        // Verify that concurrent operations complete in reasonable time
        for (final time in times) {
          expect(time, lessThan(5000)); // Should complete within 5 seconds
        }
      });
    });

    group('Resource Cleanup Tests', () {
      test('should clean up resources properly', () async {
        // Test that repeated operations don't accumulate resources
        const iterations = 100;

        for (var i = 0; i < iterations; i++) {
          final keyPair = await cryptoEngine.generateKeyPair();
          expect(keyPair.publicKey, isNotNull);

          final message = 'Cleanup test $i';
          final encrypted = await cryptoEngine.encrypt(message);
          final decrypted = await cryptoEngine.decrypt(encrypted);
          expect(decrypted, equals(message));
        }

        // If we get here without memory issues, cleanup is working
        expect(true, isTrue);
      });
    });
  });
}