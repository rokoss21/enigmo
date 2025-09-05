import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Service to manage WebRTC voice calls.
class CallService {
  final void Function(Map<String, dynamic>) _sendSignal;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  CallService(this._sendSignal);

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  Future<void> init() async {
    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true});
  }

  Future<void> startCall(String targetUserId) async {
    await init();
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    });

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
      }
    };

    for (var track in _localStream!.getTracks()) {
      _peerConnection!.addTrack(track, _localStream!);
    }

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    _sendSignal({
      'type': 'call_offer',
      'target_user_id': targetUserId,
      'sdp': offer.sdp,
      'session_type': offer.type,
    });

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _sendSignal({
          'type': 'ice_candidate',
          'target_user_id': targetUserId,
          'candidate': candidate.toMap(),
        });
      }
    };
  }

  Future<void> handleSignal(Map<String, dynamic> message) async {
    switch (message['type']) {
      case 'call_offer':
        await _handleOffer(message);
        break;
      case 'call_answer':
        await _handleAnswer(message);
        break;
      case 'ice_candidate':
        await _handleCandidate(message);
        break;
      case 'end_call':
        await endCall();
        break;
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> message) async {
    await init();
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    });

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
      }
    };
    for (var track in _localStream!.getTracks()) {
      _peerConnection!.addTrack(track, _localStream!);
    }

    final description = RTCSessionDescription(message['sdp'], 'offer');
    await _peerConnection!.setRemoteDescription(description);
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _sendSignal({
      'type': 'call_answer',
      'target_user_id': message['sender_id'],
      'sdp': answer.sdp,
      'session_type': answer.type,
    });

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _sendSignal({
          'type': 'ice_candidate',
          'target_user_id': message['sender_id'],
          'candidate': candidate.toMap(),
        });
      }
    };
  }

  Future<void> _handleAnswer(Map<String, dynamic> message) async {
    final description = RTCSessionDescription(message['sdp'], 'answer');
    await _peerConnection?.setRemoteDescription(description);
  }

  Future<void> _handleCandidate(Map<String, dynamic> message) async {
    final c = message['candidate'];
    if (c != null) {
      final candidate = RTCIceCandidate(
        c['candidate'],
        c['sdpMid'],
        c['sdpMLineIndex'],
      );
      await _peerConnection?.addCandidate(candidate);
    }
  }

  Future<void> endCall() async {
    await _peerConnection?.close();
    _peerConnection = null;
    await _localStream?.dispose();
    await _remoteStream?.dispose();
    _localStream = null;
    _remoteStream = null;
  }
}
