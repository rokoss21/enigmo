// WebRTC Signaling Message Types
export interface CallInitiateMessage {
  type: 'call_initiate';
  to: string;
  offer: string; // Encrypted SDP offer
  call_id: string;
}

export interface CallAcceptMessage {
  type: 'call_accept';
  to: string;
  answer: string; // Encrypted SDP answer
  call_id: string;
}

export interface CallCandidateMessage {
  type: 'call_candidate';
  to: string;
  candidate: string; // Encrypted ICE candidate
  call_id: string;
}

export interface CallEndMessage {
  type: 'call_end';
  to: string;
  call_id: string;
}

// In-memory call state storage
const activeCalls = new Map<string, {
  caller: string;
  callee: string;
  status: 'initiated' | 'connected' | 'ended';
  startTime: Date;
}>();

// WebSocket message handlers
export function handleCallInitiate(socket: WebSocket, message: CallInitiateMessage, userId: string) {
  // Verify user is authorized to make this call
  if (message.to === userId) {
    // Don't allow calling yourself
    return;
  }
  
  // Store call state
  activeCalls.set(message.call_id, {
    caller: userId,
    callee: message.to,
    status: 'initiated',
    startTime: new Date()
  });
  
  // Forward encrypted offer to recipient
  // In a real implementation, you would find the recipient's socket
  // and send them the call_initiate message
  forwardMessageToRecipient(message.to, {
    type: 'call_offer',
    from: userId,
    offer: message.offer,
    call_id: message.call_id
  });
}

export function handleCallAccept(socket: WebSocket, message: CallAcceptMessage, userId: string) {
  const call = activeCalls.get(message.call_id);
  if (!call || call.callee !== userId) {
    // Call doesn't exist or user isn't the callee
    return;
  }
  
  // Update call state
  call.status = 'connected';
  
  // Forward encrypted answer to caller
  forwardMessageToRecipient(call.caller, {
    type: 'call_answer',
    from: userId,
    answer: message.answer,
    call_id: message.call_id
  });
}

export function handleCallCandidate(socket: WebSocket, message: CallCandidateMessage, userId: string) {
  const call = activeCalls.get(message.call_id);
  if (!call) {
    // Call doesn't exist
    return;
  }
  
  // Forward ICE candidate to other participant
  const recipient = call.caller === userId ? call.callee : call.caller;
  forwardMessageToRecipient(recipient, {
    type: 'call_candidate',
    from: userId,
    candidate: message.candidate,
    call_id: message.call_id
  });
}

export function handleCallEnd(socket: WebSocket, message: CallEndMessage, userId: string) {
  const call = activeCalls.get(message.call_id);
  if (!call) {
    // Call doesn't exist
    return;
  }
  
  // Verify user is participant in call
  if (call.caller !== userId && call.callee !== userId) {
    return;
  }
  
  // Update call state
  call.status = 'ended';
  
  // Forward end message to other participant
  const recipient = call.caller === userId ? call.callee : call.caller;
  forwardMessageToRecipient(recipient, {
    type: 'call_end',
    from: userId,
    call_id: message.call_id
  });
  
  // Clean up call state after delay
  setTimeout(() => {
    activeCalls.delete(message.call_id);
  }, 60000); // Keep state for 1 minute after call ends
}

// Helper function to forward messages to recipients
function forwardMessageToRecipient(recipientId: string, message: any) {
  // In a real implementation, you would:
  // 1. Look up the recipient's active WebSocket connection
  // 2. Send the message through that connection
  // 3. Handle cases where the recipient is offline
  
  // For now, we'll just log the action
  console.log(`Forwarding message to ${recipientId}:`, message);
}