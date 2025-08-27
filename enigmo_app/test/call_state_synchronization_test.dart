import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:enigmo_app/models/call.dart';
import 'package:enigmo_app/services/audio_call_service.dart';
import 'package:enigmo_app/services/network_service.dart';
import 'package:enigmo_app/services/crypto_engine.dart';

// Mock classes
class MockNetworkService extends Mock implements NetworkService {
  @override
  Future<bool> send(String type, Map<String, dynamic> data) async {
    return true;
  }
}

class MockCryptoEngine extends Mock implements CryptoEngine {
  @override
  Future<String> encrypt(String data) async {
    return 'encrypted_data';
  }

  @override
  Future<String> decrypt(String data) async {
    // Return different data based on input to simulate real decryption
    if (data == 'encrypted_answer_sdp') {
      return 'v=0\r\no=- 1234567890 1234567890 IN IP4 127.0.0.1\r\ns=-\r\nc=IN IP4 127.0.0.1\r\nt=0 0\r\nm=audio 12345 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000';
    } else if (data == 'encrypted_offer_sdp') {
      return 'v=0\r\no=- 9876543210 9876543210 IN IP4 127.0.0.1\r\ns=-\r\nc=IN IP4 127.0.0.1\r\nt=0 0\r\nm=audio 54321 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000';
    } else {
      return 'v=0\r\no=- 1234567890 1234567890 IN IP4 127.0.0.1\r\ns=-\r\nc=IN IP4 127.0.0.1\r\nt=0 0\r\nm=audio 12345 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000';
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Call State Synchronization Tests', () {
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

    test('Call state transitions from idle to connecting', () async {
      // Arrange
      final recipientId = 'test_user_123';
      Call? receivedCall;

      audioCallService.onCallStatusChange = (call) {
        receivedCall = call;
      };

      // Act
      await audioCallService.initiateCall(recipientId);

      // Assert
      expect(audioCallService.currentCall, isNotNull);
      expect(audioCallService.currentCall!.status, CallStatus.connecting);
      expect(audioCallService.currentCall!.recipientId, recipientId);
      expect(audioCallService.currentCall!.isOutgoing, true);
      expect(receivedCall, isNotNull);
      expect(receivedCall!.status, CallStatus.connecting);
    });

    test('Call state transitions from connecting to connected', () async {
      // Arrange
      final recipientId = 'test_user_123';
      final callId = 'call_123';
      Call? receivedCall;

      audioCallService.onCallStatusChange = (call) {
        receivedCall = call;
      };

      // Simulate incoming answer
      final answerPayload = {
        'call_id': callId,
        'answer': 'encrypted_answer_sdp',
        'from': recipientId,
      };

      // Act
      await audioCallService.initiateCall(recipientId);
      audioCallService.testHandleAnswer(answerPayload);

      // Assert
      expect(audioCallService.currentCall, isNotNull);
      expect(audioCallService.currentCall!.status, CallStatus.connected);
      expect(receivedCall, isNotNull);
      expect(receivedCall!.status, CallStatus.connected);
    });

    test('Call state transitions to ended on connection failure', () async {
      // Arrange
      final recipientId = 'test_user_123';
      Call? receivedCall;

      audioCallService.onCallStatusChange = (call) {
        receivedCall = call;
      };

      // Act
      await audioCallService.initiateCall(recipientId);

      // Simulate connection failure
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateFailed);

      // Assert
      expect(audioCallService.currentCall, isNotNull);
      expect(audioCallService.currentCall!.status, CallStatus.ended);
      expect(receivedCall, isNotNull);
      expect(receivedCall!.status, CallStatus.ended);
    });

    test('Multiple rapid state changes are handled correctly', () async {
      // Arrange
      final recipientId = 'test_user_123';
      final states = <CallStatus>[];

      audioCallService.onCallStatusChange = (call) {
        states.add(call.status);
      };

      // Act
      await audioCallService.initiateCall(recipientId);

      // Simulate rapid state changes
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnecting);
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateDisconnected);
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateFailed);

      // Assert
      expect(states.length, greaterThanOrEqualTo(4));
      expect(states.contains(CallStatus.connecting), true);
      expect(states.contains(CallStatus.connected), true);
      expect(states.contains(CallStatus.ended), true);
    });

    test('Call state is properly reset after endCall', () async {
      // Arrange
      final recipientId = 'test_user_123';

      await audioCallService.initiateCall(recipientId);
      expect(audioCallService.currentCall, isNotNull);

      // Act
      await audioCallService.endCall();

      // Assert - call should be ended but not null (service keeps last call for reference)
      expect(audioCallService.currentCall, isNotNull);
      expect(audioCallService.currentCall!.status, CallStatus.ended);
    });

    test('Incoming call state management', () async {
      // Arrange
      final callerId = 'caller_123';
      final callId = 'call_123';
      Call? incomingCall;

      audioCallService.onIncomingCall = (call) {
        incomingCall = call;
      };

      final offerPayload = {
        'call_id': callId,
        'offer': 'encrypted_offer_sdp',
        'from': callerId,
      };

      // Act
      audioCallService.testHandleOffer(offerPayload);

      // Assert
      expect(incomingCall, isNotNull);
      expect(incomingCall!.status, CallStatus.ringing);
      expect(incomingCall!.recipientId, callerId);
      expect(incomingCall!.isOutgoing, false);
      expect(incomingCall!.id, callId);
    });

    test('Call duration is tracked correctly', () async {
      // Arrange
      final recipientId = 'test_user_123';

      await audioCallService.initiateCall(recipientId);

      // Simulate connection
      final answerPayload = {
        'call_id': audioCallService.currentCall!.id,
        'answer': 'encrypted_answer_sdp',
        'from': recipientId,
      };

      audioCallService.testHandleAnswer(answerPayload);

      // Wait a bit
      await Future.delayed(const Duration(seconds: 2));

      // Act
      final call = audioCallService.currentCall;

      // Assert
      expect(call, isNotNull);
      expect(call!.status, CallStatus.connected);
      expect(call.startTime, isNotNull);
      expect(call.startTime.isBefore(DateTime.now()), true);
    });
  });
}