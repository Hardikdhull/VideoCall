import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef void StreamStateCallback(MediaStream stream);

class Signaling {
  Map<String, dynamic> configuration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302'
        ]
      },
      // Add free TURN servers for NAT traversal
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 10,
    'iceTransportPolicy': 'all', // Try all connection types
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
  };

  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;
  String? roomId;
  StreamStateCallback? onAddRemoteStream;

  // A queue to hold candidates received before connection is ready
  List<RTCIceCandidate> remoteCandidatesQueue = [];

  // Track if answer has been received (for host)
  bool _answerReceived = false;

  Future<String> createRoom(String customId, RTCVideoRenderer remoteRenderer) async {
    FirebaseFirestore db = FirebaseFirestore.instance;
    DocumentReference roomRef = db.collection('rooms').doc(customId);

    print('DEBUG: Creating room: $customId');
    peerConnection = await createPeerConnection(configuration);

    // Register listeners FIRST before adding transceivers
    registerPeerConnectionListeners();

    // Add local tracks FIRST, before creating transceivers
    localStream?.getTracks().forEach((track) {
      print('DEBUG: Host adding local track: ${track.kind}, enabled: ${track.enabled}');
      peerConnection?.addTrack(track, localStream!);
    });

    // Collect ICE candidates
    var callerCandidatesCollection = roomRef.collection('callerCandidates');
    peerConnection?.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate != null) {
        print('DEBUG: Host ICE candidate type: ${candidate.candidate?.contains('typ relay') == true ? 'RELAY (TURN)' : candidate.candidate?.contains('typ srflx') == true ? 'SRFLX (STUN)' : candidate.candidate?.contains('typ host') == true ? 'HOST' : 'UNKNOWN'}');
        print('DEBUG: Host sending ICE candidate: ${candidate.candidate}');
        callerCandidatesCollection.add(candidate.toMap());
      }
    };

    // Create Offer with explicit constraints
    RTCSessionDescription offer = await peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await peerConnection!.setLocalDescription(offer);

    print('DEBUG: Local description set. SDP type: ${offer.type}');

    await roomRef.set({'offer': offer.toMap()});
    print('DEBUG: Offer uploaded to Firestore. Waiting for answer...');

    // Store roomId immediately so hangUp can clean up
    roomId = customId;

    // Reset the answer received flag for this new room
    _answerReceived = false;

    // Listen for Answer - FIXED: Use onSnapshot with better filtering
    roomRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists || _answerReceived) return;

      var data = snapshot.data() as Map<String, dynamic>?;
      if (data == null) return;

      print("DEBUG: Host snapshot update received. Keys: ${data.keys.toList()}");

      // Debug the conditions
      bool hasAnswer = data.containsKey('answer');
      var remoteDesc = await peerConnection?.getRemoteDescription();
      bool noRemoteDesc = remoteDesc == null || remoteDesc.sdp == null || remoteDesc.sdp!.isEmpty;

      print("DEBUG: hasAnswer: $hasAnswer, noRemoteDesc: $noRemoteDesc, answerReceived: $_answerReceived");

      // Check if answer exists and we haven't set remote description yet
      if (data.containsKey('answer') && noRemoteDesc && !_answerReceived) {
        _answerReceived = true;
        var answerData = data['answer'] as Map<String, dynamic>;
        var answer = RTCSessionDescription(
          answerData['sdp'],
          answerData['type'],
        );
        print("DEBUG: Host received Answer! Setting remote description...");
        print("DEBUG: Answer SDP type: ${answer.type}");

        try {
          await peerConnection?.setRemoteDescription(answer);
          print("DEBUG: Remote description set successfully!");
          await _processQueuedCandidates();
        } catch (e) {
          print("ERROR: Failed to set remote description: $e");
          _answerReceived = false; // Allow retry
        }
      }
    });

    // Listen for Guest Candidates
    roomRef.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          var data = change.doc.data() as Map<String, dynamic>;
          print('DEBUG: Host received guest candidate');
          _addCandidateOrQueue(data);
        }
      }
    });

    return customId;
  }

  // --- GUEST LOGIC ---
  Future<void> joinRoom(String inputRoomId, RTCVideoRenderer remoteVideo) async {
    FirebaseFirestore db = FirebaseFirestore.instance;
    DocumentReference roomRef = db.collection('rooms').doc(inputRoomId);
    var roomSnapshot = await roomRef.get();

    if (roomSnapshot.exists) {
      print('DEBUG: Guest joining room: $inputRoomId');
      peerConnection = await createPeerConnection(configuration);

      registerPeerConnectionListeners();

      localStream?.getTracks().forEach((track) {
        print('DEBUG: Guest adding local track: ${track.kind}, enabled: ${track.enabled}');
        peerConnection?.addTrack(track, localStream!);
      });
      var calleeCandidatesCollection = roomRef.collection('calleeCandidates');
      peerConnection!.onIceCandidate = (RTCIceCandidate? candidate) {
        if (candidate != null) {
          print('DEBUG: Guest ICE candidate type: ${candidate.candidate?.contains('typ relay') == true ? 'RELAY (TURN)' : candidate.candidate?.contains('typ srflx') == true ? 'SRFLX (STUN)' : candidate.candidate?.contains('typ host') == true ? 'HOST' : 'UNKNOWN'}');
          print('DEBUG: Guest sending ICE candidate');
          calleeCandidatesCollection.add(candidate.toMap());
        }
      };

      var data = roomSnapshot.data() as Map<String, dynamic>;
      var offer = data['offer'];

      print('DEBUG: Guest received offer, SDP type: ${offer['type']}');

      // Set Host's Offer as remote description
      await peerConnection?.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']),
      );
      print('DEBUG: Guest set remote description (offer)');

      // Create Answer with explicit constraints
      var answer = await peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await peerConnection!.setLocalDescription(answer);

      print('DEBUG: Guest created answer, SDP type: ${answer.type}');

      // Store roomId for cleanup
      roomId = inputRoomId;

      try {
        await roomRef.update({
          'answer': {'type': answer.type, 'sdp': answer.sdp}
        });
        print("DEBUG: Guest uploaded Answer to Firestore successfully");

        // Verify the write
        var verifySnapshot = await roomRef.get();
        var verifyData = verifySnapshot.data() as Map<String, dynamic>?;
        print("DEBUG: Guest verification - Answer exists in Firestore: ${verifyData?.containsKey('answer')}");
      } catch (e) {
        print("ERROR: Guest failed to upload answer: $e");
      }

      await _processQueuedCandidates();

      // Listen for Host Candidates
      roomRef.collection('callerCandidates').snapshots().listen((snapshot) {
        for (var document in snapshot.docChanges) {
          if (document.type == DocumentChangeType.added) {
            var data = document.doc.data() as Map<String, dynamic>;
            print('DEBUG: Guest received host candidate');
            _addCandidateOrQueue(data);
          }
        }
      });
    } else {
      print("ERROR: Room does not exist!");
    }
  }

  // --- HELPER FUNCTIONS ---

  void _addCandidateOrQueue(Map<String, dynamic> data) async {
    try {
      var candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );

      // Log candidate type
      String candidateType = 'UNKNOWN';
      if (data['candidate']?.contains('typ relay') == true) {
        candidateType = 'RELAY (TURN)';
      } else if (data['candidate']?.contains('typ srflx') == true) {
        candidateType = 'SRFLX (STUN)';
      } else if (data['candidate']?.contains('typ host') == true) {
        candidateType = 'HOST';
      }
      print("DEBUG: Received remote candidate type: $candidateType");

      // IMPORTANT: Wait until we have a remote description before adding candidates
      if (peerConnection?.getRemoteDescription() != null) {
        await peerConnection?.addCandidate(candidate);
        print("DEBUG: Added Remote Candidate immediately ($candidateType).");
      } else {
        remoteCandidatesQueue.add(candidate);
        print("DEBUG: Queued Remote Candidate ($candidateType). Queue size: ${remoteCandidatesQueue.length}");
      }
    } catch (e) {
      print("ERROR: Failed to add candidate: $e");
    }
  }

  Future<void> _processQueuedCandidates() async {
    if (remoteCandidatesQueue.isEmpty) {
      print("DEBUG: No queued candidates to process");
      return;
    }
    print("DEBUG: Processing ${remoteCandidatesQueue.length} queued candidates...");
    for (var candidate in remoteCandidatesQueue) {
      await peerConnection?.addCandidate(candidate);
      print("DEBUG: Processed queued candidate");
    }
    remoteCandidatesQueue.clear();
    print("DEBUG: Finished processing queued candidates");
  }

  Future<void> openUserMedia(RTCVideoRenderer localVideo, RTCVideoRenderer remoteVideo) async {
    var stream = await navigator.mediaDevices.getUserMedia({
      'video': {
        'mandatory': {
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      },
      'audio': true,
    });

    print('DEBUG: Got user media - Video tracks: ${stream.getVideoTracks().length}, Audio tracks: ${stream.getAudioTracks().length}');

    localVideo.srcObject = stream;
    localStream = stream;

    remoteVideo.srcObject = await createLocalMediaStream('key');
  }

  Future<void> hangUp(RTCVideoRenderer localVideo) async {
    try {
      print('DEBUG: Hanging up...');

      // Stop all tracks
      localStream?.getTracks().forEach((track) {
        print('DEBUG: Stopping local track: ${track.kind}');
        track.stop();
      });
      remoteStream?.getTracks().forEach((track) {
        print('DEBUG: Stopping remote track: ${track.kind}');
        track.stop();
      });

      // Close peer connection
      if (peerConnection != null) {
        await peerConnection!.close();
        peerConnection = null;
        print('DEBUG: Peer connection closed');
      }

      // Clean up Firestore
      if (roomId != null) {
        var db = FirebaseFirestore.instance;
        var roomRef = db.collection('rooms').doc(roomId);

        var calleeCandidates = await roomRef.collection('calleeCandidates').get();
        for (var doc in calleeCandidates.docs) await doc.reference.delete();

        var callerCandidates = await roomRef.collection('callerCandidates').get();
        for (var doc in callerCandidates.docs) await doc.reference.delete();

        await roomRef.delete();
        print('DEBUG: Firestore room cleaned up');
      }
    } catch (e) {
      print("ERROR: Error hanging up: $e");
    } finally {
      localStream = null;
      remoteStream = null;
      roomId = null;
      remoteCandidatesQueue.clear();
      _answerReceived = false;
      print('DEBUG: Hangup complete');
    }
  }

  void registerPeerConnectionListeners() {
    peerConnection?.onIceGatheringState = (RTCIceGatheringState state) {
      print('DEBUG: ICE gathering state changed: $state');
    };

    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      print('DEBUG: Connection state change: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        print('ERROR: Connection FAILED!');
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        print('SUCCESS: Connection ESTABLISHED!');
      }
    };

    peerConnection?.onSignalingState = (RTCSignalingState state) {
      print('DEBUG: Signaling state change: $state');
    };

    peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      print('DEBUG: ICE connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        print('ERROR: ICE connection FAILED!');
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        print('SUCCESS: ICE connection ESTABLISHED!');
      }
    };

    peerConnection?.onTrack = (RTCTrackEvent event) {
      print('DEBUG: ===== TRACK RECEIVED =====');
      print('DEBUG: Track kind: ${event.track.kind}');
      print('DEBUG: Track ID: ${event.track.id}');
      print('DEBUG: Track enabled: ${event.track.enabled}');
      print('DEBUG: Track muted: ${event.track.muted}');
      print('DEBUG: Number of streams: ${event.streams.length}');

      if (event.streams.isNotEmpty) {
        print('DEBUG: Stream ID: ${event.streams[0].id}');
        print('DEBUG: Stream active: ${event.streams[0].active}');
        print('DEBUG: Stream has ${event.streams[0].getVideoTracks().length} video tracks');
        print('DEBUG: Stream has ${event.streams[0].getAudioTracks().length} audio tracks');

        // Check if video tracks are enabled
        for (var track in event.streams[0].getVideoTracks()) {
          print('DEBUG: Video track ${track.id} - enabled: ${track.enabled}, muted: ${track.muted}');
        }

        // Check if audio tracks are enabled
        for (var track in event.streams[0].getAudioTracks()) {
          print('DEBUG: Audio track ${track.id} - enabled: ${track.enabled}, muted: ${track.muted}');
        }

        remoteStream = event.streams[0];

        // CRITICAL: Call the callback to update the UI
        if (onAddRemoteStream != null) {
          print('DEBUG: Calling onAddRemoteStream callback');
          onAddRemoteStream?.call(remoteStream!);
        } else {
          print('WARNING: onAddRemoteStream callback is NULL!');
        }
      } else {
        print('WARNING: Track event has no streams!');
      }
    };
  }

  // Diagnostic method to check connection details
  Future<void> logConnectionDetails() async {
    if (peerConnection == null) {
      print('DEBUG: No peer connection exists');
      return;
    }

    print('DEBUG: ===== CONNECTION DETAILS =====');
    print('DEBUG: Connection state: ${peerConnection?.connectionState}');
    print('DEBUG: ICE connection state: ${peerConnection?.iceConnectionState}');
    print('DEBUG: ICE gathering state: ${peerConnection?.iceGatheringState}');
    print('DEBUG: Signaling state: ${peerConnection?.signalingState}');

    var senders = await peerConnection?.getSenders() ?? [];
    print('DEBUG: Number of senders: ${senders.length}');
    for (var sender in senders) {
      var track = sender.track;
      if (track != null) {
        print('DEBUG: Sender - kind: ${track.kind}, enabled: ${track.enabled}, id: ${track.id}');
      } else {
        print('DEBUG: Sender has no track');
      }
    }

    var receivers = await peerConnection?.getReceivers() ?? [];
    print('DEBUG: Number of receivers: ${receivers.length}');
    for (var receiver in receivers) {
      var track = receiver.track;
      if (track != null) {
        print('DEBUG: Receiver - kind: ${track.kind}, enabled: ${track.enabled}, id: ${track.id}');
      } else {
        print('DEBUG: Receiver has no track');
      }
    }

    var transceivers = await peerConnection?.getTransceivers() ?? [];
    print('DEBUG: Number of transceivers: ${transceivers.length}');

    var localDesc = await peerConnection?.getLocalDescription();
    var remoteDesc = await peerConnection?.getRemoteDescription();
    print('DEBUG: Has local description: ${localDesc != null}');
    print('DEBUG: Has remote description: ${remoteDesc != null}');

    print('DEBUG: ===== END DETAILS =====');
  }
}