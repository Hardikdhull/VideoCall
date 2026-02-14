import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../screens/signaling.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TODO: Replace with your actual Firebase Project config
  // Get these from Firebase Console -> Project Settings -> General -> Your Apps
  await Firebase.initializeApp(
    options: const FirebaseOptions(
        apiKey: "AIzaSyCNlLagLaX_zUHOeyaqUiemd-zKrDJ19Oc",
        authDomain: "videocall-c18db.firebaseapp.com",
        projectId: "videocall-c18db",
        storageBucket: "videocall-c18db.firebasestorage.app",
        messagingSenderId: "545209786002",
        appId: "1:545209786002:web:4cfefebd520b261702d04b"
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Video Call',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.blueAccent,
      ),
      home: const VideoCallScreen(),
    );
  }
}

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final Signaling signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  String? roomId;
  TextEditingController textEditingController = TextEditingController(text: '');

  @override
  void initState() {
    super.initState();
    _initializeRenderers();

    // Connect the Signaling class to our UI
    signaling.onAddRemoteStream = ((stream) {
      _remoteRenderer.srcObject = stream;
      setState(() {});
    });
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // Open user media (Camera/Mic) immediately
    signaling.openUserMedia(_localRenderer, _remoteRenderer);
    setState(() {});
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Google Meet Clone"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 1. Room Controls (Top Bar)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                      onPressed: () async {
                        roomId = await signaling.createRoom(_remoteRenderer);
                        textEditingController.text = roomId!;
                        setState(() {});
                      },
                      child: const Text("Create Room"),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[700]),
                      onPressed: () {
                        // Join room logic
                        signaling.joinRoom(
                          textEditingController.text.trim(),
                          _remoteRenderer,
                        );
                      },
                      child: const Text("Join Room"),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Room ID Input Field
                if (roomId != null) ...[
                  SelectableText(
                    "Room ID: $roomId",
                    style: const TextStyle(fontSize: 16, color: Colors.greenAccent),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: textEditingController,
                  decoration: InputDecoration(
                    hintText: "Enter Room ID to Join",
                    filled: true,
                    fillColor: Colors.grey[900],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),

          // 2. Video Grid (Expanded)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  // Local Video (Mirror)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.blueAccent),
                          borderRadius: BorderRadius.circular(10)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: RTCVideoView(_localRenderer, mirror: true),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Remote Video (The other person)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.redAccent),
                          borderRadius: BorderRadius.circular(10)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: RTCVideoView(_remoteRenderer),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Bottom Controls (Hangup)
          Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: FloatingActionButton(
              backgroundColor: Colors.red,
              onPressed: () {
                signaling.hangUp(_localRenderer);
                Navigator.pop(context); // Or reset state
              },
              child: const Icon(Icons.call_end),
            ),
          ),
        ],
      ),
    );
  }
}