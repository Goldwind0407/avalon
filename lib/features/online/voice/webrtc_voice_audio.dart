import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'voice_controller.dart';
import 'voice_mesh.dart';
import 'webrtc_voice_transport.dart';

/// One capture stream shared by all senders. Muting stops its physical tracks;
/// replacing tracks on the negotiated audio transceivers needs no new SDP.
class WebRtcVoiceAudio implements VoiceAudio {
  WebRtcVoiceAudio({Future<List<Map<String, dynamic>>> Function()? iceServers})
      : _iceServers = iceServers ??
            (() async => [
                  {'urls': 'stun:stun.l.google.com:19302'}
                ]);
  final Future<List<Map<String, dynamic>>> Function() _iceServers;
  final _peers = <WebRtcVoicePeer>{};
  MediaStream? _stream;
  List<Map<String, dynamic>> _servers = [];
  bool _closed = false;
  int _captureGeneration = 0;

  @override
  Future<void> initialize() async {
    _servers = await _iceServers();
    if (_closed) return;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await Helper.setAppleAudioIOMode(AppleAudioIOMode.remoteOnly,
          preferSpeakerOutput: true);
      await Helper.ensureAudioSession();
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await Helper.setSpeakerphoneOnButPreferBluetooth();
    }
  }

  @override
  Future<VoicePeer> createPeer() async {
    final pc = await createPeerConnection({
      'iceServers': _servers,
      'sdpSemantics': 'unified-plan',
    });
    final peer = WebRtcVoicePeer(pc);
    try {
      if (_closed) throw const VoiceException('語音已斷線');
      _peers.add(peer);
      peer.onClosed = () => _peers.remove(peer);
      await peer.setTrack(_stream?.getAudioTracks().firstOrNull);
      if (_closed) throw const VoiceException('語音已斷線');
      await peer.initializePlayback();
      return peer;
    } catch (_) {
      await peer.close();
      rethrow;
    }
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    final generation = ++_captureGeneration;
    if (!enabled) {
      await _stopCapture();
      return;
    }
    if (_closed) throw const VoiceException('語音已斷線');
    if (_stream != null) return;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await Helper.setAppleAudioIOMode(AppleAudioIOMode.localAndRemote,
            preferSpeakerOutput: true);
      }
      if (_closed || generation != _captureGeneration) return;
      // getUserMedia is reached ONLY by the player's mic button.
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'channelCount': 1
        },
        'video': false,
      });
      if (_closed || generation != _captureGeneration) {
        await _release(stream);
        return;
      }
      _stream = stream;
      final track = stream.getAudioTracks().first;
      await Future.wait([
        for (final peer in [..._peers]) peer.setTrack(track)
      ]);
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android)) {
        await Helper.setSpeakerphoneOnButPreferBluetooth();
      }
    } catch (_) {
      if (!_closed && generation == _captureGeneration) await _stopCapture();
      rethrow;
    }
  }

  Future<void> _release(MediaStream stream) async {
    try {
      await Future.wait([for (final track in stream.getTracks()) track.stop()]);
    } finally {
      await stream.dispose();
    }
  }

  Future<void> _stopCapture() async {
    final generation = _captureGeneration;
    final stream = _stream;
    _stream = null;
    // Stop hardware immediately; replacing the sender is only cleanup.
    if (stream != null) await _release(stream);
    if (generation != _captureGeneration) return;
    await Future.wait([
      for (final peer in [..._peers]) peer.setTrack(null)
    ]);
    if (generation != _captureGeneration) return;
    if (!_closed && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await Helper.setAppleAudioIOMode(AppleAudioIOMode.remoteOnly,
          preferSpeakerOutput: true);
    }
  }

  @override
  Future<double> localLevel() async {
    for (final peer in [..._peers]) {
      if (peer.closed) continue;
      return _level(await peer.pc.getStats(), {'media-source', 'outbound-rtp'});
    }
    return 0;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++_captureGeneration;
    try {
      await _stopCapture();
    } finally {
      await Future.wait([
        for (final peer in [..._peers]) peer.close()
      ]);
    }
  }
}

double _level(List<StatsReport> stats, Set<String> types) {
  var level = 0.0;
  for (final report in stats) {
    if (!types.contains(report.type)) continue;
    final value = double.tryParse('${report.values['audioLevel']}') ?? 0;
    if (value > level) level = value;
  }
  return level;
}

