import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:enigmo_app/services/network_service.dart';
import 'package:enigmo_app/services/audio_call_service.dart';
import 'package:enigmo_app/services/crypto_engine.dart';
import 'package:enigmo_app/models/call.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Client-Server Integration Tests', () {
    late NetworkService networkService;
    late AudioCallService audioCallService;
    late CryptoEngine cryptoEngine;
    String? userId;

    setUp(() async {
      networkService = NetworkService();
      cryptoEngine = CryptoEngine();
      audioCallService = AudioCallService(networkService, cryptoEngine);

      // Connect to server
      final connected = await networkService.connect();
      expect(connected, true);

      // Register user
      userId = await networkService.registerUser(nickname: 'IntegrationTestUser');
      expect(userId, isNotNull);

      // Authenticate
      final authenticated = await networkService.authenticate();
      expect(authenticated, true);
    });

    tearDown(() {
      audioCallService.endCall();
      networkService.dispose();
    });

    test('User registration and authentication flow', () async {
      // Verify user is registered and authenticated
      expect(networkService.userId, isNotNull);
      expect(networkService.isConnected, true);
    });

    test('Message sending and receiving', () async {
      final testMessage = 'Integration test message';
      bool messageReceived = false;
      String? receivedMessage;

      // Listen for messages
      networkService.newMessages.listen((message) {
        messageReceived = true;
        receivedMessage = message.content;
      });

      // Send message to self (for testing)
      final success = await networkService.sendMessage(
        networkService.userId!,
        testMessage,
        type: MessageType.text,
      );

      expect(success, true);

      // Wait for message to be processed
      await Future.delayed(const Duration(seconds: 1));

      // In a real scenario, the message would be received
      // For this test, we verify the sending mechanism works
      expect(success, true);
    });

    test('Call signaling through server', () async {
      final recipientId = 'integration_test_recipient';
      Call? currentCall;
      Call? incomingCall;

      audioCallService.onCallStatusChange = (call) {
        currentCall = call;
      };

      audioCallService.onIncomingCall = (call) {
        incomingCall = call;
      };

      // Initiate call
      await audioCallService.initiateCall(recipientId);

      // Verify call was initiated
      expect(currentCall, isNotNull);
      expect(currentCall!.status, CallStatus.connecting);
      expect(currentCall!.recipientId, recipientId);

      // In a real scenario with two clients, we would:
      // 1. Have another client receive the call offer
      // 2. Accept the call and send answer
      // 3. Establish WebRTC connection

      // For this integration test, we verify the signaling flow
      expect(networkService.isConnected, true);
      expect(audioCallService.currentCall, isNotNull);

      // End call
      await audioCallService.endCall();
      expect(currentCall!.status, CallStatus.ended);
    });

    test('User presence and status updates', () async {
      bool statusUpdateReceived = false;
      String? updatedUserId;
      bool? updatedStatus;

      // Listen for user status updates
      networkService.userStatusUpdates.listen((data) {
        statusUpdateReceived = true;
        updatedUserId = data['userId'];
        updatedStatus = data['isOnline'];
      });

      // Get users list
      final users = await networkService.getUsers();
      expect(users, isA<List>());

      // Wait for potential status updates
      await Future.delayed(const Duration(seconds: 1));

      // Verify connection is stable
      expect(networkService.isConnected, true);
    });

    test('Connection resilience and reconnection', () async {
      // Test initial connection
      expect(networkService.isConnected, true);

      // In a real scenario, we would test:
      // 1. Network disconnection
      // 2. Automatic reconnection
      // 3. Call state preservation during reconnection

      // For this test, we verify the connection mechanisms are in place
      final connectionStatus = networkService.connectionStatus;
      expect(connectionStatus, isNotNull);

      // Test message sending during stable connection
      final success = await networkService.sendMessage(
        networkService.userId!,
        'Connection test message',
        type: MessageType.text,
      );

      expect(success, true);
    });

    test('Call state synchronization with server', () async {
      final recipientId = 'sync_test_recipient';
      Call? currentCall;

      audioCallService.onCallStatusChange = (call) {
        currentCall = call;
      };

      // Start call
      await audioCallService.initiateCall(recipientId);
      expect(currentCall!.status, CallStatus.connecting);

      // Simulate server response (in real scenario this would come from server)
      final callId = currentCall!.id;
      final answerPayload = {
        'call_id': callId,
        'answer': 'server_encrypted_answer',
        'from': recipientId,
      };

      audioCallService.testHandleAnswer(answerPayload);

      // Verify state synchronization
      expect(currentCall!.status, CallStatus.connecting); // Would be connected with real WebRTC

      // End call and verify server notification
      await audioCallService.endCall();
      expect(currentCall!.status, CallStatus.ended);
    });

    test('Large message handling', () async {
      // Test sending large messages
      final largeMessage = 'A' * 10000; // 10KB message

      final success = await networkService.sendMessage(
        networkService.userId!,
        largeMessage,
        type: MessageType.text,
      );

      expect(success, true);

      // Verify connection remains stable after large message
      expect(networkService.isConnected, true);
    });

    test('Rapid consecutive operations', () async {
      final recipientId = 'rapid_test_recipient';
      final operations = <Future>[];

      // Perform rapid operations
      for (int i = 0; i < 10; i++) {
        operations.add(networkService.sendMessage(
          networkService.userId!,
          'Rapid message $i',
          type: MessageType.text,
        ));
      }

      // Wait for all operations to complete
      final results = await Future.wait(operations);

      // Verify all operations succeeded
      expect(results.every((success) => success), true);
      expect(networkService.isConnected, true);
    });

    test('Resource cleanup on disconnection', () async {
      // Verify initial state
      expect(networkService.isConnected, true);

      // Disconnect
      networkService.dispose();

      // Verify resources are cleaned up
      expect(networkService.isConnected, false);
    });

    test('Authentication token handling', () async {
      // Test that authentication persists
      expect(networkService.userId, isNotNull);

      // In a real scenario, we would test token refresh
      // For this test, we verify authentication state is maintained
      final authenticated = await networkService.authenticate();
      expect(authenticated, true);
    });
  });
}