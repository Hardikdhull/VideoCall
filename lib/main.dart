import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../screens/signaling.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      // TODO: Paste your Firebase config here again!
      apiKey: "AIzaSy...",
      appId: "1:12345...",
      messagingSenderId: "12345...",
      projectId: "your-project-id",
      storageBucket: "your-project-id.appspot.com",
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CognitiveLens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF202124), // Google Meet Dark Grey
        useMaterial3: true,
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
  TextEditingController textEditingController = TextEditingController();
  bool _inCall = false;
  bool _micEnabled = true;
  bool _camEnabled = true;

  @override
  void initState() {
    super.initState();
    _initializeRenderers();

    signaling.onAddRemoteStream = ((stream) {
      _remoteRenderer.srcObject = stream;
      setState(() {});
    });
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // Auto-start camera for "Green Room" preview
    await signaling.openUserMedia(_localRenderer, _remoteRenderer);
    setState(() {});
  }

  // Toggle Mic/Cam Logic
  void _toggleMic() {
    // Note: In a real app, you'd toggle the track on the stream
    setState(() {
      _micEnabled = !_micEnabled;
    });
  }

  void _toggleCam() {
    // Note: In a real app, you'd toggle the track on the stream
    setState(() {
      _camEnabled = !_camEnabled;
    });
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
      appBar: _inCall
          ? null
          : AppBar(
        title: const Text("CognitiveLens"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _inCall ? _buildInCallUI() : _buildGreenRoomUI(),
    );
  }
  Widget _buildGreenRoomUI() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: Colors.black,
                      child: RTCVideoView(_localRenderer, mirror: true),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: Row(
                      children: [
                        Icon(_micEnabled ? Icons.mic : Icons.mic_off, color: Colors.white),
                        const SizedBox(width: 8),
                        Icon(_camEnabled ? Icons.videocam : Icons.videocam_off, color: Colors.white),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF2D2E30),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (roomId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8)
                  ),
                  child: SelectableText(
                    "Room ID: $roomId",
                    style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                  ),
                ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text("New Meeting"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8AB4F8),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () async {
                        roomId = await signaling.createRoom(_remoteRenderer);
                        textEditingController.text = roomId!;
                        setState(() { _inCall = true; }); // Jump to call
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textEditingController,
                      decoration: InputDecoration(
                        hintText: "Enter a code",
                        prefixIcon: const Icon(Icons.keyboard),
                        filled: true,
                        fillColor: const Color(0xFF3C4043),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      signaling.joinRoom(
                        textEditingController.text.trim(),
                        _remoteRenderer,
                      );
                      setState(() { _inCall = true; }); // Jump to call
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    ),
                    child: const Text("Join"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInCallUI() {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: Colors.black87,
            child: RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 100,
          child: Container(
            height: 150,
            width: 100,
            decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade800),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)
                ]
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: RTCVideoView(_localRenderer, mirror: true),
            ),
          ),
        ),

        // 3. Control Bar (Bottom)
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF3C4043),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildControlBtn(
                    icon: _micEnabled ? Icons.mic : Icons.mic_off,
                    color: _micEnabled ? Colors.white : Colors.red,
                    onPressed: _toggleMic,
                  ),
                  const SizedBox(width: 16),
                  _buildControlBtn(
                    icon: _camEnabled ? Icons.videocam : Icons.videocam_off,
                    color: _camEnabled ? Colors.white : Colors.red,
                    onPressed: _toggleCam,
                  ),
                  const SizedBox(width: 16),
                  _buildControlBtn(
                    icon: Icons.call_end,
                    color: Colors.white,
                    bgColor: Colors.red,
                    onPressed: () {
                      signaling.hangUp(_localRenderer);
                      setState(() {
                        _inCall = false;
                        roomId = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    Color bgColor = const Color(0xFF5F6368)
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}