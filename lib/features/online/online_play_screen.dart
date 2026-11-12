import 'package:flutter/material.dart';
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

  Future<void> _enter({required bool create}) async {
    final issue = _nameIssue ??
        (!create && !RegExp(r'^\d{6}$').hasMatch(_code.text.trim())
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
      final code = create
          ? (await service.call('createRoom', {'name': name}))['code'] as String
          : _code.text.trim();
      if (!create) await service.call('joinRoom', {'code': code, 'name': name});
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => OnlineRoomScreen(code: code, uid: uid)));
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
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        IconButton(
                            tooltip: '返回首頁',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back),
                            color: AvalonTheme.gold),
                        const SizedBox(width: 4),
                        const Text('多機遊玩',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AvalonTheme.gold)),
                        const Spacer(),
                        const Text('每人用自己的手機加入同一個房間',
                            style: TextStyle(
                                color: AvalonTheme.muted, fontSize: 12)),
                      ]),
                      const SizedBox(height: 10),
                      GoldPanel(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionLabel('你的暱稱'),
                            const SizedBox(height: 8),
                            TextField(
                              key: const ValueKey('onlineName'),
                              controller: _name,
                              maxLength: 16,
                              enabled: !_busy,
                              decoration: const InputDecoration(
                                  hintText: '其他玩家會看到這個名字', counterText: ''),
                              onChanged: (_) => setState(() => _error = null),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      IntrinsicHeight(
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: GoldPanel(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const SectionLabel('開新房間'),
                                      const SizedBox(height: 6),
                                      const Text('你會成為房主，負責設定角色和開始遊戲。',
                                          style: TextStyle(
                                              color: AvalonTheme.muted,
                                              fontSize: 12)),
                                      const Spacer(),
                                      const SizedBox(height: 12),
                                      ElevatedButton.icon(
                                        key: const ValueKey('createRoom'),
                                        onPressed: _busy
                                            ? null
                                            : () => _enter(create: true),
                                        icon: const Icon(Icons.add),
                                        label: const Text('建立房間'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GoldPanel(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const SectionLabel('加入房間'),
                                      const SizedBox(height: 8),
                                      TextField(
                                        key: const ValueKey('onlineCode'),
                                        controller: _code,
                                        enabled: !_busy,
                                        keyboardType: TextInputType.number,
                                        maxLength: 6,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly
                                        ],
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontSize: 22,
                                            letterSpacing: 8,
                                            color: AvalonTheme.gold),
                                        decoration: const InputDecoration(
                                            hintText: '6 位數房號',
                                            counterText: ''),
                                        onChanged: (_) =>
                                            setState(() => _error = null),
                                      ),
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                        key: const ValueKey('joinRoom'),
                                        onPressed: _busy
                                            ? null
                                            : () => _enter(create: false),
                                        icon: const Icon(Icons.login),
                                        label: const Text('加入'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ]),
                      ),
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
}
