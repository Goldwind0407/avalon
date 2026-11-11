import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import 'voice_controller.dart';

class VoiceControls extends StatelessWidget {
  const VoiceControls(
      {super.key,
      required this.voice,
      this.names = const {},
      this.compact = false});
  final VoiceController voice;
  final Map<String, String> names;
  final bool compact;

  Future<void> _join(BuildContext context) async {
    await voice.join();
    if (context.mounted && voice.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(voice.error!)));
    }
  }

  Future<void> _microphone(BuildContext context) async {
    await voice.toggleMicrophone();
    if (context.mounted && voice.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(voice.error!)));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: voice,
      builder: (context, _) {
        final connected = voice.connected;
        final speaking =
            voice.speakers.map((id) => names[id] ?? '玩家').join('、');
        final label = switch (voice.status) {
          VoiceStatus.offline => '加入語音',
          VoiceStatus.connecting => '語音連線中',
          VoiceStatus.connected => speaking.isNotEmpty
              ? '$speaking 說話中'
              : voice.participants == 0
                  ? '等待其他人加入'
                  : '語音 ${voice.connections}/${voice.participants} 人',
          VoiceStatus.reconnecting => '語音重連中',
          VoiceStatus.failed => '重試語音',
        };
        final canJoin = voice.status == VoiceStatus.offline ||
            voice.status == VoiceStatus.failed;
        Widget icon(IconData icon, String tooltip, VoidCallback? action) =>
            IconButton(
              tooltip: tooltip,
              onPressed: action,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 34),
              iconSize: 20,
              color: AvalonTheme.gold,
              icon: Icon(icon),
            );
        if (canJoin) {
          return Tooltip(
              message: voice.error ?? label,
              child: compact
                  ? icon(Icons.headset, label, () => _join(context))
                  : TextButton.icon(
                      onPressed: () => _join(context),
                      icon: const Icon(Icons.headset, size: 18),
                      label: Text(label),
                      style: TextButton.styleFrom(minimumSize: Size.zero)));
        }
        return Row(mainAxisSize: MainAxisSize.min, children: [
          if (!compact)
            SizedBox(
                width: 110,
                child: Tooltip(
                    message: connected && voice.connections < voice.participants
                        ? '$label；部分玩家尚未連上，請離開語音再加入，或切換 Wi-Fi／行動網路後重試。'
                        : label,
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: speaking.isEmpty
                                ? AvalonTheme.muted
                                : AvalonTheme.green)))),
          icon(
              voice.microphone ? Icons.mic : Icons.mic_off,
              voice.microphone ? '關閉麥克風' : '開啟麥克風',
              connected && !voice.microphoneBusy
                  ? () => _microphone(context)
                  : null),
          icon(Icons.call_end, '離開語音', () => voice.leave()),
        ]);
      });
}

/// Only this little indicator rebuilds on active-speaker changes.
class VoiceSpeakingMark extends StatelessWidget {
  const VoiceSpeakingMark({super.key, required this.voice, required this.uid});
  final VoiceController voice;
  final String uid;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: voice,
      builder: (context, child) => SizedBox(
          width: 16,
          child: voice.isSpeaking(uid)
              ? const Tooltip(
                  message: '說話中',
                  child:
                      Icon(Icons.volume_up, size: 14, color: AvalonTheme.green))
              : const SizedBox.shrink()));
}
