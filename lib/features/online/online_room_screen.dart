import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../game/game_model.dart';
import '../game/game_screen.dart';
import '../game/game_session.dart';
import '../game/discussion_widgets.dart';
import '../game/expansion_model.dart';
import '../game/expansion_widgets.dart';
import '../lobby/role_presets.dart';
import '../lobby/room_model.dart';
import '../lobby/setup_widgets.dart';
import '../solo/bot_difficulty.dart';
import '../solo/persona/bot_persona.dart';
import 'online_session.dart';
import 'online_service.dart';
import 'voice/voice_controller.dart';
import 'voice/webrtc_voice_transport.dart';
import 'voice/voice_signaling.dart';
import 'voice/voice_controls.dart';
import '../../core/toast.dart';

/// A room before (and between) games: who is in, which roles are used.
/// When the host deals, every phone moves to the table automatically.
class OnlineRoomScreen extends StatefulWidget {
  const OnlineRoomScreen(
      {super.key,
      required this.code,
      required this.uid,
      this.session,
      this.voice});
  final String code;
  final String uid;

  /// For tests; normally the screen connects to Firebase itself.
  final OnlineGameSession? session;
  final VoiceController? voice;

  @override
  State<OnlineRoomScreen> createState() => _OnlineRoomScreenState();
}

class _OnlineRoomScreenState extends State<OnlineRoomScreen> {
  late final OnlineGameSession session =
      widget.session ?? OnlineGameSession.connect(widget.code, widget.uid);
  late final VoiceController voice = widget.voice ??
      VoiceController(
        createTransport: () => WebRtcVoiceTransport(
            uid: widget.uid,
            signaling: FirestoreVoiceSignaling(widget.code,
                now: () => session.nowMillis, clockReady: session.clockReady),
            // Direct voice is the default: no TURN credentials/function call.
            // A future relay trial must be enabled explicitly when building.
            iceServers: const bool.fromEnvironment('VOICE_ENABLE_TURN')
                ? () async {
                    try {
                      final config = await OnlineService.instance
                          .call('voiceIce', {'code': widget.code});
                      return [
                        for (final server in config['iceServers'] as List)
                          Map<String, dynamic>.from(server as Map)
                      ];
                    } on GameMoveException catch (error) {
                      throw VoiceException(error.message == 'NOT FOUND'
                          ? '語音更新尚未部署，仍可繼續遊戲'
                          : error.message);
                    }
                  }
                : null),
      );
  bool _tableOpen = false;

  /// Players in the lobby when the room was last seen (presets follow it).
  int? _lastCount;
  Future<void> _presets = Future.value();
  late final AppLifecycleListener _lifecycle;

  /// This screen's route, to come back to when a game is ended for everyone.
  ModalRoute<Object?>? _route;

  /// The last room notice shown (null until the room is first loaded).
  int? _noticeSeen;

