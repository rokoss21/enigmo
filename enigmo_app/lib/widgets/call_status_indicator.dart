import 'package:flutter/material.dart';
import 'package:enigmo_app/models/call.dart';

class CallStatusIndicator extends StatefulWidget {
  final CallStatus status;

  const CallStatusIndicator({Key? key, required this.status}) : super(key: key);

  @override
  State<CallStatusIndicator> createState() => _CallStatusIndicatorState();
}

class _CallStatusIndicatorState extends State<CallStatusIndicator>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _dotsController;
  late Animation<int> _dotsAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation for connecting/ringing states
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Dots animation for connecting/ringing states
    _dotsController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _dotsAnimation = IntTween(begin: 0, end: 3).animate(
      CurvedAnimation(parent: _dotsController, curve: Curves.linear),
    );

    _updateAnimation();
  }

  @override
  void didUpdateWidget(CallStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (widget.status == CallStatus.connecting || widget.status == CallStatus.ringing) {
      _pulseController.repeat(reverse: true);
      _dotsController.repeat();
    } else {
      _pulseController.stop();
      _dotsController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _dotsAnimation]),
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated status indicator
            Transform.scale(
              scale: (widget.status == CallStatus.connecting || widget.status == CallStatus.ringing)
                  ? _pulseAnimation.value
                  : 1.0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _getStatusColor(),
                  shape: BoxShape.circle,
                  boxShadow: (widget.status == CallStatus.connecting || widget.status == CallStatus.ringing)
                      ? [
                          BoxShadow(
                            color: _getStatusColor().withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          )
                        ]
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _getStatusText(),
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      },
    );
  }

  String _getStatusText() {
    switch (widget.status) {
      case CallStatus.connecting:
        return 'Connecting${_getDots()}';
      case CallStatus.connected:
        return 'Connected';
      case CallStatus.ringing:
        return 'Ringing${_getDots()}';
      case CallStatus.ended:
        return 'Call Ended';
      default:
        return 'Idle';
    }
  }

  String _getDots() {
    final dotCount = _dotsAnimation.value;
    return '.' * dotCount;
  }

  Color _getStatusColor() {
    switch (widget.status) {
      case CallStatus.connecting:
        return Colors.orange;
      case CallStatus.connected:
        return Colors.green;
      case CallStatus.ringing:
        return Colors.blue;
      case CallStatus.ended:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}