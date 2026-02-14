import 'package:flutter_webrtc/flutter_webrtc.dart';

class MediaService {
  final Map<String, dynamic> _mediaConstraints = {
    'audio': true,
    'video': {
      'facingMode': 'user',
      'width': '1280',
      'height': '720',
      'frameRate': '30',
    },
  };

  Future<MediaStream> openUserMedia() async {
    try {
      MediaStream stream = await navigator.mediaDevices.getUserMedia(_mediaConstraints);
      return stream;
    } catch (e) {
      print("Error accessing media devices: $e");
      rethrow;
    }
  }
}