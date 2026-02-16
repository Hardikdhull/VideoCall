import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

typedef void StreamStateCallback(MediaStream stream);

class Signaling {
  // --- CONFIGURATION ---
  Map<String, dynamic> configuration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302'
        ]
      },
      // Free TURN servers for NAT traversal (Hotspots/4G)
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

  // UNIQUE ID for Chat & User Identification
  final String userId = DateTime.now().millisecondsSinceEpoch.toString();

  // A queue to hold candidates received before connection is ready
  List<RTCIceCandidate> remoteCandidatesQueue = [];

  // Track if answer has been received (for host)
  bool _answerReceived = false;

  // --- HOST LOGIC ---
  Future<String> createRoom(String customId, RTCVideoRenderer remoteRenderer) async {
    FirebaseFirestore db = FirebaseFirestore.instance;
    DocumentReference roomRef = db.collection('rooms').doc(customId);

    print('DEBUG: Creating room: $customId');
    peerConnection = await createPeerConnection(configuration);

    registerPeerConnectionListeners();

    // Add local tracks
    localStream?.getTracks().forEach((track) {
      print('DEBUG: Host adding local track: ${track.kind}, enabled: ${track.enabled}');
      peerConnection?.addTrack(track, localStream!);
    });

    // Collect ICE candidates
    var callerCandidatesCollection = roomRef.collection('callerCandidates');
    peerConnection?.onIceCandidate = (RTCIceCandidate? candidate) {
      if (candidate != null) {
        print('DEBUG: Host ICE candidate: ${candidate.candidate}');
        callerCandidatesCollection.add(candidate.toMap());
      }
    };

    // Create Offer with explicit constraints (Forces video even if camera is slow)
    RTCSessionDescription offer = await peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await peerConnection!.setLocalDescription(offer);

    print('DEBUG: Local description set. SDP type: ${offer.type}');

    await roomRef.set({'offer': offer.toMap()});
    print('DEBUG: Offer uploaded to Firestore. Waiting for answer...');

    roomId = customId;
    _answerReceived = false;

    // Listen for Answer
    roomRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists || _answerReceived) return;

      var data = snapshot.data() as Map<String, dynamic>?;
      if (data == null) return;

      var remoteDesc = await peerConnection?.getRemoteDescription();
      bool noRemoteDesc = remoteDesc == null || remoteDesc.sdp == null;

      // Check if answer exists and we haven't set remote description yet
      if (data.containsKey('answer') && noRemoteDesc && !_answerReceived) {
        _answerReceived = true;
        var answerData = data['answer'] as Map<String, dynamic>;
        var answer = RTCSessionDescription(
          answerData['sdp'],
          answerData['type'],
        );
        print("DEBUG: Host received Answer! Setting remote description...");

        try {
          await peerConnection?.setRemoteDescription(answer);
          print("DEBUG: Remote description set successfully!");
          await _processQueuedCandidates();
        } catch (e) {
          print("ERROR: Failed to set remote description: $e");
          _answerReceived = false;
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
        print('DEBUG: Guest adding local track: ${track.kind}');
        peerConnection?.addTrack(track, localStream!);
      });

      var calleeCandidatesCollection = roomRef.collection('calleeCandidates');
      peerConnection!.onIceCandidate = (RTCIceCandidate? candidate) {
        if (candidate != null) {
          print('DEBUG: Guest sending ICE candidate');
          calleeCandidatesCollection.add(candidate.toMap());
        }
      };

      var data = roomSnapshot.data() as Map<String, dynamic>;
      var offer = data['offer'];

      // Set Host's Offer
      await peerConnection?.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']),
      );

      // Create Answer
      var answer = await peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await peerConnection!.setLocalDescription(answer);

      roomId = inputRoomId;

      await roomRef.update({
        'answer': {'type': answer.type, 'sdp': answer.sdp}
      });
      print("DEBUG: Guest uploaded Answer");

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

  // --- SCREEN SHARE LOGIC (NEW) ---
  Future<void> switchScreenShare(bool isScreenSharing) async {
    if (peerConnection == null) return;

    MediaStream? newStream;

    if (isScreenSharing) {
      try {
        // 1. Capture Screen
        // NOTE: On Android, this requires Foreground Service permissions!
        newStream = await navigator.mediaDevices.getDisplayMedia({'video': true});
      } catch (e) {
        print("User cancelled screen share: $e");
        return;
      }
    } else {
      // 2. Revert to Camera
      // We explicitly request low-res to keep connection stable
      newStream = await navigator.mediaDevices.getUserMedia({
        'video': {
          'mandatory': {
            'minWidth': '640',
            'minHeight': '480',
            'minFrameRate': '30',
          },
          'facingMode': 'user',
        },
        'audio': true,
      });
    }

    // 3. Replace the track being sent to the other person
    try {
      var senders = await peerConnection!.getSenders();
      var videoSender = senders.firstWhere((s) => s.track?.kind == 'video');

      await videoSender.replaceTrack(newStream.getVideoTracks()[0]);

      // 4. Update local reference so UI shows the screen share
      localStream = newStream;
      print("DEBUG: Switched track successfully. Screen sharing: $isScreenSharing");
    } catch (e) {
      print("ERROR: Failed to replace track: $e");
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

      if (peerConnection?.getRemoteDescription() != null) {
        await peerConnection?.addCandidate(candidate);
        print("DEBUG: Added Remote Candidate immediately.");
      } else {
        remoteCandidatesQueue.add(candidate);
        print("DEBUG: Queued Remote Candidate.");
      }
    } catch (e) {
      print("ERROR: Failed to add candidate: $e");
    }
  }

  Future<void> _processQueuedCandidates() async {
    if (remoteCandidatesQueue.isEmpty) return;
    print("DEBUG: Processing ${remoteCandidatesQueue.length} queued candidates...");
    for (var candidate in remoteCandidatesQueue) {
      await peerConnection?.addCandidate(candidate);
    }
    remoteCandidatesQueue.clear();
  }

  Future<void> openUserMedia(RTCVideoRenderer localVideo, RTCVideoRenderer remoteVideo) async {
    // FORCE VGA (640x480) to prevent hardware encoder crashes
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

    print('DEBUG: Got user media');
    localVideo.srcObject = stream;
    localStream = stream;

    remoteVideo.srcObject = await createLocalMediaStream('key');
  }

  Future<void> hangUp(RTCVideoRenderer localVideo) async {
    try {
      print('DEBUG: Hanging up...');
      localStream?.getTracks().forEach((track) => track.stop());
      remoteStream?.getTracks().forEach((track) => track.stop());

      if (peerConnection != null) {
        await peerConnection!.close();
        peerConnection = null;
      }

      if (roomId != null) {
        var db = FirebaseFirestore.instance;
        var roomRef = db.collection('rooms').doc(roomId);

        // Cleanup Firestore
        var calleeCandidates = await roomRef.collection('calleeCandidates').get();
        for (var doc in calleeCandidates.docs) await doc.reference.delete();

        var callerCandidates = await roomRef.collection('callerCandidates').get();
        for (var doc in callerCandidates.docs) await doc.reference.delete();

        // Also delete messages
        var messages = await roomRef.collection('messages').get();
        for (var doc in messages.docs) await doc.reference.delete();

        await roomRef.delete();
      }
    } catch (e) {
      print("ERROR: Error hanging up: $e");
    } finally {
      localStream = null;
      remoteStream = null;
      roomId = null;
      remoteCandidatesQueue.clear();
      _answerReceived = false;
    }
  }

  void registerPeerConnectionListeners() {
    peerConnection?.onIceGatheringState = (RTCIceGatheringState state) {
      print('DEBUG: ICE gathering state changed: $state');
    };

    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      print('DEBUG: Connection state change: $state');
    };

    peerConnection?.onTrack = (RTCTrackEvent event) {
      print('DEBUG: ===== TRACK RECEIVED =====');
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        if (onAddRemoteStream != null) {
          onAddRemoteStream?.call(remoteStream!);
        }
      }
    };
  }
}