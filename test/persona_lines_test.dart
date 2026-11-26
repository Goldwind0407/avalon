import 'package:flutter_test/flutter_test.dart';
import 'package:avalon_shadow_council/features/solo/dialogue/bot_catalog.dart';
import 'package:avalon_shadow_council/features/solo/persona/bot_persona.dart';
import 'package:avalon_shadow_council/features/solo/persona/persona_lines.dart';

void main() {
  final blanks = RegExp(r'\{\{([A-Za-z]+)\}\}');
  final short = RegExp(r'(?<!\{)\{([a-z]+)\}(?!\})');
  Set<String> used(Iterable<String> lines, RegExp re) =>
      {for (final l in lines) for (final m in re.allMatches(l)) m[1]!};

  test('every regular has their own way of speaking', () {
    for (final p in BotPersona.cast) {
      final lines = PersonaLines.of(p.id);
      expect(lines, isNotNull, reason: p.id);
      for (final list in [
        lines!.openers,
        lines.approve,
        lines.oppose,
        lines.firstApprove,
        lines.firstOppose,
        lines.firstAgain,
        lines.join,
        lines.agree,
        lines.lady,
        ...lines.rules.values,
      ]) {
        expect(list.length, greaterThanOrEqualTo(3), reason: p.id);
        expect(list.toSet().length, list.length, reason: '${p.id}: $list');
      }
    }
  });

  test('blanks are only those the shared lines fill', () {
    final rules = {for (final r in BotDialogueCatalog.bundled.rules) r.id: r};
    for (final p in BotPersona.cast) {
      final lines = PersonaLines.of(p.id)!;
      for (final e in lines.rules.entries) {
        final rule = rules[e.key];
        expect(rule, isNotNull, reason: '${p.id}: no rule ${e.key}');
        expect(used(e.value, blanks).difference(used(rule!.templates, blanks)),
            isEmpty,
            reason: '${p.id} ${e.key}');
        expect(used(e.value, short), isEmpty, reason: '${p.id} ${e.key}');
      }
      for (final list in [lines.join, lines.agree]) {
        expect(used(list, short), {'who'}, reason: p.id);
      }
      expect(used(lines.lady, short), {'who', 'then', 'side'}, reason: p.id);
      for (final list in [
        lines.openers,
        lines.approve,
        lines.oppose,
        lines.firstApprove,
        lines.firstOppose,
        lines.firstAgain
      ]) {
        expect(used(list, short), isEmpty, reason: p.id);
        expect(used(list, blanks), isEmpty, reason: p.id);
      }
    }
  });

  test('a Lady report says the seat, the time and the side', () {
    expect(
        PersonaLines.fill('我查了{who}，{then}是{side}。',
            {'who': '3號', 'then': '當時', 'side': '邪惡'}),
        '我查了3號，當時是邪惡。');
    expect(PersonaLines.fill('{{target}}，{who}', {'who': '3號'}),
        '{{target}}，3號');
  });
}
