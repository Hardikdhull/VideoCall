import 'package:flutter/cupertino.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/material.dart';
import 'package:video_call/widgets/video_renderer.dart';

import '../service/media_service.dart';

class CallPage extends StatefulWidget {
  @override
  _CallPageState createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }
  MediaStream? _localStream;
  bool _isMicOn = true;
  bool _isCamOn = true;



  Future<void> _setupMedia() async {
    await _localRenderer.initialize();

    _localStream = await MediaService().openUserMedia();

    setState(() {
      _localRenderer.srcObject = _localStream;
    });
  }

  // Toggle Microphone
  void _toggleMic() {
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !track.enabled;
      setState(() => _isMicOn = track.enabled);
    });
  }

  // Toggle Camera
  void _toggleCamera() {
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = !track.enabled;
      setState(() => _isCamOn = track.enabled);
    });
  }

  @override
  void dispose() {
    _localStream?.dispose();
    _localRenderer.dispose();
    super.dispose();
  }

  _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: OrientationBuilder(builder: (context, orientation) {
                  return GridView.count(
                    crossAxisCount: orientation == Orientation.portrait ? 1 : 2,
                    children: [
                      VideoView(renderer: _localRenderer, isLocal: true),
                      VideoView(renderer: _remoteRenderer),
                    ],
                  );
                }),
              ),
            ),

            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: EdgeInsets.only(bottom: 20),
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[900]?.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: Icon(Icons.mic, color: Colors.white), onPressed: () {}),
                    IconButton(icon: Icon(Icons.videocam, color: Colors.white), onPressed: () {}),
                    SizedBox(width: 20),
                    FloatingActionButton(
                      backgroundColor: Colors.red,
                      onPressed: () => Navigator.pop(context),
                      child: Icon(Icons.call_end),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}