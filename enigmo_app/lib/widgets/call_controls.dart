import 'package:flutter/material.dart';

class CallControls extends StatefulWidget {
  final bool isMuted;
  final VoidCallback onMuteToggle;
  final VoidCallback onEndCall;
  final VoidCallback onSpeakerToggle;

  const CallControls({
    Key? key,
    required this.isMuted,
    required this.onMuteToggle,
    required this.onEndCall,
    required this.onSpeakerToggle,
  }) : super(key: key);

  @override
  State<CallControls> createState() => _CallControlsState();
}

class _CallControlsState extends State<CallControls> {
  bool _isSpeakerOn = false;

  @override
  void initState() {
    super.initState();
    _updateSpeakerState();
  }

  Future<void> _updateSpeakerState() async {
    // This would need to be passed from the parent or use a service
    // For now, we'll keep it simple
  }

  void _handleSpeakerToggle() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    widget.onSpeakerToggle();
  }
  
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Mute button
        Column(
          children: [
            IconButton(
              icon: Icon(
                widget.isMuted ? Icons.mic_off : Icons.mic,
                color: widget.isMuted ? Colors.red : Colors.white,
                size: 30,
              ),
              onPressed: widget.onMuteToggle,
            ),
            const Text(
              'Mute',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),

        // Speaker button
        Column(
          children: [
            IconButton(
              icon: Icon(
                _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                color: _isSpeakerOn ? Colors.green : Colors.white,
                size: 30,
              ),
              onPressed: _handleSpeakerToggle,
            ),
            const Text(
              'Speaker',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),

        // End call button
        Column(
          children: [
            IconButton(
              icon: const Icon(
                Icons.call_end,
                color: Colors.red,
                size: 30,
              ),
              onPressed: widget.onEndCall,
            ),
            const Text(
              'End',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ],
    );
  }
}