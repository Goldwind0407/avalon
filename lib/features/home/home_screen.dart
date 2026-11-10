import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../lobby/room_model.dart';
import '../lobby/lobby_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});
  final LocalRoomRepository repository;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final nameController = TextEditingController(text: '無名騎士');
  final codeController = TextEditingController();
  @override
  void dispose() {
    nameController.dispose();
    codeController.dispose();
    super.dispose();
  }

  String? get validName {
    final n = nameController.text.trim();
    return n.isEmpty || n.length > 16 ? null : n;
  }

  void _open(Room room) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              LobbyScreen(room: room, repository: widget.repository)));
  void _create() {
    if (validName == null) {
      _notice('請輸入 1～16 字的暱稱');
      return;
    }
    _open(widget.repository.create(validName!));
  }

  void _join() {
    if (validName == null) {
      _notice('請輸入 1～16 字的暱稱');
      return;
    }
    final code = codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _notice('請輸入 6 位數房號');
      return;
    }
    final room = widget.repository.join(code, validName!);
    if (room == null) {
      _notice('找不到此本機房間；目前無法跨手機加入');
      return;
    }
    _open(room);
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
        body: FantasyBackground(
            child: SafeArea(
                child: Center(
                    child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(children: [
                const SizedBox(height: 15),
                const Icon(Icons.auto_awesome,
                    size: 29, color: AvalonTheme.gold),
                const SizedBox(height: 20),
                const Icon(Icons.shield_moon_outlined,
                    size: 94, color: AvalonTheme.gold),
                const SizedBox(height: 10),
                const Text('AVALON',
                    style: TextStyle(
                        fontSize: 42,
                        letterSpacing: 9,
                        color: AvalonTheme.gold,
                        fontWeight: FontWeight.w700)),
                const Text('暗 影 議 會',
                    style: TextStyle(
                        fontSize: 19, color: Colors.white, letterSpacing: 8)),
                const SizedBox(height: 9),
                const Text('真相藏於誓言之下',
                    style: TextStyle(color: AvalonTheme.muted, fontSize: 13)),
                const SizedBox(height: 36),
                GoldPanel(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const SectionLabel('YOUR IDENTITY · 冒險者身分'),
                      const SizedBox(height: 10),
                      TextField(
                          controller: nameController,
                          maxLength: 16,
                          decoration: const InputDecoration(
                              hintText: '輸入你的暱稱',
                              counterText: '',
                              prefixIcon: Icon(Icons.person_outline))),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                          onPressed: _create,
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('建立私人房間')),
                      const SizedBox(height: 16),
                      const Center(
                          child: Text('— 或返回本機房間 —',
                              style: TextStyle(
                                  color: AvalonTheme.muted, fontSize: 12))),
                      const SizedBox(height: 15),
                      TextField(
                          controller: codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                              hintText: '6 位數房間密令',
                              counterText: '',
                              prefixIcon: Icon(Icons.key_outlined))),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                          onPressed: _join,
                          icon: const Icon(Icons.login),
                          label: const Text('返回本機房間')),
                    ])),
                const SizedBox(height: 22),
                const Text('5–10 位玩家  •  私人房間  •  推理與背叛',
                    style: TextStyle(color: AvalonTheme.muted, fontSize: 12)),
                const SizedBox(height: 8),
                const Text('同機傳遞遊玩 · 尚未支援跨裝置連線',
                    style: TextStyle(color: AvalonTheme.gold, fontSize: 11)),
              ])),
        )))),
      );
}
