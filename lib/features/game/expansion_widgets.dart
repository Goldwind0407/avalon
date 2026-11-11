import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'expansion_model.dart';

/// Lets the host choose the expansions before the game starts.
Future<ExpansionSettings?> editExpansions(
        BuildContext context, ExpansionSettings initial) =>
    showDialog<ExpansionSettings>(
        context: context, builder: (_) => _ExpansionDialog(initial));

class _ExpansionDialog extends StatefulWidget {
  const _ExpansionDialog(this.initial);
  final ExpansionSettings initial;
  @override
  State<_ExpansionDialog> createState() => _ExpansionDialogState();
}

class _ExpansionDialogState extends State<_ExpansionDialog> {
  late var value = widget.initial;

  static const _lancelotHelp = [
    '不加入蘭斯洛特。',
    '7 張轉換牌（5 張不變、2 張轉換）洗勻。第 3 次任務起，每次任務開始前翻 1 張；'
        '翻到「轉換陣營」時，兩位蘭斯洛特暗中交換陣營。',
    '7 張轉換牌抽 5 張，開局就正面放在 5 個任務上，所有人都知道哪一輪會換邊。'
        '正義方的蘭斯洛特只能出成功，邪惡方的蘭斯洛特必須出失敗。',
  ];

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 12, color: AvalonTheme.muted)),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        title: const Text('擴充規則'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                      key: const ValueKey('expansionLady'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('湖中女神'),
                      subtitle: const Text(
                          '第 2、3、4 次任務結束後，持有者查驗一名玩家的陣營，'
                          '再把湖中女神交給對方。持有過的人不能被查驗。建議 7 人以上。'),
                      value: value.lady,
                      onChanged: (v) =>
                          setState(() => value = value.copyWith(lady: v))),
                  const Divider(),
                  const Text('蘭斯洛特', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      key: const ValueKey('expansionLancelot'),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 0, label: Text('不使用')),
                        ButtonSegment(value: 1, label: Text('變體一・每輪翻牌')),
                        ButtonSegment(value: 2, label: Text('變體二・開局公開')),
                      ],
                      selected: {value.lancelot},
                      onSelectionChanged: (v) => setState(
                          () => value = value.copyWith(lancelot: v.single)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _note(_lancelotHelp[value.lancelot]),
                  if (value.lancelot > 0)
                    _note('正義與邪惡蘭斯洛特各占一個正義、邪惡名額。兩人互不認識；'
                        '邪惡蘭斯洛特會被其他壞人看見，但他看不到其他壞人。'),
                  const Divider(),
                  SwitchListTile(
                      key: const ValueKey('expansionExcalibur'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('王者之劍'),
                      subtitle: const Text('隊長提案時把劍交給隊長以外的一名隊員。'
                          '任務牌收走前，持劍者可以翻轉另一名隊員的任務牌，並看到那張牌原本是什麼。'),
                      value: value.excalibur,
                      onChanged: (v) =>
                          setState(() => value = value.copyWith(excalibur: v))),
                ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          TextButton(
              key: const ValueKey('expansionSave'),
              onPressed: () => Navigator.pop(context, value),
              child: const Text('儲存')),
        ],
      );
}

/// The row on the setup screens that shows (and opens) the expansions.
class ExpansionsButton extends StatelessWidget {
  const ExpansionsButton(
      {super.key, required this.settings, required this.onTap});
  final ExpansionSettings settings;

  /// Null when this device may not change them.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: settings.any
            ? AvalonTheme.violet.withValues(alpha: .3)
            : AvalonTheme.raised,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          key: const ValueKey('expansions'),
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              const Icon(Icons.extension_outlined,
                  size: 18, color: AvalonTheme.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('擴充規則',
                          style: TextStyle(fontSize: 13, color: Colors.white)),
                      Text(settings.any ? settings.summary : '未使用（點此加入湖中女神、蘭斯洛特、王者之劍）',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10,
                              color: settings.any
                                  ? AvalonTheme.gold
                                  : AvalonTheme.muted)),
                    ]),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right,
                    size: 18, color: AvalonTheme.muted),
            ]),
          ),
        ),
      );
}
