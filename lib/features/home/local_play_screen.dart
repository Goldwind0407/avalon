import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../game/game_screen.dart';
import '../game/discussion_model.dart';
import '../game/discussion_widgets.dart';
import '../game/game_model.dart';
import '../game/expansion_model.dart';
import '../game/expansion_widgets.dart';
import '../lobby/role_presets.dart';
import '../lobby/room_model.dart';
import '../lobby/setup_widgets.dart';
import '../solo/bot_difficulty.dart';
import '../solo/memory/match_history_screen.dart';
import '../solo/memory/match_repository.dart';
import '../solo/memory/player_model.dart';
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
    final preset = rolePreset(count, lancelot: expansions.lancelot > 0);
    if (preset == null) return;
    roles
      ..clear()
      ..addAll(['梅林', '刺客', for (final r in preset) r.label]);
  }

  /// New expansion settings. Switching Lancelot on makes room for the evil
  /// Lancelot by dropping evil roles; switching it off brings the preset
  /// back if the roles were only the preset made to fit.
  void _setExpansions(ExpansionSettings value) {
    final was = expansions.lancelot > 0, now = value.lancelot > 0;
    expansions = value;
    if (was == now) return;
    final extra = {
      for (final r in Role.values)
        if (roles.contains(r.label) && r != Role.merlin && r != Role.assassin) r
    };
    final Set<Role> next;
    if (now) {
      next = fitForLancelot(playerCount, extra);
    } else {
      final fitted = rolePreset(playerCount, lancelot: true);
      next = fitted != null && setEquals(fitted, extra)
          ? rolePreset(playerCount)!
          : extra;
    }
    roles
      ..clear()
      ..addAll(['梅林', '刺客', for (final r in next) r.label]);
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
                    // what this computer player has learned of your habits
                    for (final line
                        in playerModelLines(PlayerModel.of(persona.id, past)))
                      Text('・$line',
                          style: const TextStyle(
                              fontSize: 12, color: AvalonTheme.muted)),
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
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(children: [
              _header(context),
              const SizedBox(height: 10),
              Expanded(
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Expanded(flex: 6, child: _players()),
                    const SizedBox(width: 10),
                    Expanded(flex: 5, child: _roles(options)),
                  ])),
              const SizedBox(height: 10),
              _footer(context, configuration, evilCount),
            ])),
      )))),
    );
  }

  /// On the narrowest phones the speaking-order chip shows its icon only
  /// and the count needs no label.
  Widget _header(BuildContext context) => LayoutBuilder(
      builder: (context, box) =>
          _headerRow(context, compact: box.maxWidth < 760));

  Widget _headerRow(BuildContext context, {required bool compact}) =>
      Row(children: [
        ScreenTitle(widget.solo ? '跟電腦遊玩' : '一機遊玩', backTooltip: '返回首頁'),
        const SizedBox(width: 12),
        // the settings give way (scale down) before anything overflows
        Expanded(
            child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (widget.solo) ...[
                        RoundIconButton(
                            key: const ValueKey('matchHistory'),
                            icon: Icons.history,
                            tooltip: '對局紀錄',
                            size: 34,
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                    builder: (_) => MatchHistoryScreen(
                                        repository: _archive)))),
                        const SizedBox(width: 8),
                        PopupMenuButton<BotDifficulty>(
                          key: const ValueKey('botDifficulty'),
                          tooltip: '電腦難度',
                          initialValue: difficulty,
                          onSelected: (value) =>
                              setState(() => difficulty = value),
                          itemBuilder: (_) => [
                            for (final level in BotDifficulty.values)
                              PopupMenuItem(
                                key: ValueKey('botDifficulty_${level.name}'),
                                value: level,
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(level.label),
                                      Text(level.description,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AvalonTheme.muted)),
                                    ]),
                              ),
                          ],
                          child: IgnorePointer(
                            child: SettingChip(
                                icon: Icons.psychology_outlined,
                                label: '難度：${difficulty.label}',
                                onTap: () {},
                                trailing: const Icon(Icons.arrow_drop_down,
                                    size: 18, color: AvalonTheme.muted)),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      SettingChip(
                          icon: Icons.timer_outlined,
                          label: compact
                              ? ''
                              : (discussion.enabled ? '依序發言' : '自由討論'),
                          tooltip: discussion.enabled ? '依序發言' : '自由討論',
                          highlight: discussion.enabled,
                          onTap: () async {
                            final value =
                                await editDiscussion(context, discussion);
                            if (mounted && value != null) {
                              setState(() => discussion = value);
                            }
                          }),
                    ])))),
        const SizedBox(width: 10),
        if (!compact) ...[
          const Text('人數',
              style: TextStyle(
                  color: AvalonTheme.muted, fontSize: 12, letterSpacing: 1)),
          const SizedBox(width: 8),
        ],
        PillSelector<int>(
            values: const [5, 6, 7, 8, 9, 10],
            selected: playerCount,
            label: (count) => '$count',
            keyOf: (count) => ValueKey('playerCount$count'),
            onSelected: (count) => setState(() => _setPlayers(count))),
      ]);

  Widget _players() => GoldPanel(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionLabel(widget.solo ? '座位・1 號是你，其餘是電腦' : '座位・點一下修改暱稱'),
        const SizedBox(height: 9),
        Expanded(child: SetupGrid(count: playerCount, cell: _seat)),
      ]));

  Widget _seat(int index) {
    final bot = widget.solo && index > 0;
    final style = bot ? cast[index - 1].style.label : null;
    return SetupSeat(
        tapKey: ValueKey('playerName$index'),
        number: index + 1,
        name: names[index],
        highlight: index == 0 && widget.solo,
        onTap: () => editName(index),
        trailing: [
          if (style != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(style,
                  style: const TextStyle(
                      fontSize: 10.5, color: AvalonTheme.muted)),
            ),
          Icon(bot ? Icons.info_outline : Icons.edit_outlined,
              size: 14, color: AvalonTheme.muted),
        ]);
  }

  Widget _roles(List<(String, String)> options) => GoldPanel(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionLabel('角色配置'),
        const SizedBox(height: 9),
        Expanded(
            child: SetupGrid(
                count: options.length, cell: (i) => _role(options[i]))),
      ]));

  Widget _role((String, String) option) {
    final (name, side) = option;
    final role = Role.values.firstWhere((r) => r.label == name);
    final expansionRole = role.isLancelot;
    final active = expansionRole || roles.contains(name);
    final required = expansionRole || name == '梅林' || name == '刺客';
    return SetupRole(
        tapKey: ValueKey('role$name'),
        role: role,
        side: side,
        active: active,
        locked: required,
        onTap: () => setState(() {
              active ? roles.remove(name) : roles.add(name);
            }));
  }

  Widget _footer(BuildContext context, Room configuration, int evilCount) =>
      SizedBox(
        height: 44,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
              width: 230,
              child: ExpansionsButton(
                  settings: expansions,
                  onTap: () async {
                    final value = await editExpansions(context, expansions,
                        players: playerCount);
                    if (mounted && value != null) {
                      setState(() => _setExpansions(value));
                    }
                  })),
          const SizedBox(width: 12),
          Expanded(
              child: configuration.roleIssue != null
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(configuration.roleIssue!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.orangeAccent)))
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: SetupTally(
                          good: playerCount - evilCount, evil: evilCount))),
          const SizedBox(width: 12),
          SizedBox(
              width: 168,
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
                                      cast: cast.take(playerCount - 1).toList(),
                                      archive: _archive)
                                  : GameScreen(room: configuration)))
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('開始遊戲'))),
        ]),
      );
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
