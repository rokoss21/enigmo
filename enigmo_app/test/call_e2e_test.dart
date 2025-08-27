import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:enigmo_app/main.dart';
import 'package:enigmo_app/services/audio_call_service.dart';
import 'package:enigmo_app/services/network_service.dart';
import 'package:enigmo_app/services/crypto_engine.dart';
import 'package:enigmo_app/models/call.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('End-to-End Call Flow Tests', () {
    testWidgets('Complete call lifecycle: app start -> call -> hang up',
        (WidgetTester tester) async {
      // Start the app
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();

      // Verify app started successfully
      expect(find.text('Enigmo'), findsOneWidget);

      // Navigate through splash screen
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      // This is a simplified E2E test - in a real scenario we would:
      // 1. Mock server responses
      // 2. Simulate user interactions
      // 3. Test complete call flow

      // For now, we'll test the service layer E2E
      final networkService = NetworkService();
      final cryptoEngine = CryptoEngine();
      final audioCallService = AudioCallService(networkService, cryptoEngine);

      // Test complete call flow
      final recipientId = 'e2e_test_user';
      Call? currentCall;
      Call? incomingCall;

      audioCallService.onCallStatusChange = (call) {
        currentCall = call;
      };

      audioCallService.onIncomingCall = (call) {
        incomingCall = call;
      };

      // 1. Initiate call
      await audioCallService.initiateCall(recipientId);
      expect(currentCall, isNotNull);
      expect(currentCall!.status, CallStatus.connecting);

      // 2. Simulate receiving incoming call
      final callId = currentCall!.id;
      final offerPayload = {
        'call_id': callId,
        'offer': 'e2e_encrypted_offer',
        'from': recipientId,
      };

      audioCallService.testHandleOffer(offerPayload);
      expect(incomingCall, isNotNull);
      expect(incomingCall!.status, CallStatus.ringing);

      // 3. Accept call
      await audioCallService.acceptCall(callId, recipientId);

      // 4. Simulate answer
      final answerPayload = {
        'call_id': callId,
        'answer': 'e2e_encrypted_answer',
        'from': recipientId,
      };

      audioCallService.testHandleAnswer(answerPayload);

      // 5. Simulate connection established
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      // 6. Wait for call to establish
      await tester.pump(const Duration(seconds: 1));

      // 7. Verify call is connected
      expect(currentCall!.status, CallStatus.connected);

      // 8. Test call controls during active call
      await audioCallService.toggleMute();
      await audioCallService.toggleSpeakerphone();

      // 9. End call
      await audioCallService.endCall();

      // 10. Verify call ended
      expect(currentCall!.status, CallStatus.ended);
      expect(currentCall!.endTime, isNotNull);

      // Cleanup
      networkService.dispose();
    });

    testWidgets('Call recovery after network interruption',
        (WidgetTester tester) async {
      final networkService = NetworkService();
      final cryptoEngine = CryptoEngine();
      final audioCallService = AudioCallService(networkService, cryptoEngine);

      final recipientId = 'recovery_test_user';
      Call? currentCall;

      audioCallService.onCallStatusChange = (call) {
        currentCall = call;
      };

      // 1. Establish call
      await audioCallService.initiateCall(recipientId);

      final answerPayload = {
        'call_id': currentCall!.id,
        'answer': 'recovery_encrypted_answer',
        'from': recipientId,
      };

      audioCallService.testHandleAnswer(answerPayload);
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      expect(currentCall!.status, CallStatus.connected);

      // 2. Simulate network interruption
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateDisconnected);

      // 3. Verify call attempts to reconnect
      expect(currentCall!.status, CallStatus.connecting);

      // 4. Simulate successful reconnection
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      // 5. Verify call is restored
      expect(currentCall!.status, CallStatus.connected);

      // 6. End call
      await audioCallService.endCall();
      expect(currentCall!.status, CallStatus.ended);

      networkService.dispose();
    });

    testWidgets('Multiple call attempts and error recovery',
        (WidgetTester tester) async {
      final networkService = NetworkService();
      final cryptoEngine = CryptoEngine();
      final audioCallService = AudioCallService(networkService, cryptoEngine);

      final recipientId = 'error_recovery_test_user';
      final callAttempts = <Call>[];
      Call? currentCall;

      audioCallService.onCallStatusChange = (call) {
        currentCall = call;
        callAttempts.add(call);
      };

      // 1. First call attempt (fails)
      await audioCallService.initiateCall(recipientId);
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateFailed);

      // 2. Second call attempt (succeeds)
      await audioCallService.initiateCall(recipientId);

      final answerPayload = {
        'call_id': currentCall!.id,
        'answer': 'error_recovery_encrypted_answer',
        'from': recipientId,
      };

      audioCallService.testHandleAnswer(answerPayload);
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      // 3. Verify second attempt succeeds
      expect(currentCall!.status, CallStatus.connected);
      expect(callAttempts.length, greaterThanOrEqualTo(3)); // connecting -> failed -> connecting -> connected

      // 4. End successful call
      await audioCallService.endCall();
      expect(currentCall!.status, CallStatus.ended);

      networkService.dispose();
    });

    testWidgets('Call state persistence across service recreation',
        (WidgetTester tester) async {
      final networkService = NetworkService();
      final cryptoEngine = CryptoEngine();

      // Create first service instance
      final audioCallService1 = AudioCallService(networkService, cryptoEngine);
      final recipientId = 'persistence_test_user';

      // Start call
      await audioCallService1.initiateCall(recipientId);
      final originalCall = audioCallService1.currentCall;
      expect(originalCall, isNotNull);

      // Simulate connection
      final answerPayload = {
        'call_id': originalCall!.id,
        'answer': 'persistence_encrypted_answer',
        'from': recipientId,
      };

      audioCallService1.testHandleAnswer(answerPayload);
      audioCallService1.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      expect(originalCall.status, CallStatus.connected);

      // Create second service instance (simulating app restart)
      final audioCallService2 = AudioCallService(networkService, cryptoEngine);

      // Verify call state is not persisted (as expected for real-time calls)
      expect(audioCallService2.currentCall, isNull);

      // Cleanup
      audioCallService1.endCall();
      audioCallService2.endCall();
      networkService.dispose();
    });

    testWidgets('Call controls functionality during active call',
        (WidgetTester tester) async {
      final networkService = NetworkService();
      final cryptoEngine = CryptoEngine();
      final audioCallService = AudioCallService(networkService, cryptoEngine);

      final recipientId = 'controls_test_user';

      // Start and connect call
      await audioCallService.initiateCall(recipientId);

      final answerPayload = {
        'call_id': audioCallService.currentCall!.id,
        'answer': 'controls_encrypted_answer',
        'from': recipientId,
      };

      audioCallService.testHandleAnswer(answerPayload);
      audioCallService.testHandleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      // Test all controls during active call
      final initialMuteState = audioCallService.isMuted;
      await audioCallService.toggleMute();
      expect(audioCallService.isMuted, isNot(initialMuteState));

      await audioCallService.toggleSpeakerphone();
      final speakerEnabled = await audioCallService.isSpeakerphoneEnabled();
      expect(speakerEnabled, isA<bool>());

      // End call
      await audioCallService.endCall();
      expect(audioCallService.currentCall!.status, CallStatus.ended);

      networkService.dispose();
    });
  });
}