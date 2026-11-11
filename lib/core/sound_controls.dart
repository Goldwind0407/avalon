import 'package:flutter/material.dart';
import 'game_sounds.dart';

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

Future<void> showSoundSettings(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => ListenableBuilder(
        listenable: GameSounds.instance,
        builder: (context, _) {
          final sound = GameSounds.instance;
          return AlertDialog(
              title: const Text('遊戲音效'),
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
