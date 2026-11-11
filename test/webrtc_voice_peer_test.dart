import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:avalon_shadow_council/features/online/voice/webrtc_voice_audio.dart';

class AudioTrack implements MediaStreamTrack {
  @override
  String get kind => 'audio';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Sender implements RTCRtpSender {
  @override
  String get senderId => 'audio-sender';
  MediaStreamTrack? attached;
  final replacements = <MediaStreamTrack?>[];
  @override
  final parameters = RTCRtpParameters(encodings: [RTCRtpEncoding()]);
  @override
  Future<void> replaceTrack(MediaStreamTrack? track) async {
    attached = track;
    replacements.add(track);
  }

  @override
  Future<bool> setParameters(RTCRtpParameters parameters) async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Receiver implements RTCRtpReceiver {
  @override
  final track = AudioTrack();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Transceiver implements RTCRtpTransceiver {
  @override
  final Sender sender = Sender();
  @override
  final receiver = Receiver();
  TransceiverDirection? direction;
  @override
  Future<void> setDirection(TransceiverDirection value) async {
    direction = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Connection extends RTCPeerConnection {
  int added = 0, remoteDescriptions = 0;
  final Transceiver transceiver = Transceiver();
  @override
  Future<List<RTCRtpSender>> getSenders() async => [transceiver.sender];
  @override
  Future<RTCRtpTransceiver> addTransceiver(
      {MediaStreamTrack? track,
      RTCRtpMediaType? kind,
      RTCRtpTransceiverInit? init}) async {
    added++;
    return transceiver;
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    remoteDescriptions++;
  }

  @override
  Future<List<RTCRtpTransceiver>> getTransceivers() async {
    expect(remoteDescriptions, greaterThan(0));
    return [transceiver];
  }

  @override
  Future<RTCSessionDescription> createOffer(
          [Map<String, dynamic>? constraints]) async =>
      RTCSessionDescription('offer-sdp', 'offer');
  @override
  Future<RTCSessionDescription> createAnswer(
          [Map<String, dynamic>? constraints]) async =>
      RTCSessionDescription('answer-sdp', 'answer');
  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('answerer sends on the offered transceiver without adding an unused one',
      () async {
    final connection = Connection();
    final peer = WebRtcVoicePeer(connection);
    final track = AudioTrack();
    await peer.setTrack(track);
    expect(connection.transceiver.sender.attached, isNull);
    await peer.acceptOffer({'type': 'offer', 'sdp': 'offer-sdp'});
    expect(connection.added, 0);
    expect(connection.transceiver.direction, TransceiverDirection.SendRecv);
    expect(connection.transceiver.sender.attached, same(track));
    expect(
        connection.transceiver.sender.parameters.encodings!.single.maxBitrate,
        24000);
    await peer.setTrack(null);
    expect(connection.transceiver.sender.attached, isNull);
    // Opening mic later uses the same negotiated sender, without another offer.
    await peer.setTrack(track);
    expect(connection.added, 0);
    expect(connection.remoteDescriptions, 1);
  });

  test('offerer creates one audio transceiver, initially with no capture track',
      () async {
    final connection = Connection();
    final peer = WebRtcVoicePeer(connection);
    await peer.createOffer();
    expect(connection.added, 1);
    expect(connection.transceiver.sender.attached, isNull);
    await peer.acceptAnswer({'type': 'answer', 'sdp': 'answer-sdp'});
    final track = AudioTrack();
    await peer.setTrack(track);
    expect(connection.transceiver.sender.attached, same(track));
    expect(connection.added, 1);
  });
}
