enum CallStatus { 
  idle, 
  connecting, 
  connected, 
  ringing, 
  ended 
}

class Call {
  final String id;
  final String recipientId;
  final CallStatus status;
  final bool isOutgoing;
  final DateTime startTime;
  final DateTime? endTime;
  
  Call({
    required this.id,
    required this.recipientId,
    required this.status,
    required this.isOutgoing,
    required this.startTime,
    this.endTime,
  });
  
  Call copyWith({
    String? id,
    String? recipientId,
    CallStatus? status,
    bool? isOutgoing,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return Call(
      id: id ?? this.id,
      recipientId: recipientId ?? this.recipientId,
      status: status ?? this.status,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Call &&
        other.id == id &&
        other.recipientId == recipientId &&
        other.status == status;
  }
  
  @override
  int get hashCode => Object.hash(id, recipientId, status);
}