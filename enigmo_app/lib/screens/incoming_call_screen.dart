import 'package:flutter/material.dart';
import 'package:enigmo_app/models/call.dart';

class IncomingCallScreen extends StatelessWidget {
  final Call call;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  
  const IncomingCallScreen({
    Key? key,
    required this.call,
    required this.onAccept,
    required this.onReject,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Avatar
              const CircleAvatar(
                radius: 60,
                backgroundColor: Colors.grey,
                child: Icon(
                  Icons.person,
                  size: 60,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 20),
              
              // Caller name
              Text(
                call.recipientId, // In a real app, this would be the caller's name
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              
              // Call status
              const Text(
                'Incoming Audio Call',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 40),
              
              // Call actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Reject button (red)
                  Column(
                    children: [
                      FloatingActionButton(
                        backgroundColor: Colors.red,
                        onPressed: onReject,
                        child: const Icon(
                          Icons.call_end,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Reject',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  
                  // Accept button (green)
                  Column(
                    children: [
                      FloatingActionButton(
                        backgroundColor: Colors.green,
                        onPressed: onAccept,
                        child: const Icon(
                          Icons.call,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Accept',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}