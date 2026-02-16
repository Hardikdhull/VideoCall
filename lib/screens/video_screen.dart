import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../screens/signaling.dart'; // Ensure this path is correct
import '../widgets/chat_panel.dart'; // Import the new ChatPanel widget

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final Signaling signaling = Signaling();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  // UI State Variables
  String? roomId;
  TextEditingController textEditingController = TextEditingController();
  bool _inCall = false;
  bool _micEnabled = true;
  bool _camEnabled = true;
  bool _isLoading = false;
  bool _remoteVideoActive = false;

  // New Feature States
  bool _isChatOpen = false;
  bool _isScreenSharing = false;

  @override
  void initState() {
    super.initState();
    _initializeRenderers();

    // Set up the listener for when the other person joins/sends video
    signaling.onAddRemoteStream = ((stream) {
      print('UI: Received remote stream callback');
      setState(() {
        _remoteRenderer.srcObject = stream;
        _remoteVideoActive = true;
      });
    });
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    try {
      // Start camera for the "Green Room" preview
      await signaling.openUserMedia(_localRenderer, _remoteRenderer);
      setState(() {});
    } catch (e) {
      print("ERROR: Error opening user media: $e");
    }
  }

  // --- TOGGLES ---
  void _toggleMic() {
    var tracks = signaling.localStream?.getAudioTracks();
    if (tracks != null && tracks.isNotEmpty) {
      bool newStatus = !tracks[0].enabled;
      tracks[0].enabled = newStatus;
      setState(() => _micEnabled = newStatus);
    }
  }

  void _toggleCam() {
    var tracks = signaling.localStream?.getVideoTracks();
    if (tracks != null && tracks.isNotEmpty) {
      bool newStatus = !tracks[0].enabled;
      tracks[0].enabled = newStatus;
      setState(() => _camEnabled = newStatus);
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    signaling.hangUp(_localRenderer);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF202124), // Dark background like Meet
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

  // --- 1. GREEN ROOM (Before Joining) ---
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
                  // Local Camera Preview
                  Positioned.fill(
                    child: Container(
                      color: Colors.black,
                      child: RTCVideoView(_localRenderer, mirror: true),
                    ),
                  ),
                  // Icons overlay
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

        // Control Panel
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF2D2E30),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Create Room Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.video_call),
                  label: Text(_isLoading ? "Creating..." : "New Meeting"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8AB4F8),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _isLoading ? null : () async {
                    setState(() => _isLoading = true);
                    try {
                      String randomCode = (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();
                      await signaling.createRoom(randomCode, _remoteRenderer);

                      setState(() {
                        roomId = randomCode;
                        _inCall = true;
                        _remoteVideoActive = false;
                        textEditingController.text = randomCode;
                      });
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                    } finally {
                      setState(() => _isLoading = false);
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),

              const Text("OR", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),

              // Join Room Section
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textEditingController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Enter a code",
                        hintStyle: const TextStyle(color: Colors.grey),
                        prefixIcon: const Icon(Icons.keyboard, color: Colors.grey),
                        filled: true,
                        fillColor: const Color(0xFF3C4043),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () async {
                      if (textEditingController.text.isEmpty) return;
                      setState(() => _isLoading = true);

                      try {
                        await signaling.joinRoom(textEditingController.text.trim(), _remoteRenderer);
                        setState(() {
                          roomId = textEditingController.text.trim();
                          _inCall = true;
                          _remoteVideoActive = false;
                        });
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                      } finally {
                        setState(() => _isLoading = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
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

  // --- 2. IN-CALL UI (The Video Screen) ---
  Widget _buildInCallUI() {
    return Stack(
      children: [
        // A. REMOTE VIDEO LAYER (Full Screen)
        Positioned.fill(
          child: Container(
            color: Colors.black87,
            child: Stack(
              children: [
                // Placeholder
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!_remoteVideoActive) const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        _remoteVideoActive ? "" : "Waiting for Remote Video...",
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                // Actual Video
                RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: false,
                ),
              ],
            ),
          ),
        ),

        // B. LOCAL VIDEO LAYER (Picture-in-Picture)
        Positioned(
          right: 16,
          bottom: 100,
          child: GestureDetector(
            onDoubleTap: () {
              // Optional: Logic to flip camera could go here
            },
            child: Container(
              height: 150,
              width: 100,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade800),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(_localRenderer, mirror: !_isScreenSharing), // Don't mirror if sharing screen
              ),
            ),
          ),
        ),

        // C. CHAT PANEL OVERLAY
        if (_isChatOpen && roomId != null)
          Positioned(
            right: 16,
            bottom: 110, // Above control bar
            top: 60,     // Below header
            child: ChatPanel(
              roomId: roomId!,
              senderId: signaling.userId,
              onClose: () => setState(() => _isChatOpen = false),
            ),
          ),

        // D. ROOM ID HEADER
        Positioned(
          top: 50,
          left: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Text("Room: ${roomId ?? '...'}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _remoteVideoActive ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
        ),

        // E. BOTTOM CONTROL BAR
        Positioned(
          left: 0,
          right: 0,
          bottom: 20,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF3C4043),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Mic
                  _buildControlBtn(
                    icon: _micEnabled ? Icons.mic : Icons.mic_off,
                    color: _micEnabled ? Colors.white : Colors.black,
                    bgColor: _micEnabled ? Colors.transparent : Colors.white,
                    onPressed: _toggleMic,
                  ),
                  const SizedBox(width: 12),

                  // 2. Camera
                  _buildControlBtn(
                    icon: _camEnabled ? Icons.videocam : Icons.videocam_off,
                    color: _camEnabled ? Colors.white : Colors.black,
                    bgColor: _camEnabled ? Colors.transparent : Colors.white,
                    onPressed: _toggleCam,
                  ),
                  const SizedBox(width: 12),

                  // 3. Screen Share
                  _buildControlBtn(
                    icon: _isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
                    color: _isScreenSharing ? Colors.black : Colors.white,
                    bgColor: _isScreenSharing ? Colors.greenAccent : Colors.transparent,
                    onPressed: () async {
                      bool newStatus = !_isScreenSharing;
                      await signaling.switchScreenShare(newStatus);
                      setState(() {
                        _isScreenSharing = newStatus;
                        // Force update local view to show screen or camera
                        _localRenderer.srcObject = signaling.localStream;
                      });
                    },
                  ),
                  const SizedBox(width: 12),

                  // 4. Chat
                  _buildControlBtn(
                    icon: _isChatOpen ? Icons.chat_bubble : Icons.chat_bubble_outline,
                    color: _isChatOpen ? Colors.blueAccent : Colors.white,
                    bgColor: Colors.transparent,
                    onPressed: () => setState(() => _isChatOpen = !_isChatOpen),
                  ),
                  const SizedBox(width: 12),

                  // 5. Hang Up
                  _buildControlBtn(
                    icon: Icons.call_end,
                    color: Colors.white,
                    bgColor: Colors.red,
                    onPressed: () async {
                      await signaling.hangUp(_localRenderer);
                      setState(() {
                        _inCall = false;
                        roomId = null;
                        _remoteVideoActive = false;
                        _isScreenSharing = false;
                        _isChatOpen = false;
                        _localRenderer.srcObject = null;
                        _remoteRenderer.srcObject = null;
                      });

                      // Restart Camera for Green Room
                      if (mounted) {
                        await Future.delayed(const Duration(milliseconds: 500));
                        await signaling.openUserMedia(_localRenderer, _remoteRenderer);
                        setState(() {});
                      }
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
    Color bgColor = Colors.transparent,
  }) {
    return Material(
      color: bgColor,
      shape: const CircleBorder(),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }
}