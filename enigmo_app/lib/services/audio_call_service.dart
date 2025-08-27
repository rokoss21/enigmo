import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:enigmo_app/services/network_service.dart';
import 'package:enigmo_app/services/crypto_engine.dart';
import 'package:enigmo_app/services/audio_manager_service.dart';
import 'package:enigmo_app/models/call.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'dart:async';

class AudioCallService {
  final NetworkService _networkService;
  final CryptoEngine _cryptoEngine;
  
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  Call? _currentCall;
  
  // Callbacks for UI updates
  Function(Call)? onIncomingCall;
  Function(Call)? onCallStatusChange;
  
  AudioCallService(this._networkService, this._cryptoEngine) {
    _setupSignalingListeners();
  }
  
  void _setupSignalingListeners() {
    // Listen for incoming call signals
    _networkService.onMessage('call_offer', _handleOffer);
    _networkService.onMessage('call_answer', _handleAnswer);
    _networkService.onMessage('call_candidate', _handleCandidate);
    _networkService.onMessage('call_end', _handleCallEnd);
    _networkService.onMessage('call_restart', _handleRestart);
    _networkService.onMessage('call_restart_answer', _handleRestartAnswer);
  }
  
  Future<void> initiateCall(String recipientId) async {
    try {
      print('DEBUG AudioCallService.initiateCall: Starting call to $recipientId');

      // Generate unique call ID
      final callId = _generateCallId();
      print('DEBUG AudioCallService.initiateCall: Generated callId: $callId');

      _currentCall = Call(
        id: callId,
        recipientId: recipientId,
        status: CallStatus.connecting,
        isOutgoing: true,
        startTime: DateTime.now(),
      );

      // Notify UI of call status change
      onCallStatusChange?.call(_currentCall!);
      print('DEBUG AudioCallService.initiateCall: Call status updated to connecting');

      // Set audio mode for call
      await setCallAudioMode();
      print('DEBUG AudioCallService.initiateCall: Audio mode set');

      // Create local media stream (audio only)
      print('DEBUG AudioCallService.initiateCall: Getting user media...');
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': false,
        });
        print('DEBUG AudioCallService.initiateCall: Local stream created successfully');
      } catch (e) {
        print('ERROR AudioCallService.initiateCall: Failed to get user media: $e');
        // Check if it's a permission error
        if (e.toString().contains('permission') || e.toString().contains('denied')) {
          print('ERROR AudioCallService.initiateCall: Microphone permission denied. Please allow microphone access.');
        }
        rethrow;
      }

      // Create peer connection
      print('DEBUG AudioCallService.initiateCall: Creating peer connection...');
      _peerConnection = await _createPeerConnection();
      print('DEBUG AudioCallService.initiateCall: Peer connection created');

      // Add local stream to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
      print('DEBUG AudioCallService.initiateCall: Local tracks added to peer connection');

      // Create offer
      print('DEBUG AudioCallService.initiateCall: Creating offer...');
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      print('DEBUG AudioCallService.initiateCall: Offer created and set as local description');

      // Send encrypted offer to recipient
      print('DEBUG AudioCallService.initiateCall: Encrypting offer...');
      final encryptedOffer = await CryptoEngine.encrypt(offer.sdp!);
      print('DEBUG AudioCallService.initiateCall: Sending call_initiate message...');
      _networkService.send('call_initiate', {
        'to': recipientId,
        'offer': encryptedOffer,
        'call_id': callId,
      });
      print('DEBUG AudioCallService.initiateCall: Call initiation message sent successfully');
      logCallState();
    } catch (e) {
      // Handle error
      print('ERROR AudioCallService.initiateCall: Failed to initiate call: $e');
      logCallState();
    }
  }

  
  Future<void> acceptCall(String callId, String callerId) async {
    try {
      _currentCall = Call(
        id: callId,
        recipientId: callerId,
        status: CallStatus.connecting,
        isOutgoing: false,
        startTime: DateTime.now(),
      );

      // Notify UI of call status change
      onCallStatusChange?.call(_currentCall!);

      // Set audio mode for call
      await setCallAudioMode();

      // Create local media stream
      print('DEBUG AudioCallService.acceptCall: Getting user media...');
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': false,
        });
        print('DEBUG AudioCallService.acceptCall: Local stream created successfully');
      } catch (e) {
        print('ERROR AudioCallService.acceptCall: Failed to get user media: $e');
        if (e.toString().contains('permission') || e.toString().contains('denied')) {
          print('ERROR AudioCallService.acceptCall: Microphone permission denied. Please allow microphone access.');
        }
        rethrow;
      }

      // Create peer connection
      _peerConnection = await _createPeerConnection();

      // Add local stream to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });
    } catch (e) {
      print('Failed to accept call: $e');
    }
  }
  
  Future<RTCPeerConnection> _createPeerConnection() async {
    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        // Production TURN servers
        {
          'urls': 'turn:193.233.206.172:3478',
          'username': 'enigmo',
          'credential': 'enigmo123'
        },
        {
          'urls': 'turn:193.233.206.172:5349',
          'username': 'enigmo',
          'credential': 'enigmo123'
        }
      ],
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'sdpSemantics': 'unified-plan',
      if (kIsWeb) 'encodedInsertableStreams': true,
    };

    final peerConnection = await createPeerConnection(configuration);
    
    // Handle ICE candidates
    peerConnection.onIceCandidate = (candidate) async {
      if (candidate == null) return;
      
      final encryptedCandidate = await CryptoEngine.encrypt(candidate.candidate!);
      _networkService.send('call_candidate', {
        'to': _currentCall!.recipientId,
        'candidate': encryptedCandidate,
        'call_id': _currentCall!.id,
      });
    };
    
    // Handle remote stream
    peerConnection.onAddStream = (stream) {
      _remoteStream = stream;
    };

    // Handle connection state changes
    peerConnection.onConnectionState = (state) {
      print('WebRTC Connection state changed: $state');
      _handleConnectionStateChange(state);
    };

    // Handle ICE connection state changes
    peerConnection.onIceConnectionState = (state) {
      print('ICE Connection state changed: $state');
      _handleIceConnectionStateChange(state);
    };

    // Handle ICE gathering state changes
    peerConnection.onIceGatheringState = (state) {
      print('ICE Gathering state changed: $state');
    };

    // Handle signaling state changes
    peerConnection.onSignalingState = (state) {
      print('Signaling state changed: $state');
    };

    // Handle signaling state changes
    peerConnection.onSignalingState = (state) {
      print('Signaling state changed: $state');
    };

    // Handle track events
    peerConnection.onTrack = (event) {
      print('Received remote track: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
      }
    };

    return peerConnection;
  }
  
  void _handleOffer(Map<String, dynamic> payload) async {
    try {
      print('DEBUG AudioCallService._handleOffer: Received call offer');
      final callId = payload['call_id'] as String;
      final callerId = payload['from'] as String;
      print('DEBUG AudioCallService._handleOffer: callId=$callId, callerId=$callerId');

      // Create incoming call object
      final incomingCall = Call(
        id: callId,
        recipientId: callerId,
        status: CallStatus.ringing,
        isOutgoing: false,
        startTime: DateTime.now(),
      );

      print('DEBUG AudioCallService._handleOffer: Created incoming call object');
      // Notify UI of incoming call
      onIncomingCall?.call(incomingCall);
      print('DEBUG AudioCallService._handleOffer: Notified UI of incoming call');

      // Decrypt and set offer
      print('DEBUG AudioCallService._handleOffer: Handling remote description...');
      await _handleRemoteDescription(payload, 'offer');
      print('DEBUG AudioCallService._handleOffer: Remote description handled successfully');
    } catch (e) {
      print('ERROR AudioCallService._handleOffer: Failed to handle offer: $e');
    }
  }
  
  void _handleAnswer(Map<String, dynamic> payload) async {
    await _handleRemoteDescription(payload, 'answer');
  }

  Future<void> _handleRemoteDescription(Map<String, dynamic> payload, String type) async {
    try {
      final sdpKey = type == 'answer' ? 'answer' : 'offer';
      final sdp = await CryptoEngine.decrypt(payload[sdpKey]);
      final description = RTCSessionDescription(sdp, type);
      await _peerConnection?.setRemoteDescription(description);

      // Update call status to connected when answer is received
      if (type == 'answer' && _currentCall != null) {
        _currentCall = _currentCall!.copyWith(status: CallStatus.connected);
        onCallStatusChange?.call(_currentCall!);
      }
    } catch (e) {
      print('Failed to handle $type: $e');
    }
  }
  
  void _handleCandidate(Map<String, dynamic> payload) async {
    // Handle ICE candidate from peer
    final candidateStr = await CryptoEngine.decrypt(payload['candidate']);
    final candidate = RTCIceCandidate(candidateStr, '', 0);
    await _peerConnection?.addCandidate(candidate);
  }
  
  Future<void> endCall() async {
    try {
      // Cancel reconnection timer
      _reconnectionTimer?.cancel();
      _reconnectionTimer = null;
      _reconnectionAttempts = 0;

      // Close peer connection
      await _peerConnection?.close();
      _peerConnection = null;

      // Stop local stream tracks
      _localStream?.getTracks().forEach((track) async {
        await track.stop();
      });
      await _localStream?.dispose();

      // Reset audio mode
      await resetAudioMode();

      // Notify peer if we have a current call
      if (_currentCall != null) {
        _networkService.send('call_end', {
          'to': _currentCall!.recipientId,
          'call_id': _currentCall!.id,
        });

        _currentCall = _currentCall!.copyWith(
          status: CallStatus.ended,
          endTime: DateTime.now(),
        );

        // Notify UI of call status change
        onCallStatusChange?.call(_currentCall!);
      }
    } catch (e) {
      print('Error ending call: $e');
    }
  }

  void _handleRestart(Map<String, dynamic> payload) async {
    try {
      print('Received call restart offer');
      final offerSdp = await CryptoEngine.decrypt(payload['offer']);
      final offer = RTCSessionDescription(offerSdp, 'offer');
      await _peerConnection?.setRemoteDescription(offer);

      // Create and send answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      final encryptedAnswer = await CryptoEngine.encrypt(answer.sdp!);
      _networkService.send('call_restart_answer', {
        'to': _currentCall!.recipientId,
        'answer': encryptedAnswer,
        'call_id': _currentCall!.id,
      });

      // Reset reconnection attempts on successful restart
      _reconnectionAttempts = 0;
    } catch (e) {
      print('Failed to handle restart: $e');
    }
  }

  void _handleRestartAnswer(Map<String, dynamic> payload) async {
    try {
      print('Received call restart answer');
      await _handleRemoteDescription(payload, 'answer');
      // Reset reconnection attempts on successful restart
      _reconnectionAttempts = 0;
    } catch (e) {
      print('Failed to handle restart answer: $e');
    }
  }

  void _handleCallEnd(Map<String, dynamic> payload) async {
    // Close peer connection
    await _peerConnection?.close();
    _peerConnection = null;

    // Stop local stream tracks
    _localStream?.getTracks().forEach((track) async {
      await track.stop();
    });
    await _localStream?.dispose();

    // Reset audio mode
    await resetAudioMode();

    // Update call status to ended
    if (_currentCall != null) {
      _currentCall = _currentCall!.copyWith(
        status: CallStatus.ended,
        endTime: DateTime.now(),
      );
      onCallStatusChange?.call(_currentCall!);
    }
  }
  
  // Toggle mute state
  Future<void> toggleMute() async {
    final audioTrack = _localStream?.getAudioTracks().first;
    if (audioTrack != null) {
      audioTrack.enabled = !audioTrack.enabled;
    }
  }

  // Check if call is muted
  bool get isMuted {
    final audioTrack = _localStream?.getAudioTracks().first;
    return audioTrack == null || audioTrack.enabled == false;
  }
  
  // Get current call state
  Call? get currentCall => _currentCall;
  
  // Get local stream for UI
  MediaStream? get localStream => _localStream;
  
  // Get remote stream for UI
  MediaStream? get remoteStream => _remoteStream;
  
  // Generate unique call ID
  String _generateCallId() {
    final random = Random();
    return '${DateTime.now().millisecondsSinceEpoch}_${random.nextInt(10000)}';
  }

  // Check microphone permissions
  Future<bool> checkMicrophonePermission() async {
    try {
      if (kIsWeb) {
        // On web, try to get user media to check permissions
        final testStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
        // Immediately stop the test stream
        testStream.getTracks().forEach((track) => track.stop());
        return true;
      } else {
        // On mobile, permissions are handled by the platform
        return true;
      }
    } catch (e) {
      print('DEBUG AudioCallService.checkMicrophonePermission: Permission check failed: $e');
      return false;
    }
  }

  // Get WebRTC connection statistics for debugging
  Future<Map<String, dynamic>> getConnectionStats() async {
    if (_peerConnection == null) {
      return {'error': 'No active peer connection'};
    }

    try {
      final stats = await _peerConnection!.getStats();
      final statsMap = <String, dynamic>{};

      stats.forEach((report) {
        statsMap[report.id] = {
          'type': report.type,
          'timestamp': report.timestamp,
          'values': report.values,
        };
      });

      return statsMap;
    } catch (e) {
      print('ERROR AudioCallService.getConnectionStats: $e');
      return {'error': e.toString()};
    }
  }

  // Log current call state for debugging
  void logCallState() {
    print('=== CALL STATE DEBUG ===');
    print('Current call: $_currentCall');
    print('Peer connection: ${_peerConnection != null ? 'active' : 'null'}');
    print('Local stream: ${_localStream != null ? 'active' : 'null'}');
    print('Remote stream: ${_remoteStream != null ? 'active' : 'null'}');
    print('Is muted: $isMuted');
    print('Reconnection attempts: $_reconnectionAttempts');
    print('=======================');
  }


  // Handle WebRTC connection state changes
  void _handleConnectionStateChange(RTCPeerConnectionState state) {
    print('DEBUG AudioCallService._handleConnectionStateChange: $state');
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        if (_currentCall != null && _currentCall!.status != CallStatus.connected) {
          _currentCall = _currentCall!.copyWith(status: CallStatus.connecting);
          onCallStatusChange?.call(_currentCall!);
        }
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        if (_currentCall != null) {
          _currentCall = _currentCall!.copyWith(status: CallStatus.connected);
          onCallStatusChange?.call(_currentCall!);
          print('DEBUG AudioCallService: Call successfully connected!');
        }
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        print('DEBUG AudioCallService: Connection lost, attempting to reconnect...');
        if (_currentCall != null) {
          _currentCall = _currentCall!.copyWith(status: CallStatus.connecting);
          onCallStatusChange?.call(_currentCall!);
        }
        // Try to reconnect instead of immediately ending
        _handleConnectionLost();
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        print('DEBUG AudioCallService: Connection failed');
        if (_currentCall != null) {
          _currentCall = _currentCall!.copyWith(status: CallStatus.ended);
          onCallStatusChange?.call(_currentCall!);
        }
        endCall();
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        print('DEBUG AudioCallService: Connection closed');
        if (_currentCall != null) {
          _currentCall = _currentCall!.copyWith(status: CallStatus.ended);
          onCallStatusChange?.call(_currentCall!);
        }
        break;
      default:
        print('DEBUG AudioCallService: Unknown connection state: $state');
        break;
    }
  }

  // Handle ICE connection state changes
  void _handleIceConnectionStateChange(RTCIceConnectionState state) {
    print('DEBUG AudioCallService._handleIceConnectionStateChange: $state');
    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateNew:
        print('DEBUG AudioCallService: ICE connection initialized');
        break;
      case RTCIceConnectionState.RTCIceConnectionStateChecking:
        print('DEBUG AudioCallService: ICE connection checking...');
        if (_currentCall != null && _currentCall!.status != CallStatus.connected) {
          _currentCall = _currentCall!.copyWith(status: CallStatus.connecting);
          onCallStatusChange?.call(_currentCall!);
        }
        break;
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
        print('DEBUG AudioCallService: ICE connection established!');
        if (_currentCall != null) {
          _currentCall = _currentCall!.copyWith(status: CallStatus.connected);
          onCallStatusChange?.call(_currentCall!);
        }
        // Reset reconnection attempts on successful connection
        _reconnectionAttempts = 0;
        break;
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        print('DEBUG AudioCallService: ICE connection completed');
        if (_currentCall != null && _currentCall!.status != CallStatus.connected) {
          _currentCall = _currentCall!.copyWith(status: CallStatus.connected);
          onCallStatusChange?.call(_currentCall!);
        }
        _reconnectionAttempts = 0;
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        print('DEBUG AudioCallService: ICE connection lost, attempting to reconnect...');
        if (_currentCall != null) {
          _currentCall = _currentCall!.copyWith(status: CallStatus.connecting);
          onCallStatusChange?.call(_currentCall!);
        }
        _handleConnectionLost();
        break;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        print('DEBUG AudioCallService: ICE connection failed');
        if (_currentCall != null) {
          _currentCall = _currentCall!.copyWith(status: CallStatus.ended);
          onCallStatusChange?.call(_currentCall!);
        }
        _handleConnectionFailed();
        break;
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
        print('DEBUG AudioCallService: ICE connection closed');
        break;
      default:
        print('DEBUG AudioCallService: Unknown ICE state: $state');
        break;
    }
  }

  int _reconnectionAttempts = 0;
  final int _maxReconnectionAttempts = 3;
  Timer? _reconnectionTimer;

  void _handleConnectionLost() {
    if (_currentCall == null || _currentCall!.status != CallStatus.connected) return;

    if (_reconnectionAttempts < _maxReconnectionAttempts) {
      _reconnectionAttempts++;
      print('Attempting reconnection ${_reconnectionAttempts}/${_maxReconnectionAttempts}');

      // Update UI to show reconnection attempt
      _currentCall = _currentCall!.copyWith(status: CallStatus.connecting);
      onCallStatusChange?.call(_currentCall!);

      // Wait before attempting reconnection
      _reconnectionTimer?.cancel();
      _reconnectionTimer = Timer(Duration(seconds: _reconnectionAttempts * 2), () {
        _attemptReconnection();
      });
    } else {
      print('Max reconnection attempts reached, ending call');
      endCall();
    }
  }

  void _handleConnectionFailed() {
    _reconnectionTimer?.cancel();
    endCall();
  }

  Future<void> _attemptReconnection() async {
    try {
      if (_peerConnection == null || _currentCall == null) return;

      print('Attempting ICE restart...');

      // Create new offer with ICE restart
      final offer = await _peerConnection!.createOffer({'iceRestart': true});
      await _peerConnection!.setLocalDescription(offer);

      // Send the new offer through signaling
      final encryptedOffer = await CryptoEngine.encrypt(offer.sdp!);
      _networkService.send('call_restart', {
        'to': _currentCall!.recipientId,
        'offer': encryptedOffer,
        'call_id': _currentCall!.id,
      });

    } catch (e) {
      print('Reconnection attempt failed: $e');
      _handleConnectionLost();
    }
  }

  // Speakerphone management
  Future<void> toggleSpeakerphone() async {
    try {
      final bool isCurrentlyOn = await AudioManagerService.isSpeakerphoneOn();
      await AudioManagerService.setSpeakerphoneOn(!isCurrentlyOn);
    } catch (e) {
      print('Error toggling speakerphone: $e');
    }
  }

  Future<bool> isSpeakerphoneEnabled() async {
    try {
      return await AudioManagerService.isSpeakerphoneOn();
    } catch (e) {
      print('Error getting speakerphone state: $e');
      return false;
    }
  }

  // Set audio mode for calls
  Future<void> setCallAudioMode() async {
    try {
      await AudioManagerService.setAudioMode(AudioManagerService.MODE_IN_COMMUNICATION);
    } catch (e) {
      print('Error setting call audio mode: $e');
    }
  }

  // Reset audio mode after call
  Future<void> resetAudioMode() async {
    try {
      await AudioManagerService.setAudioMode(AudioManagerService.MODE_NORMAL);
    } catch (e) {
      print('Error resetting audio mode: $e');
    }
  }

  // Test helper methods for handling WebRTC messages
  void testHandleOffer(Map<String, dynamic> payload) {
    _handleOffer(payload);
  }

  void testHandleAnswer(Map<String, dynamic> payload) {
    _handleAnswer(payload);
  }

  void testHandleCandidate(Map<String, dynamic> payload) {
    _handleCandidate(payload);
  }

  void testHandleConnectionStateChange(RTCPeerConnectionState state) {
    _handleConnectionStateChange(state);
  }

}