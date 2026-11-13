import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../game/game_screen.dart';
import '../game/discussion_model.dart';
import '../game/discussion_widgets.dart';
import '../game/expansion_model.dart';
import '../game/expansion_widgets.dart';
import '../lobby/role_presets.dart';
import '../lobby/room_model.dart';
import '../solo/bot_difficulty.dart';
import '../solo/memory/match_history_screen.dart';
import '../solo/memory/match_repository.dart';
import '../solo/memory/social_memory.dart';
import '../solo/persona/bot_persona.dart';

class LocalPlayScreen extends StatefulWidget {
  const LocalPlayScreen(
      {super.key, this.solo = false, this.random, this.archive});
  final bool solo;

  /// Solo: decides who sits at the table, and where past games are kept.
  final Random? random;
  final MatchRepository? archive;

  @override
  State<LocalPlayScreen> createState() => _LocalPlayScreenState();
}

class _LocalPlayScreenState extends State<LocalPlayScreen> {
  int playerCount = 5;
  DiscussionSettings discussion = const DiscussionSettings();
  ExpansionSettings expansions = const ExpansionSettings();
  BotDifficulty difficulty = BotDifficulty.normal;
  final names = List.generate(10, (i) => '玩家${i + 1}');
  final roles = <String>{'梅林', '刺客', '派西維爾', '莫甘娜'};
  List<BotPersona> cast = const [];
  MatchRepository get _archive => widget.archive ?? MatchRepository.shared;
  @override
  void initState() {
    super.initState();
    if (widget.solo) {
      // the regulars: whoever sits in seats 2 to 10 this evening
      cast = BotPersona.deal(9, widget.random ?? Random());
      names.setAll(0, ['你', for (final p in cast) p.name]);
      discussion = DiscussionSettings.recommended;
    }
  }

  static const roleOptions = [
    ('梅林', '正義・固定'),
    ('刺客', '邪惡・固定'),
    ('派西維爾', '正義'),
    ('莫甘娜', '邪惡'),
    ('莫德雷德', '邪惡'),
    ('奧伯倫', '邪惡'),
  ];

  /// A new player count brings its recommended roles; everything can still
  /// be changed by hand afterwards.
  void _setPlayers(int count) {
    playerCount = count;
    // Lancelot cannot be played with fewer than 7
    if (count < lancelotMinPlayers) {
      expansions = expansions.copyWith(lancelot: 0);
    }
    final preset = rolePreset(count);
    if (preset == null) return;
    roles
      ..clear()
      ..addAll(['梅林', '刺客', for (final r in preset) r.label]);
  }

  Room get setup {
    // Reuse the rules engine's configuration without creating a shared room.
    final game = Room(
        code: '',
        players: List.generate(playerCount,
            (i) => Player(id: 'seat$i', name: names[i], isReady: true)));
    game.specialRoles
      ..clear()
      ..addAll(roles);
    game.discussion = discussion;
    game.expansions = expansions;
    return game;
  }

