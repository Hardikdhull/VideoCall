import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../screens/signaling.dart';

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
  bool _isLoading = false;
  bool _remoteVideoActive = false; // Track if remote video is actually showing

  @override
  void initState() {
    super.initState();
    _initializeRenderers();

    // CRITICAL: Set the callback BEFORE any room operations
    signaling.onAddRemoteStream = ((stream) {
      print('UI: Received remote stream callback');
      print('UI: Stream has ${stream.getVideoTracks().length} video tracks');
      print('UI: Stream has ${stream.getAudioTracks().length} audio tracks');

      setState(() {
        _remoteRenderer.srcObject = stream;
        _remoteVideoActive = true;
      });

      print('UI: Remote renderer srcObject updated');
    });
  }

  Future<void> _initializeRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    print('UI: Renderers initialized');

    // Auto-start camera
    try {
      await signaling.openUserMedia(_localRenderer, _remoteRenderer);
      setState(() {});
      print('UI: User media opened successfully');
    } catch (e) {
      print("ERROR: Error opening user media: $e");
    }
  }

  // --- FIXED TOGGLE LOGIC ---
  void _toggleMic() {
    var tracks = signaling.localStream?.getAudioTracks();

    if (tracks != null && tracks.isNotEmpty) {
      bool newStatus = !tracks[0].enabled;
      tracks[0].enabled = newStatus;

      setState(() {
        _micEnabled = newStatus;
      });
      print("UI: Mic enabled: $newStatus");
    } else {
      print("ERROR: No audio tracks found to toggle.");
    }
  }

  void _toggleCam() {
    var tracks = signaling.localStream?.getVideoTracks();

    if (tracks != null && tracks.isNotEmpty) {
      bool newStatus = !tracks[0].enabled;
      tracks[0].enabled = newStatus;

      setState(() {
        _camEnabled = newStatus;
      });
      print("UI: Camera enabled: $newStatus");
    } else {
      print("ERROR: No video tracks found to toggle.");
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
                        Icon(_micEnabled ? Icons.mic : Icons.mic_off,
                            color: Colors.white),
                        const SizedBox(width: 8),
                        Icon(_camEnabled ? Icons.videocam : Icons.videocam_off,
                            color: Colors.white),
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
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8)),
                  child: SelectableText(
                    "Room ID: $roomId",
                    style: const TextStyle(
                        color: Colors.blueAccent, fontWeight: FontWeight.bold),
                  ),
                ),
              const SizedBox(height: 16),

              // CREATE ROOM BUTTON
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: _isLoading
                          ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.black, strokeWidth: 2))
                          : const Icon(Icons.add),
                      label: Text(_isLoading ? "Creating..." : "Create (Random)"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8AB4F8),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _isLoading
                          ? null
                          : () async {
                        setState(() => _isLoading = true);
                        try {
                          // GENERATE RANDOM 4-DIGIT CODE
                          String randomCode = (1000 +
                              (DateTime.now().millisecondsSinceEpoch %
                                  9000))
                              .toString();

                          print('UI: Creating room with code: $randomCode');

                          // Use the random code as the ID
                          roomId = await signaling.createRoom(
                              randomCode, _remoteRenderer);

                          textEditingController.text = roomId!;
                          setState(() {
                            _inCall = true;
                            _remoteVideoActive = false; // Reset remote video status
                          });
                          print('UI: Room created, entered call state');
                        } catch (e) {
                          print("ERROR: Failed to create room: $e");
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error: $e")));
                        } finally {
                          setState(() => _isLoading = false);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // JOIN ROOM ROW
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textEditingController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: "Enter 4-digit code",
                        prefixIcon: const Icon(Icons.dialpad),
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
                    onPressed: () async {
                      if (textEditingController.text.isEmpty) return;

                      print('UI: Joining room: ${textEditingController.text.trim()}');

                      // Join using the typed code
                      await signaling.joinRoom(
                        textEditingController.text.trim(),
                        _remoteRenderer,
                      );

                      setState(() {
                        roomId = textEditingController.text.trim();
                        _inCall = true;
                        _remoteVideoActive = false; // Will be set to true when stream arrives
                      });

                      print('UI: Joined room, entered call state');
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 24),
                    ),
                    child: const Text("Join"),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInCallUI() {
    return Stack(
      children: [
        // 1. Remote Video (Fills Screen)
        Positioned.fill(
          child: Container(
            color: Colors.black87,
            child: Stack(
              children: [
                // A. Placeholder text (Shows if video is missing/loading)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        _remoteVideoActive
                            ? "Connected"
                            : "Waiting for Remote Video...",
                        style: const TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                // B. The Actual Remote Video
                RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: false, // Don't mirror remote video
                ),
              ],
            ),
          ),
        ),

        // 2. Local Video (Floating PiP)
        Positioned(
          right: 16,
          bottom: 100, // Above the control bar
          child: Container(
            height: 150,
            width: 100,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade800),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  // Placeholder for self (if camera fails)
                  const Center(
                      child: Icon(Icons.videocam_off, color: Colors.grey)),
                  // The Actual Local Video
                  RTCVideoView(_localRenderer, mirror: true),
                ],
              ),
            ),
          ),
        ),

        // 3. Room ID Overlay (Top Center)
        Positioned(
          top: 50,
          left: 20,
          right: 20,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(
                    "Room ID: ${roomId ?? 'Connecting...'}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Connection status indicator
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _remoteVideoActive ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 4. Control Bar (Bottom Center)
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
                  // Mic Button
                  _buildControlBtn(
                    icon: _micEnabled ? Icons.mic : Icons.mic_off,
                    color: _micEnabled ? Colors.white : Colors.red,
                    onPressed: _toggleMic,
                  ),
                  const SizedBox(width: 16),

                  // Camera Button
                  _buildControlBtn(
                    icon: _camEnabled ? Icons.videocam : Icons.videocam_off,
                    color: _camEnabled ? Colors.white : Colors.red,
                    onPressed: _toggleCam,
                  ),
                  const SizedBox(width: 16),

                  // Debug Button (Temporary - for diagnostics)
                  _buildControlBtn(
                    icon: Icons.bug_report,
                    color: Colors.white,
                    bgColor: Colors.purple,
                    onPressed: () async {
                      print('UI: Running diagnostics...');
                      await signaling.logConnectionDetails();
                    },
                  ),
                  const SizedBox(width: 16),

                  // Hang Up Button
                  _buildControlBtn(
                    icon: Icons.call_end,
                    color: Colors.white,
                    bgColor: Colors.red,
                    onPressed: () async {
                      print('UI: Hang up button pressed');

                      // 1. Hang up the call
                      await signaling.hangUp(_localRenderer);

                      // 2. Clear the UI state
                      setState(() {
                        _inCall = false;
                        roomId = null;
                        _remoteVideoActive = false;
                        // Wipe the renderers to prevent "frozen" frames
                        _localRenderer.srcObject = null;
                        _remoteRenderer.srcObject = null;
                      });

                      print('UI: Call ended, returning to green room');

                      // 3. RESTART CAMERA for the Green Room
                      if (mounted) {
                        // Small delay to ensure previous tracks are fully dead
                        await Future.delayed(const Duration(milliseconds: 500));
                        print("UI: Restarting camera for waiting room...");

                        // Re-initialize the local stream
                        try {
                          await signaling.openUserMedia(
                              _localRenderer, _remoteRenderer);
                          // Force UI refresh
                          setState(() {});
                          print('UI: Camera restarted successfully');
                        } catch (e) {
                          print('ERROR: Failed to restart camera: $e');
                        }
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
    Color bgColor = const Color(0xFF3C4043), // Default Google Meet dark grey
  }) {
    return Material(
      color: bgColor,
      shape: const CircleBorder(),
      clipBehavior: Clip.hardEdge, // Constraints the ripple to the circle
      child: InkWell(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(15),
          child: Icon(icon, color: color, size: 28),
        ),
      ),
    );
  }
}