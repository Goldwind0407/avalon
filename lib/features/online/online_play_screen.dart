import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../game/game_session.dart';
import 'online_room_screen.dart';
import 'online_service.dart';

/// Entry to online play: pick a nickname, then create a room or join one
/// with its 6-digit code.
class OnlinePlayScreen extends StatefulWidget {
  const OnlinePlayScreen({super.key});
  @override
  State<OnlinePlayScreen> createState() => _OnlinePlayScreenState();
}

class _OnlinePlayScreenState extends State<OnlinePlayScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The Google account signed in (online play needs one), once known.
  String? _account;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkAccount();
  }

  Future<void> _checkAccount() async {
    final service = OnlineService.instance;
    final signedIn = await service.hasGoogle();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _account = signedIn ? service.googleAccount : null;
      if (signedIn && _name.text.isEmpty) _name.text = service.googleName ?? '';
    });
    if (signedIn) await _loadRooms(rejoin: true);
  }

  /// Rooms where this player still has a seat (after the app was closed,
  /// the connection lost, or on a new phone with the same account).
  List<MyRoom> _rooms = const [];

  /// Finds them; with [rejoin], goes straight back into a game that is
  /// going on, as the player would want after dropping out of it.
  Future<void> _loadRooms({bool rejoin = false}) async {
    final List<MyRoom> rooms;
    try {
      rooms = await OnlineService.instance.myRooms();
    } catch (_) {
      return; // not now: the code still works
    }
    if (!mounted) return;
    setState(() => _rooms = rooms);
    final going =
        rooms.where((r) => r.status == 'playing' && !r.finished).firstOrNull;
    if (rejoin && going != null && !_busy) {
      await _enter(create: false, code: going.code);
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uid = await OnlineService.instance.signInWithGoogle();
      if (uid != null) await _checkAccount();
    } on GameMoveException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await OnlineService.instance.signOutGoogle();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _account = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  String? get _nameIssue {
    final name = _name.text.trim();
    if (name.isEmpty) return '請輸入暱稱';
    if (name.length > 16) return '暱稱最多 16 個字';
    return null;
  }

  Future<void> _enter({required bool create, String? code}) async {
    if (_account == null) {
      return setState(() => _error = '多機遊玩需要先用 Google 登入');
    }
    final joining = code ?? _code.text.trim();
    final issue = _nameIssue ??
        (!create && !RegExp(r'^\d{6}$').hasMatch(joining)
            ? '房號是 6 位數字'
            : null);
    if (issue != null) return setState(() => _error = issue);
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = OnlineService.instance;
    try {
      final uid = await service.signIn();
      final name = _name.text.trim();
      final room = create
          ? (await service.call('createRoom', {'name': name}))['code'] as String
          : joining;
      if (!create) await service.call('joinRoom', {'code': room, 'name': name});
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => OnlineRoomScreen(code: room, uid: uid)));
      // back here: which rooms still have a seat for this player
      if (mounted) unawaited(_loadRooms());
    } on GameMoveException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: FantasyBackground(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        const ScreenTitle('多機遊玩',
                            subtitle: '每人用自己的手機加入同一個房間',
                            backTooltip: '返回首頁'),
                        const Spacer(),
                        if (_account != null) _accountChip(),
                      ]),
                      const SizedBox(height: 12),
                      if (_checking)
                        const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(child: CircularProgressIndicator()))
                      else if (_account == null)
                        _signInPanel()
                      else ...[
                        for (final room in _rooms) ...[
                          _backToRoom(room),
                          const SizedBox(height: 10),
                        ],
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 5, child: _namePanel()),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 6,
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      ModeCard(
                                        key: const ValueKey('createRoom'),
                                        icon: Icons.add_home_outlined,
                                        title: '建立房間',
                                        subtitle: '你當房主，選好角色後開始',
                                        primary: _rooms.isEmpty,
                                        onTap: _busy
                                            ? () {}
                                            : () => _enter(create: true),
                                      ),
                                      const SizedBox(height: 10),
                                      _joinPanel(),
                                    ]),
                              ),
                            ]),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 22,
                        child: _busy
                            ? const Center(
                                child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)))
                            : Text(_error ?? '',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.orangeAccent, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  /// The name the others see, beside the ways in.
  Widget _namePanel() => GoldPanel(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AvalonTheme.raised,
                  border: Border.all(
                      color: AvalonTheme.gold.withValues(alpha: .5))),
              child: const Icon(Icons.person_outline,
                  color: AvalonTheme.gold, size: 21),
            ),
            const SizedBox(width: 12),
            const Expanded(child: SectionLabel('你的暱稱')),
          ]),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('onlineName'),
            controller: _name,
            maxLength: 16,
            enabled: !_busy,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(
                hintText: '其他玩家會看到這個名字', counterText: ''),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 8),
          const Text('其他玩家只看得到暱稱，看不到你的 Google 帳號。',
              style: TextStyle(color: AvalonTheme.muted, fontSize: 11.5)),
        ]),
      );

  /// The six digits of a friend's room, and the way in.
  Widget _joinPanel() => GoldPanel(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.login, color: AvalonTheme.gold, size: 18),
            SizedBox(width: 8),
            Text('加入房間',
                style: TextStyle(
                    fontSize: 16,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            SizedBox(width: 8),
            Expanded(
              child: Text('輸入房主給你的 6 位數房號',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AvalonTheme.muted, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: CodeBoxes(
                key: const ValueKey('onlineCode'),
                controller: _code,
                enabled: !_busy,
                onChanged: () => setState(() => _error = null),
                onDone: () => _enter(create: false),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              key: const ValueKey('joinRoom'),
              style:
                  ElevatedButton.styleFrom(minimumSize: const Size(72, 48)),
              onPressed: _busy || _code.text.length != 6
                  ? null
                  : () => _enter(create: false),
              child: const Text('加入'),
            ),
          ]),
        ]),
      );

  /// A room this player still has a seat in.
  Widget _backToRoom(MyRoom room) => ModeCard(
        key: ValueKey('backToRoom${room.code}'),
        icon: Icons.replay,
        title: '回到房間 ${room.code}',
        subtitle: [
          room.status == 'playing'
              ? (room.finished ? '這局已結束' : '對局進行中')
              : '在大廳等待',
          if (room.host.isNotEmpty) '房主 ${room.host}',
          '${room.players} 人',
        ].join(' · '),
        primary: true,
        onTap: _busy ? () {} : () => _enter(create: false, code: room.code),
      );

  /// Online play needs a Google account: one per person, kept across
  /// phones and reinstalls, and not made by the thousand.
  Widget _signInPanel() => GoldPanel(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.verified_user_outlined,
              color: AvalonTheme.gold, size: 34),
          const SizedBox(height: 10),
          const Text('多機遊玩需要用 Google 登入',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AvalonTheme.gold)),
          const SizedBox(height: 6),
          const Text(
              '換手機或重裝 App 後，登入同一個帳號就能回到原本的座位。'
              '其他玩家只會看到你取的暱稱，看不到 Google 帳號。',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AvalonTheme.muted, fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 16),
          SizedBox(
            width: 260,
            child: ElevatedButton.icon(
              key: const ValueKey('googleSignIn'),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              onPressed: _busy ? null : _signIn,
              icon: const Icon(Icons.login),
              label: const Text('用 Google 登入'),
            ),
          ),
          const SizedBox(height: 8),
          const Text('一機遊玩和跟電腦遊玩不需要登入。',
              style: TextStyle(color: AvalonTheme.muted, fontSize: 11.5)),
        ]),
      );

  /// Which Google account is signed in, with a way out.
  Widget _accountChip() => PopupMenuButton<String>(
        key: const ValueKey('googleAccount'),
        tooltip: 'Google 帳號',
        onSelected: (_) => _signOut(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'out', child: Text('登出 Google 帳號')),
        ],
        child: IgnorePointer(
          child: SettingChip(
              icon: Icons.account_circle_outlined,
              label: _account ?? '',
              onTap: () {}),
        ),
      );
}

/// Six boxes for a room code, filled as it is typed (one hidden text field
/// takes the typing, so pasting and the number pad work as usual).
class CodeBoxes extends StatelessWidget {
  const CodeBoxes(
      {super.key,
      required this.controller,
      required this.onChanged,
      required this.onDone,
      this.enabled = true});
  final TextEditingController controller;
  final VoidCallback onChanged, onDone;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: Stack(children: [
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final text = controller.text;
              return Row(children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) SizedBox(width: i == 3 ? 10 : 5),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AvalonTheme.raised,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                            color: i == text.length
                                ? AvalonTheme.gold
                                : AvalonTheme.gold.withValues(
                                    alpha: i < text.length ? .55 : .2),
                            width: i == text.length ? 1.5 : 1),
                      ),
                      child: Text(i < text.length ? text[i] : '',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AvalonTheme.gold)),
                    ),
                  ),
                ],
              ]);
            },
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: controller,
                enabled: enabled,
                keyboardType: TextInputType.number,
                maxLength: 6,
                showCursor: false,
                enableInteractiveSelection: false,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    counterText: '', border: InputBorder.none),
                onChanged: (_) => onChanged(),
                onSubmitted: (_) => onDone(),
              ),
            ),
          ),
        ]),
      );
}
