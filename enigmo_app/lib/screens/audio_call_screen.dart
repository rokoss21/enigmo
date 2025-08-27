import 'package:flutter/material.dart';
import 'package:enigmo_app/services/audio_call_service.dart';
import 'package:enigmo_app/widgets/call_controls.dart';
import 'package:enigmo_app/widgets/call_status_indicator.dart';
import 'package:enigmo_app/models/call.dart';

class AudioCallScreen extends StatefulWidget {
  final AudioCallService audioCallService;
  
  const AudioCallScreen({Key? key, required this.audioCallService}) : super(key: key);
  
  @override
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  String _callDuration = '00:00';

  @override
  void initState() {
    super.initState();

    // Setup pulse animation for connecting state
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen for call state changes
    widget.audioCallService.onCallStatusChange = (call) {
      if (mounted) {
        _handleCallStatusChange(call);
      }
    };

    // Start call timer if already connected
    final call = widget.audioCallService.currentCall;
    if (call != null && call.status == CallStatus.connected) {
      _startCallTimer();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleCallStatusChange(Call? call) {
    if (call != null && call.status == CallStatus.connected) {
      _startCallTimer();
    } else if (call != null && call.status == CallStatus.ended) {
      _pulseController.stop();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _startCallTimer() {
    final call = widget.audioCallService.currentCall;
    if (call == null) return;

    // Update duration every second
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      final currentCall = widget.audioCallService.currentCall;
      if (currentCall == null || currentCall.status != CallStatus.connected) {
        return false;
      }

      final duration = DateTime.now().difference(currentCall.startTime);
      if (mounted) {
        setState(() {
          _callDuration = _formatDuration(duration);
        });
      }
      return true;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  
  @override
  Widget build(BuildContext context) {
    final call = widget.audioCallService.currentCall;

    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Contact avatar/name with pulse animation for connecting state
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: call?.status == CallStatus.connecting ? _pulseAnimation.value : 1.0,
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor: _getAvatarColor(call?.status),
                      child: Icon(
                        Icons.person,
                        size: 60,
                        color: Colors.white70,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // Contact name
              Text(
                call?.recipientId ?? 'Unknown',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),

              // Call duration (only show when connected)
              if (call?.status == CallStatus.connected)
                Text(
                  _callDuration,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                    fontFamily: 'monospace',
                  ),
                ),

              const SizedBox(height: 10),

              // Call status
              CallStatusIndicator(status: call?.status ?? CallStatus.connecting),
              const SizedBox(height: 40),

              // Call controls
              CallControls(
                isMuted: widget.audioCallService.isMuted,
                onMuteToggle: () => widget.audioCallService.toggleMute(),
                onEndCall: () => _endCall(context),
                onSpeakerToggle: () => widget.audioCallService.toggleSpeakerphone(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getAvatarColor(CallStatus? status) {
    switch (status) {
      case CallStatus.connecting:
        return Colors.orange;
      case CallStatus.connected:
        return Colors.green;
      case CallStatus.ended:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
  
  void _endCall(BuildContext context) {
    widget.audioCallService.endCall();
    Navigator.of(context).pop();
  }
}