  /// Solo: who this computer player is and what they remember of you.
  Future<void> _showPersona(int index) async {
    final persona = cast[index - 1];
    final past = await _archive.summaries();
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('${index + 1} 號　${persona.name}'),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(persona.bio),
                    const SizedBox(height: 8),
                    Text(memorySummary(BotMemory.of(persona.id, past, 0)),
                        key: const ValueKey('personaRecord'),
                        style: const TextStyle(
                            fontSize: 12.5, color: AvalonTheme.muted)),
                    const SizedBox(height: 4),
                    const Text('每一局都會重新抽角色；他記得的是以前打完的局。',
                        style: TextStyle(
                            fontSize: 11.5, color: AvalonTheme.muted)),
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('關閉'))
              ],
            ));
  }

  Future<void> editName(int index) async {
    if (widget.solo && index > 0) return _showPersona(index);
    final name = await showDialog<String>(
        context: context,
        builder: (_) => _PlayerNameDialog(name: names[index]));
    if (mounted && name != null) setState(() => names[index] = name);
  }

  @override
  Widget build(BuildContext context) {
    final configuration = setup;
    final options = [
      ...roleOptions,
      if (expansions.lancelot > 0) ...[
        ('正義蘭斯洛特', '正義・擴充固定'),
        ('邪惡蘭斯洛特', '邪惡・擴充固定'),
      ],
    ];
    final evilCount = Room.evilCount(playerCount);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: FantasyBackground(
          child: SafeArea(
              child: Center(
                  child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                IconButton(
                    tooltip: '返回首頁',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                    color: AvalonTheme.gold,
                    constraints:
                        const BoxConstraints.tightFor(width: 36, height: 36),
                    padding: EdgeInsets.zero),
                const SizedBox(width: 8),
                Text(widget.solo ? '跟電腦遊玩' : '一機遊玩',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AvalonTheme.gold)),
                if (widget.solo) ...[
                  const SizedBox(width: 4),
                  IconButton(
                      key: const ValueKey('matchHistory'),
                      tooltip: '對局紀錄',
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) =>
                                  MatchHistoryScreen(repository: _archive))),
                      icon: const Icon(Icons.history),
                      color: AvalonTheme.gold,
                      constraints:
                          const BoxConstraints.tightFor(width: 36, height: 36),
                      padding: EdgeInsets.zero),
                  const SizedBox(width: 6),
                  PopupMenuButton<BotDifficulty>(
                    key: const ValueKey('botDifficulty'),
                    tooltip: '電腦難度',
                    initialValue: difficulty,
                    onSelected: (value) => setState(() => difficulty = value),
                    itemBuilder: (_) => [
                      for (final level in BotDifficulty.values)
                        PopupMenuItem(
                          key: ValueKey('botDifficulty_${level.name}'),
                          value: level,
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(level.label),
                                Text(level.description,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AvalonTheme.muted)),
                              ]),
                        ),
                    ],
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                          color: AvalonTheme.raised,
                          borderRadius: BorderRadius.circular(9)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('難度：${difficulty.label}',
                            style: const TextStyle(
                                fontSize: 12, color: AvalonTheme.gold)),
                        const Icon(Icons.arrow_drop_down,
                            size: 18, color: AvalonTheme.muted),
                      ]),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                    tooltip: '發言設定',
                    icon: const Icon(Icons.timer_outlined),
                    color: AvalonTheme.gold,
                    onPressed: () async {
                      final value = await editDiscussion(context, discussion);
                      if (mounted && value != null) {
                        setState(() => discussion = value);
                      }
                    }),
                const Text('人數',
                    style: TextStyle(color: AvalonTheme.muted, fontSize: 12)),
                const SizedBox(width: 8),
                ...List.generate(6, (i) {
                  final count = i + 5;
                  final active = playerCount == count;
                  return Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: SizedBox(
                        width: 34,
                        height: 34,
                        child: TextButton(
                            key: ValueKey('playerCount$count'),
                            style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                backgroundColor: active
                                    ? AvalonTheme.gold
                                    : AvalonTheme.raised,
                                foregroundColor:
                                    active ? AvalonTheme.bg : AvalonTheme.muted,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9))),
                            onPressed: () => setState(() => _setPlayers(count)),
                            child: Text('$count')),
                      ));
                }),
              ]),
              const SizedBox(height: 10),
              Expanded(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Expanded(
                        flex: 6,
                        child: GoldPanel(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SectionLabel(
                                      widget.solo ? '1 號是你・其餘是電腦' : '玩家暱稱'),
                                  const SizedBox(height: 8),
                                  ...List.generate(
                                      (playerCount + 1) ~/ 2,
                                      (row) => Expanded(
                                              child: Padding(
                                            padding: EdgeInsets.only(
                                                top: row == 0 ? 0 : 5),
                                            child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children:
                                                    List.generate(2, (column) {
                                                  final index =
                                                      row * 2 + column;
                                                  return Expanded(
                                                      child: Padding(
                                                    padding: EdgeInsets.only(
                                                        left: column == 0
                                                            ? 0
                                                            : 6),
                                                    child: index >= playerCount
                                                        ? const SizedBox
                                                            .shrink()
                                                        : Material(
                                                            color: AvalonTheme
                                                                .raised,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        9),
                                                            child: InkWell(
                                                              key: ValueKey(
                                                                  'playerName$index'),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          9),
                                                              onTap: () =>
                                                                  editName(
                                                                      index),
                                                              child: Padding(
                                                                  padding: const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          8),
                                                                  child: Row(
                                                                      children: [
                                                                        Text(
                                                                            '${index + 1}',
                                                                            style:
                                                                                const TextStyle(color: AvalonTheme.gold, fontWeight: FontWeight.bold)),
                                                                        const SizedBox(
                                                                            width:
                                                                                8),
                                                                        Expanded(
                                                                            child: Text(names[index],
                                                                                maxLines: 1,
                                                                                overflow: TextOverflow.ellipsis,
                                                                                style: const TextStyle(fontSize: 13))),
                                                                        Icon(
                                                                            widget.solo && index > 0
                                                                                ? Icons.person_outline
                                                                                : Icons.edit_outlined,
                                                                            size: 14,
                                                                            color: AvalonTheme.muted),
                                                                      ])),
                                                            ),
                                                          ),
                                                  ));
                                                })),
                                          ))),
                                ]))),
                    const SizedBox(width: 10),
                    Expanded(
                        flex: 5,
                        child: GoldPanel(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SectionLabel('角色配置'),
                                  const SizedBox(height: 8),
                                  ...List.generate(
                                      options.length ~/ 2,
                                      (row) => Expanded(
                                              child: Padding(
                                            padding: EdgeInsets.only(
                                                top: row == 0 ? 0 : 5),
                                            child: Row(
                                                children:
                                                    List.generate(2, (column) {
                                              final (role, side) =
                                                  options[row * 2 + column];
                                              final expansionRole =
                                                  role.endsWith('蘭斯洛特');
                                              final active = expansionRole ||
                                                  roles.contains(role);
                                              final required = expansionRole ||
                                                  role == '梅林' ||
                                                  role == '刺客';
                                              return Expanded(
                                                  child: Padding(
                                                padding: EdgeInsets.only(
                                                    left: column == 0 ? 0 : 6),
                                                child: Material(
                                                  color: active
                                                      ? AvalonTheme.violet
                                                          .withValues(alpha: .3)
                                                      : AvalonTheme.raised,
                                                  borderRadius:
                                                      BorderRadius.circular(9),
                                                  child: InkWell(
                                                    key: ValueKey('role$role'),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            9),
                                                    onTap: required
                                                        ? null
                                                        : () => setState(() {
                                                              active
                                                                  ? roles
                                                                      .remove(
                                                                          role)
                                                                  : roles.add(
                                                                      role);
                                                            }),
                                                    child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 8),
                                                        child: Row(children: [
                                                          Expanded(
                                                              child: FittedBox(
                                                                  fit: BoxFit
                                                                      .scaleDown,
                                                                  alignment:
                                                                      Alignment
                                                                          .centerLeft,
                                                                  child: Column(
                                                                      mainAxisAlignment:
                                                                          MainAxisAlignment
                                                                              .center,
                                                                      crossAxisAlignment:
                                                                          CrossAxisAlignment
                                                                              .start,
                                                                      children: [
                                                                        FittedBox(
                                                                            fit:
                                                                                BoxFit.scaleDown,
                                                                            alignment: Alignment.centerLeft,
                                                                            child: Text(role, style: TextStyle(fontSize: 13, color: active ? AvalonTheme.gold : Colors.white))),
                                                                        Text(
                                                                            side,
                                                                            style:
                                                                                const TextStyle(fontSize: 10, color: AvalonTheme.muted)),
                                                                      ]))),
                                                          Icon(
                                                              active
                                                                  ? Icons
                                                                      .check_circle
                                                                  : Icons
                                                                      .circle_outlined,
                                                              size: 16,
                                                              color: active
                                                                  ? AvalonTheme
                                                                      .gold
                                                                  : AvalonTheme
                                                                      .muted),
                                                        ])),
                                                  ),
                                                ),
                                              ));
                                            })),
                                          ))),
                                ]))),
                  ])),
              const SizedBox(height: 10),
              Row(children: [
                SizedBox(
                    width: 250,
                    height: 42,
                    child: ExpansionsButton(
                        settings: expansions,
                        onTap: () async {
                          final value = await editExpansions(
                              context, expansions,
                              players: playerCount);
                          if (mounted && value != null) {
                            setState(() => expansions = value);
                          }
                        })),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(
                        configuration.roleIssue ??
                            '正義 ${playerCount - evilCount} 人・邪惡 $evilCount 人，其他名額自動補齊',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: configuration.roleIssue == null
                                ? AvalonTheme.muted
                                : Colors.orangeAccent))),
                const SizedBox(width: 12),
                SizedBox(
                    width: 170,
                    height: 42,
                    child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(minimumSize: Size.zero),
                        onPressed: configuration.canStart
                            ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => widget.solo
                                        ? GameScreen.solo(
                                            room: configuration,
                                            difficulty: difficulty,
                                            cast: cast
                                                .take(playerCount - 1)
                                                .toList(),
                                            archive: _archive)
                                        : GameScreen(room: configuration)))
                            : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('開始遊戲'))),
              ]),
            ])),
      )))),
    );
  }
}

class _PlayerNameDialog extends StatefulWidget {
  const _PlayerNameDialog({required this.name});
  final String name;
  @override
  State<_PlayerNameDialog> createState() => _PlayerNameDialogState();
}

class _PlayerNameDialogState extends State<_PlayerNameDialog> {
  late final controller = TextEditingController(text: widget.name);
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final value = controller.text.trim();
    if (value.isEmpty || value.length > 16) {
      setState(() => error = '請輸入 1～16 字的暱稱');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('修改暱稱'),
        content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 16,
            decoration: InputDecoration(labelText: '玩家暱稱', errorText: error),
            onSubmitted: (_) => submit()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: submit, child: const Text('儲存')),
        ],
      );
}