class WebRtcVoicePeer extends VoicePeer {
  WebRtcVoicePeer(this.pc) {
    pc.onIceCandidate = (candidate) {
      if (!closed && (candidate.candidate?.isNotEmpty ?? false)) {
        onCandidate?.call(candidate.toMap());
      }
    };
    pc.onConnectionState = (state) {
      if (closed) return;
      onState?.call(switch (state) {
        RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
          PeerState.connected,
        RTCPeerConnectionState.RTCPeerConnectionStateFailed => PeerState.failed,
        RTCPeerConnectionState.RTCPeerConnectionStateClosed => PeerState.closed,
        _ => PeerState.connecting,
      });
      _disconnectTimer?.cancel();
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _disconnectTimer = Timer(
            const Duration(seconds: 8), () => onState?.call(PeerState.failed));
      }
    };
    pc.onTrack = (event) {
      if (!closed && event.track.kind == 'audio') {
        _remoteTracks.add(event.track);
        event.track.enabled = _playbackAllowed;
        if (kIsWeb) unawaited(_playRemote(event));
      }
    };
  }
  final RTCPeerConnection pc;
  RTCRtpTransceiver? transceiver;
  void Function()? onClosed;
  RTCVideoRenderer? _renderer;
  MediaStream? _playbackStream;
  MediaStreamTrack? _track;
  Timer? _disconnectTimer;
  bool closed = false;
  bool _playbackAllowed = true;
  final _remoteTracks = <MediaStreamTrack>[];
  @override
  void setPlaybackEnabled(bool enabled) {
    _playbackAllowed = enabled;
    if (closed) return;
    for (final track in _remoteTracks) {
      track.enabled = enabled;
    }
    if (_renderer != null) _renderer!.muted = !enabled;
  }

  Future<void> initializePlayback() async {
    // Native WebRTC plays audio automatically. Web requires a media element.
    if (kIsWeb) {
      final renderer = _renderer = RTCVideoRenderer();
      await renderer.initialize();
      if (closed) await renderer.dispose();
    }
  }

  Future<void> setTrack(MediaStreamTrack? track) async {
    _track = track;
    if (!closed) await transceiver?.sender.replaceTrack(track);
  }

  Future<void> _playRemote(RTCTrackEvent event) async {
    try {
      MediaStream stream;
      if (event.streams.isNotEmpty) {
        stream = event.streams.first;
      } else {
        // A sender negotiated before it has a mic track can be streamless.
        stream = await createLocalMediaStream('voice-playback');
        if (closed) {
          await stream.dispose();
          return;
        }
        _playbackStream = stream;
        await stream.addTrack(event.track);
      }
      if (!closed) _renderer?.srcObject = stream;
      if (!closed && _renderer != null) _renderer!.muted = !_playbackAllowed;
    } catch (_) {
      if (!closed) onState?.call(PeerState.failed);
    }
  }

  static const _constraints = <String, dynamic>{
    'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': false},
    'optional': <dynamic>[],
  };

  @override
  Future<Map<String, dynamic>> createOffer() async {
    transceiver = await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(
            direction: TransceiverDirection.SendRecv,
            sendEncodings: [RTCRtpEncoding(maxBitrate: 24000)]));
    await setTrack(_track);
    final description = await pc.createOffer(_constraints);
    await pc.setLocalDescription(description);
    return description.toMap();
  }

  @override
  Future<Map<String, dynamic>> acceptOffer(Map<String, dynamic> offer) async {
    await pc.setRemoteDescription(RTCSessionDescription(offer['sdp'], 'offer'));
    // Reuse the remote offer's transceiver. Pre-adding one on the answerer
    // would leave its sender unassociated and result in one-way audio.
    transceiver = (await pc.getTransceivers())
        .firstWhere((t) => t.receiver.track?.kind == 'audio');
    await transceiver!.setDirection(TransceiverDirection.SendRecv);
    await setTrack(_track);
    final answer = await pc.createAnswer(_constraints);
    await pc.setLocalDescription(answer);
    await _limitBitrate();
    return answer.toMap();
  }

  @override
  Future<void> acceptAnswer(Map<String, dynamic> answer) async {
    await pc
        .setRemoteDescription(RTCSessionDescription(answer['sdp'], 'answer'));
    await _limitBitrate();
  }

  Future<void> _limitBitrate() async {
    // getSenders refreshes the native parameters after negotiation; the
    // transceiver's earlier snapshot may still have no encodings.
    final sender = (await pc.getSenders())
        .firstWhere((s) => s.senderId == transceiver!.sender.senderId);
    final parameters = sender.parameters;
    if (parameters.encodings?.isNotEmpty ?? false) {
      for (final encoding in parameters.encodings!) {
        encoding.maxBitrate = 24000;
      }
      await sender.setParameters(parameters);
    }
  }

  @override
  Future<void> addCandidate(Map<String, dynamic> candidate) =>
      pc.addCandidate(RTCIceCandidate(candidate['candidate'],
          candidate['sdpMid'], (candidate['sdpMLineIndex'] as num?)?.toInt()));

  @override
  Future<double> remoteLevel() async =>
      _level(await pc.getStats(), {'inbound-rtp'});

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    _disconnectTimer?.cancel();
    onClosed?.call();
    try {
      await pc.close();
    } finally {
      await pc.dispose();
      await _renderer?.dispose();
      await _playbackStream?.dispose();
    }
  }
}