  /// The deal the player walked away from; they are not pulled back into it.
  int _leftGen = -1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    session.addListener(_onRoomChanged);
    _updateVoiceFloor();
    // leaving the app (home screen, another app) always closes the microphone
    // and coming back tells the server at once that this player is here
    _lifecycle = AppLifecycleListener(
        onHide: voice.releaseMicrophone, onResume: session.reportPresence);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route ??= ModalRoute.of(context);
  }

  @override
  void dispose() {
    session.removeListener(_onRoomChanged);
    _lifecycle.dispose();
    if (widget.voice == null) voice.dispose();
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  void _onRoomChanged() {
    _updateVoiceFloor();
    final room = session.room;
    if (session.closed ||
        session.error != null ||
        (room != null && room.seatOf(widget.uid) < 0)) {
      voice.leave();
      if (_tableOpen && _route != null) {
        Navigator.of(context).popUntil((r) => r == _route);
      }
      return;
    }
    if (room == null || session.leaving) return;
    // someone left mid-game: the game is over, everyone comes back here
    if (!room.inGame && _tableOpen) {
      Navigator.of(context).popUntil((r) => r == _route);
    }
    _showNotice(room);
    _followPreset(room);
    if (room.inGame && !_tableOpen && room.gen != _leftGen) {
      _openTable();
    }
  }

  /// The host's phone applies the recommended roles whenever someone joins
  /// or leaves the lobby; the host can still change them afterwards.
  void _followPreset(OnlineRoom room) {
    final count = room.players.length, last = _lastCount;
    _lastCount = count;
    if (last == null || last == count || room.inGame || !session.isHost) return;
    final preset =
        rolePreset(count, lancelot: session.room!.expansions.lancelot > 0);
    if (preset == null) return;
    _presets = _presets.then((_) async {
      if (!mounted || session.room?.players.length != count) return;
      try {
        if (!setEquals(session.room!.optionalRoles, preset)) {
          await session.setRoles(preset);
        }
      } catch (_) {/* The host can still set the roles by hand. */}
    });
  }

  /// New expansion settings. Lancelot needs an evil place: switching it on
  /// first drops evil roles to make room; switching it off brings the
  /// preset back if the roles were only the preset made to fit.
  Future<void> _setExpansions(OnlineRoom room, ExpansionSettings value) async {
    final count = room.players.length;
    final was = room.expansions.lancelot > 0, now = value.lancelot > 0;
    final roles = room.optionalRoles;
    if (now && !was) {
      final fitted = fitForLancelot(count, roles);
      if (!setEquals(fitted, roles)) await session.setRoles(fitted);
      await session.setExpansions(value);
      return;
    }
    await session.setExpansions(value);
    if (was && !now) {
      final fitted = rolePreset(count, lancelot: true);
      if (fitted != null && setEquals(fitted, roles)) {
        await session.setRoles(rolePreset(count)!);
      }
    }
  }

  void _updateVoiceFloor() {
    final room = session.room;
    Set<String>? allowed;
    if (room?.inGame == true && session.discussionSettings.enabled) {
      final seat = switch (session.phase) {
        GamePhase.discussion => session.speaker,
        GamePhase.team when !session.discussionSettings.selectionFree =>
          session.leader,
        _ => null,
      };
      if (seat != null) {
        allowed = {session.playerIds[seat]};
      } else if ([
        GamePhase.identity,
        GamePhase.vote,
        GamePhase.voteResult,
        GamePhase.quest,
        GamePhase.questResult
      ].contains(session.phase)) {
        allowed = {};
      }
    }
    voice.setFloor(allowed, widget.uid);
  }

  void _showNotice(OnlineRoom room) {
    final step = room.noticeStep ?? -1;
    // notices from before this phone opened the room are not news
    if (_noticeSeen == null || room.notice == null) {
      _noticeSeen = step;
      return;
    }
    if (step <= _noticeSeen!) return;
    _noticeSeen = step;
    final text = room.notice!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showToast(context, text);
    });
  }

  Future<void> _openTable() async {
    _tableOpen = true;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => GameScreen.online(session: session, voice: voice)));
    if (!mounted) return;
    setState(() {
      _tableOpen = false;
      _leftGen = session.generation;
    });
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } on GameMoveException catch (e) {
      if (mounted) {
        showToast(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Back arrow: in the lobby this gives up the seat; during a game the
  /// seat is kept so the player can come back with the same code.
  Future<void> _leave() async {
    final room = session.room;
    if (room != null && room.status == 'lobby') return _leaveRoom();
    await voice.leave();
    if (mounted) Navigator.pop(context);
  }

  /// Gives up the seat for good and returns to the home screen.
  Future<void> _leaveRoom() async {
    final room = session.room;
    final midGame =
        room != null && room.inGame && session.phase != GamePhase.finished;
    if (midGame) {
      final sure = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('離開房間？'),
                content: const Text('對局正在進行。你離開後這局會中止，所有人回到房間大廳。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent),
                      child: const Text('離開房間')),
                ],
              ));
      if (sure != true) return;
    }
    setState(() => _busy = true);
    try {
      await voice.leave();
      await session.leave();
    } on GameMoveException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, e.message);
      }
      return;
    }
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          body: FantasyBackground(
            child: SafeArea(
              child: ListenableBuilder(
                listenable: session,
                builder: (context, _) => _body(),
              ),
            ),
          ),
        ),
      );

  Widget _message(String text) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text, style: const TextStyle(color: AvalonTheme.muted)),
          const SizedBox(height: 16),
          SizedBox(
            width: 180,
            child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回')),
          ),
        ]),
      );

  Widget _body() {
    if (session.closed) return _message('這個房間已經關閉了');
    if (session.error != null) return _message('無法讀取房間，可能已不在房間內');
    final room = session.room;
    if (room == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final host = session.isHost;
    final n = room.players.length;
    final issue = onlineSetupIssue(n, room.optionalRoles, room.expansions);
    final finished = room.inGame && session.phase == GamePhase.finished;
    final evil = Room.evilCount(n);
    return Center(
        child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(children: [
          _header(room),
          const SizedBox(height: 10),
          Expanded(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 6, child: _seats(room)),
              const SizedBox(width: 10),
              Expanded(flex: 5, child: _roles(room, host)),
            ]),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              OutlinedButton.icon(
                key: const ValueKey('leaveRoom'),
                style: OutlinedButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(
                        color: Colors.redAccent.withValues(alpha: .6))),
                onPressed: _busy ? null : _leaveRoom,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('離開房間'),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 230,
                child: ExpansionsButton(
                    settings: room.expansions,
                    onTap: host && !room.inGame && !_busy
                        ? () async {
                            final value =
                                await editExpansions(context, room.expansions);
                            if (mounted && value != null) {
                              await _run(() => _setExpansions(room, value));
                            }
                          }
                        : null),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: room.inGame
                      ? Text(finished ? '對局已結束' : '對局進行中',
                          style: const TextStyle(
                              fontSize: 12, color: AvalonTheme.muted))
                      : issue != null
                          ? Text(issue,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.orangeAccent))
                          : SetupTally(
                              good: n - evil,
                              evil: evil,
                              note: host ? '其餘名額自動補齊' : '等待房主開始'),
                ),
              ),
              const SizedBox(width: 12),
              if (room.inGame) ...[
                if (host && finished) ...[
                  OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: const EdgeInsets.symmetric(horizontal: 14)),
                      onPressed: _busy ? null : () => _run(session.backToLobby),
                      child: const Text('回到大廳調整')),
                  const SizedBox(width: 10),
                ],
                SizedBox(
                  width: 168,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(minimumSize: Size.zero),
                    onPressed: _openTable,
                    icon: const Icon(Icons.table_restaurant),
                    label: const Text('回到對局'),
                  ),
                ),
              ] else if (host)
                SizedBox(
                  width: 168,
                  child: ElevatedButton.icon(
                    key: const ValueKey('startOnline'),
                    style: ElevatedButton.styleFrom(minimumSize: Size.zero),
                    onPressed: issue == null && !_busy
                        ? () => _run(session.start)
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('開始遊戲'),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    ));
  }

  /// The room code, the house rules and voice, as in the setup screens.
  Widget _header(OnlineRoom room) {
    final host = session.isHost, open = host && !room.inGame && !_busy;
    return LayoutBuilder(
        builder: (context, box) => Row(children: [
              RoundIconButton(
                  icon: Icons.arrow_back,
                  tooltip: '離開房間',
                  onPressed: _busy ? null : _leave),
              const SizedBox(width: 12),
              // the room code, to tell the others
              Material(
                color: AvalonTheme.raised.withValues(alpha: .8),
                shape: StadiumBorder(
                    side: BorderSide(
                        color: AvalonTheme.gold.withValues(alpha: .35))),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: room.code));
                    showToast(context, '已複製房號');
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('房號',
                          style: TextStyle(
                              color: AvalonTheme.muted,
                              fontSize: 12,
                              letterSpacing: 1)),
                      const SizedBox(width: 8),
                      Text(room.code,
                          key: const ValueKey('roomCode'),
                          style: const TextStyle(
                              fontSize: 22,
                              letterSpacing: 4,
                              fontWeight: FontWeight.bold,
                              color: AvalonTheme.gold)),
                      const SizedBox(width: 6),
                      const Tooltip(
                          message: '複製房號',
                          child: Icon(Icons.copy,
                              size: 16, color: AvalonTheme.muted)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (room.hasBots || (host && !room.inGame)) ...[
                        _botLevel(room),
                        const SizedBox(width: 8),
                      ],
                      SettingChip(
                          icon: Icons.timer_outlined,
                          label: box.maxWidth < 760
                              ? ''
                              : (room.discussion.enabled ? '依序發言' : '自由討論'),
                          tooltip: room.discussion.enabled ? '依序發言' : '自由討論',
                          highlight: room.discussion.enabled,
                          onTap: open
                              ? () async {
                                  final settings = await editDiscussion(
                                      context, room.discussion);
                                  if (mounted && settings != null) {
                                    await _run(
                                        () => session.setDiscussion(settings));
                                  }
                                }
                              : null),
                    ]),
                  ),
                ),
              ),
              VoiceControls(
                  voice: voice,
                  names: {for (final p in room.players) p.uid: p.name}),
            ]));
  }

  Widget _seats(OnlineRoom room) => GoldPanel(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionLabel('玩家（${room.players.length}/10）'),
          const SizedBox(height: 9),
          Expanded(
              child: SetupGrid(
                  count: 10, rows: 5, cell: (seat) => _seat(room, seat))),
        ]),
      );

  static const _levels = {'novice': '新手', 'normal': '一般', 'expert': '高手'};

  /// How well the computers play; the host picks it in the lobby.
  Widget _botLevel(OnlineRoom room) {
    final mayChange = session.isHost && !room.inGame && !_busy;
    final chip = SettingChip(
        icon: Icons.psychology_outlined,
        label: '電腦：${_levels[room.botLevel] ?? '一般'}',
        trailing: mayChange
            ? const Icon(Icons.arrow_drop_down,
                size: 18, color: AvalonTheme.muted)
            : null,
        onTap: mayChange ? () {} : null);
    if (!mayChange) return chip;
    return PopupMenuButton<String>(
      key: const ValueKey('botLevel'),
      tooltip: '電腦難度',
      initialValue: room.botLevel,
      onSelected: (level) => _run(() => session.setBotLevel(level)),
      itemBuilder: (_) => [
        for (final level in BotDifficulty.values)
          PopupMenuItem(
            value: level.name,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(level.label),
                  Text(level.description,
                      style: const TextStyle(
                          fontSize: 11, color: AvalonTheme.muted)),
                ]),
          ),
      ],
      child: IgnorePointer(child: chip),
    );
  }

  /// The next of the cast who is not at this table yet.
  BotPersona? _nextBot(OnlineRoom room) {
    final seated = {for (final p in room.players) p.persona};
    for (final p in BotPersona.cast) {
      if (!seated.contains(p.id)) return p;
    }
    return null;
  }

  Widget _seat(OnlineRoom room, int seat) {
    if (seat >= room.players.length) {
      final next = _nextBot(room);
      // the first empty seat is where the host can seat a computer
      final offer = session.isHost &&
          !room.inGame &&
          seat == room.players.length &&
          next != null;
      return SetupEmptySeat(
          key: offer ? const ValueKey('addBot') : null,
          label: offer ? '加入電腦' : '空位',
          icon: offer ? Icons.smart_toy_outlined : null,
          onTap: offer && !_busy
              ? () =>
                  _run(() => session.setBot(next.id, next.name, seated: true))
              : null);
    }
    final p = room.players[seat];
    final me = p.uid == session.uid;
    final style = p.bot ? BotPersona.byId(p.persona)?.style.label : null;
    const mark = TextStyle(fontSize: 10.5, color: AvalonTheme.muted);
    return SetupSeat(
      number: seat + 1,
      name: p.name,
      highlight: me,
      dim: room.away.contains(seat),
      leading: room.away.contains(seat)
          ? const AwayMark()
          : p.bot
              ? null
              : VoiceSpeakingMark(voice: voice, uid: p.uid),
      trailing: [
        if (style != null)
          Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(style, style: mark)),
        if (p.bot)
          const Tooltip(
              message: '電腦玩家',
              child: Icon(Icons.smart_toy_outlined,
                  size: 15, color: AvalonTheme.muted)),
        if (p.bot && session.isHost && !room.inGame)
          SizedBox(
            width: 26,
            child: IconButton(
                key: ValueKey('removeBot${p.persona}'),
                tooltip: '移除這位電腦',
                padding: EdgeInsets.zero,
                iconSize: 16,
                color: AvalonTheme.muted,
                onPressed: _busy
                    ? null
                    : () => _run(() =>
                        session.setBot(p.persona!, p.name, seated: false)),
                icon: const Icon(Icons.close)),
          ),
        if (p.uid == room.hostUid)
          const Tooltip(
              message: '房主',
              child: Icon(Icons.workspace_premium,
                  size: 16, color: AvalonTheme.gold)),
        if (me)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text('你',
                style: TextStyle(fontSize: 11, color: AvalonTheme.gold)),
          ),
      ],
    );
  }

  Widget _roles(OnlineRoom room, bool host) {
    final editable = host && !room.inGame && !_busy;
    final options = [
      (Role.merlin, '正義・固定', true),
      (Role.assassin, '邪惡・固定', true),
      for (final r in optionalRoles) (r, r.isEvil ? '邪惡' : '正義', false),
      if (room.expansions.lancelot > 0) ...[
        (Role.lancelotGood, '正義・擴充固定', true),
        (Role.lancelotEvil, '邪惡・擴充固定', true),
      ],
    ];
    return GoldPanel(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionLabel(host ? '角色配置' : '角色配置（房主設定）'),
        const SizedBox(height: 9),
        Expanded(
          child: SetupGrid(
              count: options.length,
              cell: (i) {
                final (role, side, fixed) = options[i];
                final active = fixed || room.optionalRoles.contains(role);
                return SetupRole(
                    tapKey: ValueKey('onlineRole${role.name}'),
                    role: role,
                    side: side,
                    active: active,
                    locked: fixed,
                    onTap: editable
                        ? () {
                            final next = {...room.optionalRoles};
                            active ? next.remove(role) : next.add(role);
                            _run(() => session.setRoles(next));
                          }
                        : null);
              }),
        ),
      ]),
    );
  }
}
