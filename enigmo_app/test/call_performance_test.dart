import 'package:flutter_test/flutter_test.dart';
import 'package:enigmo_app/services/audio_call_service.dart';
import 'package:enigmo_app/services/network_service.dart';
import 'package:enigmo_app/services/crypto_engine.dart';
import 'package:enigmo_app/models/call.dart';

// Mock classes for performance testing
class MockNetworkService extends Mock implements NetworkService {
  @override
  Future<bool> send(String type, Map<String, dynamic> data) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 50));
    return true;
  }
}

class MockCryptoEngine extends Mock implements CryptoEngine {
  @override
  Future<String> encrypt(String data) async {
    // Simulate encryption delay
    await Future.delayed(const Duration(milliseconds: 10));
    return 'encrypted_data';
  }

  @override
  Future<String> decrypt(String data) async {
    // Simulate decryption delay
    await Future.delayed(const Duration(milliseconds: 10));
    return 'v=0\r\no=- 1234567890 1234567890 IN IP4 127.0.0.1\r\ns=-\r\nc=IN IP4 127.0.0.1\r\nt=0 0\r\nm=audio 12345 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000';
  }
}

void main() {
  group('Call Performance Tests', () {
    late AudioCallService audioCallService;
    late MockNetworkService mockNetworkService;
    late MockCryptoEngine mockCryptoEngine;

    setUp(() {
      mockNetworkService = MockNetworkService();
      mockCryptoEngine = MockCryptoEngine();
      audioCallService = AudioCallService(mockNetworkService, mockCryptoEngine);
    });

    tearDown(() {
      audioCallService.endCall();
    });

    test('Call initiation performance', () async {
      final recipientId = 'perf_test_user';
      final stopwatch = Stopwatch();

      // Measure call initiation time
      stopwatch.start();
      await audioCallService.initiateCall(recipientId);
      stopwatch.stop();

      // Call initiation should complete within reasonable time
      expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Less than 1 second
      expect(audioCallService.currentCall, isNotNull);
    });

    test('Rapid call state changes performance', () async {
      final recipientId = 'perf_state_test';
      final stopwatch = Stopwatch();
      final stateChanges = <CallStatus>[];

      audioCallService.onCallStatusChange = (call) {
        stateChanges.add(call.status);
      };

      await audioCallService.initiateCall(recipientId);

      // Measure rapid state changes
      stopwatch.start();
      for (int i = 0; i < 10; i++) {
        audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);
        audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateDisconnected);
      }
      stopwatch.stop();

      // State changes should be fast
      expect(stopwatch.elapsedMilliseconds, lessThan(500)); // Less than 500ms for 20 changes
      expect(stateChanges.length, greaterThanOrEqualTo(20));
    });

    test('Multiple simultaneous call operations', () async {
      final recipientId = 'perf_multi_test';
      final stopwatch = Stopwatch();

      await audioCallService.initiateCall(recipientId);

      // Measure multiple operations
      stopwatch.start();
      await Future.wait([
        audioCallService.toggleMute(),
        audioCallService.toggleSpeakerphone(),
        audioCallService.isSpeakerphoneEnabled(),
        audioCallService.endCall(),
      ]);
      stopwatch.stop();

      // Multiple operations should complete quickly
      expect(stopwatch.elapsedMilliseconds, lessThan(200)); // Less than 200ms
    });

    test('Memory efficiency - call cleanup', () async {
      final recipientIds = List.generate(5, (i) => 'perf_memory_test_$i');

      // Create multiple calls and clean them up
      for (final recipientId in recipientIds) {
        await audioCallService.initiateCall(recipientId);
        await audioCallService.endCall();
      }

      // Verify no memory leaks (call should be properly cleaned up)
      expect(audioCallService.currentCall, isNull);
    });

    test('Call duration tracking accuracy', () async {
      final recipientId = 'perf_duration_test';

      await audioCallService.initiateCall(recipientId);

      // Simulate call connection
      final answerPayload = {
        'call_id': audioCallService.currentCall!.id,
        'answer': 'encrypted_answer_sdp',
        'from': recipientId,
      };

      audioCallService.testHandleAnswer(answerPayload);

      // Wait for a specific duration
      await Future.delayed(const Duration(seconds: 2));

      final call = audioCallService.currentCall;
      expect(call, isNotNull);
      expect(call!.startTime, isNotNull);

      // Duration should be tracked accurately
      final actualDuration = DateTime.now().difference(call.startTime);
      expect(actualDuration.inSeconds, greaterThanOrEqualTo(2));
      expect(actualDuration.inSeconds, lessThan(5)); // Allow some margin for test execution
    });

    test('High frequency state updates', () async {
      final recipientId = 'perf_frequency_test';
      final updateCount = 100;
      final stopwatch = Stopwatch();
      int updateCounter = 0;

      audioCallService.onCallStatusChange = (call) {
        updateCounter++;
      };

      await audioCallService.initiateCall(recipientId);

      // Simulate high frequency updates
      stopwatch.start();
      for (int i = 0; i < updateCount; i++) {
        audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);
      }
      stopwatch.stop();

      // Should handle high frequency updates efficiently
      expect(updateCounter, updateCount);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // Less than 1 second for 100 updates
    });

    test('Concurrent call operations', () async {
      final recipientId = 'perf_concurrent_test';
      final operationCount = 10;
      final stopwatch = Stopwatch();

      await audioCallService.initiateCall(recipientId);

      // Perform concurrent operations
      stopwatch.start();
      final futures = List.generate(operationCount, (i) async {
        await audioCallService.toggleMute();
        await audioCallService.toggleSpeakerphone();
        return audioCallService.isSpeakerphoneEnabled();
      });

      await Future.wait(futures);
      stopwatch.stop();

      // Concurrent operations should complete efficiently
      expect(stopwatch.elapsedMilliseconds, lessThan(500)); // Less than 500ms for 30 operations
    });

    test('Call service initialization time', () async {
      final stopwatch = Stopwatch();

      // Measure service initialization
      stopwatch.start();
      final newAudioCallService = AudioCallService(mockNetworkService, mockCryptoEngine);
      stopwatch.stop();

      // Initialization should be fast
      expect(stopwatch.elapsedMilliseconds, lessThan(100)); // Less than 100ms

      newAudioCallService.endCall();
    });

    test('Resource cleanup performance', () async {
      final recipientId = 'perf_cleanup_test';
      final stopwatch = Stopwatch();

      await audioCallService.initiateCall(recipientId);

      // Measure cleanup time
      stopwatch.start();
      await audioCallService.endCall();
      stopwatch.stop();

      // Cleanup should be fast
      expect(stopwatch.elapsedMilliseconds, lessThan(200)); // Less than 200ms
      expect(audioCallService.currentCall, isNull);
    });

    test('Large scale call simulation', () async {
      final recipientIds = List.generate(20, (i) => 'perf_scale_test_$i');
      final stopwatch = Stopwatch();

      // Simulate large number of calls
      stopwatch.start();
      for (final recipientId in recipientIds) {
        await audioCallService.initiateCall(recipientId);
        await audioCallService.endCall();
      }
      stopwatch.stop();

      // Large scale operations should complete within reasonable time
      expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // Less than 5 seconds for 20 calls
    });
  });
}