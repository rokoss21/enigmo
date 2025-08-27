import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'dart:async';
import 'package:enigmo_app/models/call.dart';
import 'package:enigmo_app/services/audio_call_service.dart';
import 'package:enigmo_app/services/network_service.dart';
import 'package:enigmo_app/services/crypto_engine.dart';
import 'package:enigmo_app/services/incoming_call_handler.dart';
import 'package:enigmo_app/widgets/call_controls.dart';
import 'package:enigmo_app/widgets/call_status_indicator.dart';

// Mock classes
class MockNetworkService extends Mock implements NetworkService {}
class MockCryptoEngine extends Mock implements CryptoEngine {}

void main() {
  group('Call End-to-End Tests', () {
    late AudioCallService audioCallService;
    late MockNetworkService mockNetworkService;
    late MockCryptoEngine mockCryptoEngine;
    late IncomingCallHandler incomingCallHandler;

    setUp(() {
      mockNetworkService = MockNetworkService();
      mockCryptoEngine = MockCryptoEngine();
      audioCallService = AudioCallService(mockNetworkService, mockCryptoEngine);
      incomingCallHandler = IncomingCallHandler(audioCallService: audioCallService);
    });

    tearDown(() {
      audioCallService.endCall();
    });

    test('Full call lifecycle: UI interaction simulation', () async {
      // Arrange
      final callerId = 'user_alice';
      final calleeId = 'user_bob';
      final callId = 'call_001';

      final events = <String>[];
      Call? currentCallState;

      // Setup event tracking
      audioCallService.onCallStatusChange = (call) {
        currentCallState = call;
        events.add('call_status_changed:${call.status}');
      };

      audioCallService.onIncomingCall = (call) {
        events.add('incoming_call:${call.id}');
      };

      // Act & Assert - Step 1: User initiates call
      events.add('user_initiates_call');
      await audioCallService.initiateCall(calleeId);

      expect(currentCallState, isNotNull);
      expect(currentCallState!.status, CallStatus.connecting);
      expect(events.contains('call_status_changed:connecting'), true);

      // Step 2: Network sends offer to callee
      events.add('network_sends_offer');
      final offerPayload = {
        'call_id': callId,
        'offer': 'encrypted_offer_sdp',
        'from': callerId,
      };
      audioCallService._handleOffer(offerPayload);

      expect(events.contains('incoming_call:$callId'), true);

      // Step 3: Callee accepts call (UI interaction)
      events.add('callee_accepts_call');
      await audioCallService.acceptCall(callId, callerId);

      // Step 4: Network sends answer back
      events.add('network_sends_answer');
      final answerPayload = {
        'call_id': callId,
        'answer': 'encrypted_answer_sdp',
        'from': callerId,
      };
      audioCallService._handleAnswer(answerPayload);

      expect(currentCallState!.status, CallStatus.connected);
      expect(events.contains('call_status_changed:connected'), true);

      // Step 5: ICE candidates are exchanged
      events.add('ice_candidates_exchange');
      final candidatePayload = {
        'candidate': 'candidate:1 1 UDP 2122260223 192.168.1.1 5000 typ host',
        'call_id': callId,
        'from': callerId,
      };
      audioCallService._handleCandidate(candidatePayload);

      // Step 6: Call is connected and active
      audioCallService._handleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      // Step 7: Users interact with call controls
      events.add('user_toggles_mute');
      await audioCallService.toggleMute();

      events.add('user_toggles_speaker');
      await audioCallService.toggleSpeakerphone();

      // Step 8: Call ends
      events.add('user_ends_call');
      await audioCallService.endCall();

      expect(currentCallState!.status, CallStatus.ended);
      expect(events.contains('call_status_changed:ended'), true);
      expect(audioCallService.currentCall, isNull);

      // Verify complete event sequence
      expect(events.length, greaterThanOrEqualTo(8));
      expect(events.first, 'user_initiates_call');
      expect(events.last, 'user_ends_call');
    });

    test('Call rejection scenario end-to-end', () async {
      // Arrange
      final callerId = 'user_alice';
      final calleeId = 'user_bob';
      final callId = 'call_reject_001';

      final events = <String>[];
      Call? currentCallState;

      audioCallService.onCallStatusChange = (call) {
        currentCallState = call;
        events.add('call_status_changed:${call.status}');
      };

      audioCallService.onIncomingCall = (call) {
        events.add('incoming_call:${call.id}');
      };

      // Act - Step 1: Call is initiated
      await audioCallService.initiateCall(calleeId);

      // Step 2: Incoming call is received
      final offerPayload = {
        'call_id': callId,
        'offer': 'encrypted_offer_sdp',
        'from': callerId,
      };
      audioCallService._handleOffer(offerPayload);

      expect(events.contains('incoming_call:$callId'), true);

      // Step 3: Callee rejects the call
      events.add('callee_rejects_call');
      await audioCallService.endCall(); // Reject by ending call

      // Assert
      expect(currentCallState!.status, CallStatus.ended);
      expect(events.contains('call_status_changed:ended'), true);
      expect(audioCallService.currentCall, isNull);
    });

    test('Network interruption and recovery during call', () async {
      // Arrange
      final callerId = 'user_alice';
      final calleeId = 'user_bob';
      final callId = 'call_network_001';

      final events = <String>[];
      Call? currentCallState;

      audioCallService.onCallStatusChange = (call) {
        currentCallState = call;
        events.add('call_status_changed:${call.status}');
      };

      // Act - Establish call
      await audioCallService.initiateCall(calleeId);

      final answerPayload = {
        'call_id': audioCallService.currentCall!.id,
        'answer': 'encrypted_answer_sdp',
        'from': callerId,
      };
      audioCallService._handleAnswer(answerPayload);
      audioCallService._handleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      expect(currentCallState!.status, CallStatus.connected);

      // Step 2: Network interruption occurs
      events.add('network_interruption');
      audioCallService._handleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateDisconnected);

      // Step 3: System attempts reconnection
      events.add('reconnection_attempt');
      await audioCallService._attemptReconnection();

      // Step 4: Network recovers
      events.add('network_recovery');
      audioCallService._handleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      // Assert
      expect(currentCallState!.status, CallStatus.connected);
      expect(events.contains('network_interruption'), true);
      expect(events.contains('reconnection_attempt'), true);
      expect(events.contains('network_recovery'), true);
    });

    test('Multiple call attempts and busy state handling', () async {
      // Arrange
      final callerId1 = 'user_alice';
      final callerId2 = 'user_charlie';
      final calleeId = 'user_bob';

      final events = <String>[];
      Call? currentCallState;

      audioCallService.onCallStatusChange = (call) {
        currentCallState = call;
        events.add('call_status_changed:${call.status}');
      };

      audioCallService.onIncomingCall = (call) {
        events.add('incoming_call:${call.id}');
      };

      // Act - First call
      await audioCallService.initiateCall(calleeId);
      expect(currentCallState!.status, CallStatus.connecting);

      // Second call attempt (should be handled gracefully)
      final secondCallId = 'call_second_001';
      final offerPayload2 = {
        'call_id': secondCallId,
        'offer': 'encrypted_offer_sdp_2',
        'from': callerId2,
      };

      // In current implementation, this would create a new call
      // but we test that the system handles it
      audioCallService._handleOffer(offerPayload2);

      // Assert
      expect(events.contains('incoming_call:$secondCallId'), true);
      // Current implementation allows multiple calls, but this test documents the behavior
    });

    test('Call with audio controls end-to-end', () async {
      // Arrange
      final calleeId = 'user_bob';

      await audioCallService.initiateCall(calleeId);

      // Establish connection
      final answerPayload = {
        'call_id': audioCallService.currentCall!.id,
        'answer': 'encrypted_answer_sdp',
        'from': calleeId,
      };
      audioCallService._handleAnswer(answerPayload);
      audioCallService._handleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      // Act - Test all audio controls
      final initialMuteState = audioCallService.isMuted;

      await audioCallService.toggleMute();
      expect(audioCallService.isMuted, !initialMuteState);

      await audioCallService.toggleMute(); // Toggle back
      expect(audioCallService.isMuted, initialMuteState);

      await audioCallService.toggleSpeakerphone();
      await audioCallService.setCallAudioMode();

      // End call with audio reset
      await audioCallService.endCall();

      // Assert
      expect(audioCallService.currentCall, isNull);
    });

    test('Call duration and timing end-to-end', () async {
      // Arrange
      final calleeId = 'user_bob';
      final callDuration = const Duration(seconds: 5);

      await audioCallService.initiateCall(calleeId);
      final callStartTime = audioCallService.currentCall!.startTime;

      // Establish connection
      final answerPayload = {
        'call_id': audioCallService.currentCall!.id,
        'answer': 'encrypted_answer_sdp',
        'from': calleeId,
      };
      audioCallService._handleAnswer(answerPayload);
      audioCallService._handleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      // Act - Wait for call duration
      await Future.delayed(callDuration);

      final callEndTime = DateTime.now();
      await audioCallService.endCall();

      // Assert
      final actualDuration = callEndTime.difference(callStartTime);
      expect(actualDuration.inSeconds, greaterThanOrEqualTo(callDuration.inSeconds - 1));
      expect(audioCallService.currentCall!.endTime, isNotNull);
    });

    test('Error scenarios end-to-end', () async {
      // Arrange
      final calleeId = 'user_bob';
      final events = <String>[];
      Call? currentCallState;

      audioCallService.onCallStatusChange = (call) {
        currentCallState = call;
        events.add('call_status_changed:${call.status}');
      };

      // Act - Test various error scenarios

      // 1. Connection failure during setup
      await audioCallService.initiateCall(calleeId);
      audioCallService._handleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateFailed);
      expect(currentCallState!.status, CallStatus.ended);

      // 2. Network error during call
      await audioCallService.initiateCall(calleeId);
      final answerPayload = {
        'call_id': audioCallService.currentCall!.id,
        'answer': 'encrypted_answer_sdp',
        'from': calleeId,
      };
      audioCallService._handleAnswer(answerPayload);
      audioCallService._handleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      // Simulate network error
      audioCallService._handleConnectionFailed();
      expect(currentCallState!.status, CallStatus.ended);

      // Assert
      expect(events.where((event) => event.contains('ended')).length, greaterThanOrEqualTo(2));
    });

    test('Resource cleanup end-to-end', () async {
      // Arrange
      final calleeId = 'user_bob';

      // Act - Create and destroy multiple calls
      for (int i = 0; i < 3; i++) {
        await audioCallService.initiateCall('$calleeId$i');

        // Establish connection
        final answerPayload = {
          'call_id': audioCallService.currentCall!.id,
          'answer': 'encrypted_answer_sdp',
          'from': '$calleeId$i',
        };
        audioCallService._handleAnswer(answerPayload);
        audioCallService._handleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

        // End call
        await audioCallService.endCall();

        // Assert cleanup
        expect(audioCallService.currentCall, isNull);
      }
    });

    test('Call state persistence across app lifecycle', () async {
      // Arrange
      final calleeId = 'user_bob';

      // Act - Simulate app background/foreground
      await audioCallService.initiateCall(calleeId);

      final originalCallId = audioCallService.currentCall!.id;

      // Establish connection
      final answerPayload = {
        'call_id': originalCallId,
        'answer': 'encrypted_answer_sdp',
        'from': calleeId,
      };
      audioCallService._handleAnswer(answerPayload);
      audioCallService._handleConnectionStateChange(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      // Simulate app going to background and back
      await audioCallService.setUserStatus(isActive: false);
      await audioCallService.setUserStatus(isActive: true);

      // Assert call persists
      expect(audioCallService.currentCall, isNotNull);
      expect(audioCallService.currentCall!.id, originalCallId);
      expect(audioCallService.currentCall!.status, CallStatus.connected);
    });
  });
}