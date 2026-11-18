import 'package:material_ui/material_ui.dart';
import 'bot_voices.dart';
import 'game_sounds.dart';
import 'toast.dart';

class SoundSettingsButton extends StatelessWidget {
  const SoundSettingsButton({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: GameSounds.instance,
      builder: (context, _) => IconButton(
          tooltip: '音效設定',
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          padding: EdgeInsets.zero,
          iconSize: 20,
          icon: Icon(
              GameSounds.instance.enabled && GameSounds.instance.volume > 0
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined),
          onPressed: () => showSoundSettings(context)));
}

/// Whose voice was tried last, so the next try is someone else.
String? _lastSample;

Future<void> showSoundSettings(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
        listenable: Listenable.merge([GameSounds.instance, BotVoices.instance]),
        builder: (context, _) {
          final sound = GameSounds.instance;
          final voices = BotVoices.instance;
          return AlertDialog(
              title: const Text('遊戲音效'),
              // phones are held sideways: the settings scroll when tall
              scrollable: true,
              content: SizedBox(
                  width: 340,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('開啟音效'),
                        value: sound.enabled,
                        onChanged: sound.setEnabled),
                    Row(children: [
                      const Icon(Icons.volume_down_outlined),
                      Expanded(
                          child: Slider(
                              value: sound.volume,
                              onChanged: sound.enabled ? sound.setVolume : null,
                              onChangeEnd: (_) => sound.play(GameSound.turn))),
                      Text('${(sound.volume * 100).round()}%')
                    ]),
                    const Text('只影響遊戲音效，不會關閉多人語音。',
                        style: TextStyle(fontSize: 12)),
                    const Divider(height: 24),
                    SwitchListTile(
                        key: const ValueKey('botVoices'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('電腦玩家語音'),
                        subtitle: const Text('電腦的台詞會念出來。聲音由 AI 生成，不是真人錄音',
                            style: TextStyle(fontSize: 12)),
                        value: voices.enabled,
                        onChanged: voices.setEnabled),
                    Row(children: [
                      const Icon(Icons.record_voice_over_outlined),
                      Expanded(
                          child: Slider(
                              value: voices.volume,
                              onChanged:
                                  voices.enabled ? voices.setVolume : null)),
                      Text('${(voices.volume * 100).round()}%')
                    ]),
                    Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                            key: const ValueKey('tryBotVoice'),
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('試聽電腦語音'),
                            onPressed: voices.enabled
                                ? () async {
                                    final who = await voices.trySample(
                                        after: _lastSample);
                                    _lastSample = who ?? _lastSample;
                                    if (who == null && context.mounted) {
                                      showToast(context, '還沒有錄好的電腦語音');
                                    }
                                  }
                                : null)),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => sound.play(GameSound.turn),
                    child: const Text('試聽')),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('完成'))
              ]);
        }));
