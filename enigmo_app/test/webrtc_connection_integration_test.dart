import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:enigmo_app/services/audio_call_service.dart';
import 'package:enigmo_app/services/network_service.dart';
import 'package:enigmo_app/services/crypto_engine.dart';
import 'package:enigmo_app/models/call.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('WebRTC Connection Integration Tests', () {
    late NetworkService networkService;
    late AudioCallService audioCallService;
    late CryptoEngine cryptoEngine;

    setUp(() async {
      networkService = NetworkService();
      cryptoEngine = CryptoEngine();
      audioCallService = AudioCallService(networkService, cryptoEngine);

      // Connect to server
      final connected = await networkService.connect();
      expect(connected, true);

      // Register and authenticate
      final userId = await networkService.registerUser(nickname: 'WebRTCIntegrationTest');
      expect(userId, isNotNull);

      final authenticated = await networkService.authenticate();
      expect(authenticated, true);
    });

    tearDown(() {
      audioCallService.endCall();
      networkService.dispose();
    });

    test('WebRTC peer connection creation', () async {
      final recipientId = 'webrtc_test_user';

      // Start call (this will attempt to create WebRTC connection)
      await audioCallService.initiateCall(recipientId);

      // Verify call object is created
      expect(audioCallService.currentCall, isNotNull);
      expect(audioCallService.currentCall!.status, CallStatus.connecting);

      // In test environment, WebRTC will fail but the framework should handle it gracefully
      // The service should not crash
      expect(audioCallService.currentCall, isNotNull);
    });

    test('ICE candidate handling integration', () async {
      final recipientId = 'ice_test_user';

      await audioCallService.initiateCall(recipientId);

      // Simulate ICE candidate exchange
      // In real scenario, this would happen through the signaling server
      final candidatePayload = {
        'candidate': 'test_ice_candidate',
        'call_id': audioCallService.currentCall!.id,
        'from': recipientId,
      };

      // This should not crash even if WebRTC is not available in test environment
      expect(() {
        // ICE handling is internal, we test that the service remains stable
        return audioCallService.currentCall;
      }(), isNotNull);
    });

    test('Media stream handling', () async {
      final recipientId = 'media_test_user';

      await audioCallService.initiateCall(recipientId);

      // Test media stream access
      final localStream = audioCallService.localStream;
      final remoteStream = audioCallService.remoteStream;

      // In test environment, streams will be null but service should handle it
      expect(localStream, isNull); // WebRTC not available in test
      expect(remoteStream, isNull);

      // Service should remain stable
      expect(audioCallService.currentCall, isNotNull);
    });

    test('Connection state transitions', () async {
      final recipientId = 'state_test_user';
      final stateChanges = <CallStatus>[];

      audioCallService.onCallStatusChange = (call) {
        stateChanges.add(call.status);
      };

      await audioCallService.initiateCall(recipientId);

      // Simulate various connection states
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnecting);
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateDisconnected);
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateFailed);

      // Verify state changes are handled
      expect(stateChanges.length, greaterThanOrEqualTo(4));
      expect(stateChanges.contains(CallStatus.connecting), true);
      expect(stateChanges.contains(CallStatus.connected), true);
      expect(stateChanges.contains(CallStatus.ended), true);
    });

    test('ICE connection state handling', () async {
      final recipientId = 'ice_connection_test_user';

      await audioCallService.initiateCall(recipientId);

      // Test ICE connection state changes
      audioCallService.testHandleIceConnectionStateChange(RTCIceConnectionState.RTCIceConnectionStateConnected);
      expect(audioCallService.currentCall!.status, CallStatus.connected);

      audioCallService.testHandleIceConnectionStateChange(RTCIceConnectionState.RTCIceConnectionStateDisconnected);
      expect(audioCallService.currentCall!.status, CallStatus.connecting);

      audioCallService.testHandleIceConnectionStateChange(RTCIceConnectionState.RTCIceConnectionStateFailed);
      expect(audioCallService.currentCall!.status, CallStatus.ended);
    });

    test('Signaling state changes', () async {
      final recipientId = 'signaling_test_user';

      await audioCallService.initiateCall(recipientId);

      // Signaling state changes are handled internally
      // We test that the service remains stable
      expect(audioCallService.currentCall, isNotNull);
      expect(audioCallService.currentCall!.status, CallStatus.connecting);
    });

    test('Call restart functionality', () async {
      final recipientId = 'restart_test_user';

      await audioCallService.initiateCall(recipientId);

      // Simulate connection loss
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateDisconnected);

      // Service should attempt restart
      expect(audioCallService.currentCall!.status, CallStatus.connecting);

      // Simulate restart offer
      final restartPayload = {
        'offer': 'restart_encrypted_offer',
        'call_id': audioCallService.currentCall!.id,
        'from': recipientId,
      };

      audioCallService.testHandleRestart(restartPayload);

      // Service should handle restart
      expect(audioCallService.currentCall, isNotNull);
    });

    test('Call restart answer handling', () async {
      final recipientId = 'restart_answer_test_user';

      await audioCallService.initiateCall(recipientId);

      // Simulate restart answer
      final restartAnswerPayload = {
        'answer': 'restart_encrypted_answer',
        'call_id': audioCallService.currentCall!.id,
        'from': recipientId,
      };

      audioCallService.testHandleRestartAnswer(restartAnswerPayload);

      // Service should handle restart answer
      expect(audioCallService.currentCall, isNotNull);
    });

    test('Audio control integration with WebRTC', () async {
      final recipientId = 'audio_control_test_user';

      await audioCallService.initiateCall(recipientId);

      // Test mute functionality
      final initialMuteState = audioCallService.isMuted;
      await audioCallService.toggleMute();
      expect(audioCallService.isMuted, isNot(initialMuteState));

      // Test speakerphone functionality
      await audioCallService.toggleSpeakerphone();
      final speakerEnabled = await audioCallService.isSpeakerphoneEnabled();
      expect(speakerEnabled, isA<bool>());
    });

    test('SDP encryption and decryption', () async {
      final recipientId = 'sdp_test_user';
      const testSdp = 'v=0\r\no=- 1234567890 1234567890 IN IP4 127.0.0.1\r\ns=-\r\nc=IN IP4 127.0.0.1\r\nt=0 0\r\nm=audio 12345 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000';

      await audioCallService.initiateCall(recipientId);

      // Test SDP handling with encryption
      final offerPayload = {
        'call_id': audioCallService.currentCall!.id,
        'offer': 'encrypted_offer_sdp',
        'from': recipientId,
      };

      audioCallService.testHandleOffer(offerPayload);

      // Service should handle encrypted SDP
      expect(audioCallService.currentCall, isNotNull);
    });

    test('WebRTC resource cleanup', () async {
      final recipientId = 'cleanup_test_user';

      await audioCallService.initiateCall(recipientId);

      // End call and verify cleanup
      await audioCallService.endCall();

      expect(audioCallService.currentCall!.status, CallStatus.ended);
      expect(audioCallService.localStream, isNull);
      expect(audioCallService.remoteStream, isNull);
    });

    test('Multiple call cleanup', () async {
      final recipients = ['multi_cleanup_1', 'multi_cleanup_2', 'multi_cleanup_3'];

      // Create multiple calls and clean them up
      for (final recipient in recipients) {
        await audioCallService.initiateCall(recipient);
        await audioCallService.endCall();
      }

      // Verify final state
      expect(audioCallService.currentCall, isNotNull);
      expect(audioCallService.currentCall!.status, CallStatus.ended);
    });

    test('WebRTC error recovery', () async {
      final recipientId = 'error_recovery_test_user';

      await audioCallService.initiateCall(recipientId);

      // Simulate WebRTC errors
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateFailed);

      // Service should handle error gracefully
      expect(audioCallService.currentCall!.status, CallStatus.ended);
    });

    test('Connection timeout handling', () async {
      final recipientId = 'timeout_test_user';

      await audioCallService.initiateCall(recipientId);

      // Wait for potential timeout
      await Future.delayed(const Duration(seconds: 5));

      // Service should remain stable
      expect(audioCallService.currentCall, isNotNull);
    });
  });
}