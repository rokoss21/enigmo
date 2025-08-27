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

  group('WebRTC Integration Tests', () {
    late AudioCallService audioCallService;
    late NetworkService networkService;
    late CryptoEngine cryptoEngine;

    setUp(() async {
      networkService = NetworkService();
      cryptoEngine = CryptoEngine();
      audioCallService = AudioCallService(networkService, cryptoEngine);

      // Initialize network connection
      final connected = await networkService.connect();
      expect(connected, true);

      // Register user for testing
      final userId = await networkService.registerUser(nickname: 'TestUser');
      expect(userId, isNotNull);

      final authenticated = await networkService.authenticate();
      expect(authenticated, true);
    });

    tearDown(() {
      audioCallService.endCall();
      networkService.dispose();
    });

    testWidgets('Complete call flow: initiate -> accept -> connect -> end',
        (WidgetTester tester) async {
      // This test requires two clients, so we'll simulate the flow
      final recipientId = 'test_recipient_123';
      Call? currentCall;
      Call? incomingCall;

      // Setup call status listener
      audioCallService.onCallStatusChange = (call) {
        currentCall = call;
      };

      audioCallService.onIncomingCall = (call) {
        incomingCall = call;
      };

      // Test 1: Initiate call
      await audioCallService.initiateCall(recipientId);

      // Verify call was initiated
      expect(currentCall, isNotNull);
      expect(currentCall!.status, CallStatus.connecting);
      expect(currentCall!.recipientId, recipientId);
      expect(currentCall!.isOutgoing, true);

      // Test 2: Simulate incoming call (in real scenario this would come from server)
      final callId = currentCall!.id;
      final callerPayload = {
        'call_id': callId,
        'offer': 'simulated_encrypted_offer',
        'from': recipientId,
      };

      // Simulate receiving offer
      audioCallService.testHandleOffer(callerPayload);

      // Verify incoming call was processed
      expect(incomingCall, isNotNull);
      expect(incomingCall!.status, CallStatus.ringing);
      expect(incomingCall!.recipientId, recipientId);
      expect(incomingCall!.isOutgoing, false);

      // Test 3: Accept call
      await audioCallService.acceptCall(callId, recipientId);

      // Verify call status changed
      expect(currentCall!.status, CallStatus.connecting);

      // Test 4: Simulate answer from recipient
      final answerPayload = {
        'call_id': callId,
        'answer': 'simulated_encrypted_answer',
        'from': recipientId,
      };

      audioCallService.testHandleAnswer(answerPayload);

      // In test environment, WebRTC won't actually connect, but we can verify the flow
      expect(currentCall!.status, CallStatus.connecting); // Would be connected in real WebRTC

      // Test 5: End call
      await audioCallService.endCall();

      // Verify call was ended
      expect(currentCall!.status, CallStatus.ended);
      expect(currentCall!.endTime, isNotNull);
    });

    testWidgets('Call state persistence across app restart simulation',
        (WidgetTester tester) async {
      // This test simulates app restart by creating new service instance
      final recipientId = 'test_recipient_456';

      // Initiate call
      await audioCallService.initiateCall(recipientId);
      final originalCall = audioCallService.currentCall;
      expect(originalCall, isNotNull);

      // Simulate app restart by creating new service instance
      final newAudioCallService = AudioCallService(networkService, cryptoEngine);

      // Verify call state is not persisted (as expected for voice calls)
      expect(newAudioCallService.currentCall, isNull);

      // Clean up
      newAudioCallService.endCall();
    });

    testWidgets('Multiple call attempts handling', (WidgetTester tester) async {
      final recipientId = 'test_recipient_789';
      final callStatuses = <CallStatus>[];

      audioCallService.onCallStatusChange = (call) {
        callStatuses.add(call.status);
      };

      // Attempt multiple calls rapidly
      await audioCallService.initiateCall(recipientId);
      await audioCallService.initiateCall(recipientId); // Second attempt
      await audioCallService.endCall();

      // Verify only one call was active
      expect(callStatuses.where((status) => status == CallStatus.connecting).length, 1);
    });

    testWidgets('Call controls integration', (WidgetTester tester) async {
      final recipientId = 'test_recipient_control';

      // Start call
      await audioCallService.initiateCall(recipientId);

      // Test mute toggle
      final initialMuteState = audioCallService.isMuted;
      await audioCallService.toggleMute();
      expect(audioCallService.isMuted, isNot(initialMuteState));

      // Test speaker toggle (in test environment this is no-op)
      await audioCallService.toggleSpeakerphone();
      await audioCallService.isSpeakerphoneEnabled();

      // End call
      await audioCallService.endCall();
    });
  });
}