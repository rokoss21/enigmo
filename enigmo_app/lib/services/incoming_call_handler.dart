import 'package:flutter/material.dart';
import 'package:enigmo_app/services/audio_call_service.dart';
import 'package:enigmo_app/screens/incoming_call_screen.dart';
import 'package:enigmo_app/models/call.dart';

class IncomingCallHandler extends StatefulWidget {
  final AudioCallService audioCallService;
  
  const IncomingCallHandler({Key? key, required this.audioCallService}) : super(key: key);
  
  @override
  State<IncomingCallHandler> createState() => _IncomingCallHandlerState();
}

class _IncomingCallHandlerState extends State<IncomingCallHandler> {
  Call? _incomingCall;
  
  @override
  void initState() {
    super.initState();
    
    // Set up listener for incoming calls
    widget.audioCallService.onIncomingCall = _handleIncomingCall;
  }
  
  void _handleIncomingCall(Call call) {
    print('DEBUG IncomingCallHandler._handleIncomingCall: Received incoming call');
    print('DEBUG IncomingCallHandler._handleIncomingCall: callId=${call.id}, callerId=${call.recipientId}');

    // Show incoming call dialog
    if (mounted) {
      print('DEBUG IncomingCallHandler._handleIncomingCall: Widget mounted, showing dialog');
      setState(() {
        _incomingCall = call;
      });

      // Show the incoming call screen as an overlay
      _showIncomingCallDialog(call);
    } else {
      print('DEBUG IncomingCallHandler._handleIncomingCall: Widget not mounted, cannot show dialog');
    }
  }
  
  void _showIncomingCallDialog(Call call) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (BuildContext context) {
        return IncomingCallScreen(
          call: call,
          onAccept: () => _acceptCall(call),
          onReject: _rejectCall,
        );
      },
    );
  }
  
  void _acceptCall(Call call) async {
    // Close the incoming call dialog
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    
    // Accept the call through the audio call service
    await widget.audioCallService.acceptCall(call.id, call.recipientId);
  }
  
  void _rejectCall() {
    // Close the incoming call dialog
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    
    // End the call (reject)
    widget.audioCallService.endCall();
  }
  
  @override
  Widget build(BuildContext context) {
    // This widget doesn't render anything visible
    // It just handles incoming call events
    return const SizedBox.shrink();
  }
}