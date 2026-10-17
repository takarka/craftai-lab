import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'tokens.dart';

enum BuilderGlyph {
  robot,
  course,
  profile,
  settings,
  back,
  chevron,
  close,
  send,
  check,
  lock,
  doc,
  memory,
  cloud,
  globe,
  phone,
  calendar,
  code,
  reset,
  plus,
  tool,
  search,
  info,
  bolt,
  trash,
}

class BuilderIcon extends StatelessWidget {
  const BuilderIcon(
    this.glyph, {
    super.key,
    this.size = 24,
    this.color = BuilderColors.ink,
  });
  final BuilderGlyph glyph;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.asset(
      'assets/icons/${glyph.name}.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    ),
  );
}

enum CharacterMood {
  idle('Ожидание', BuilderGlyph.robot),
  listening('Слушает', BuilderGlyph.info),
  thinking('Думает', BuilderGlyph.memory),
  acting('Действует', BuilderGlyph.tool),
  awaitingApproval('Ждёт подтверждения', BuilderGlyph.check),
  uncertain('Не уверен', BuilderGlyph.info),
  newModule('Новый модуль', BuilderGlyph.plus);

  const CharacterMood(this.label, this.glyph);
  final String label;
  final BuilderGlyph glyph;
}

/// Original vector from Char.dc.html. Locked silhouettes follow UK4 (14%).
class BuilderCharacter extends StatelessWidget {
  const BuilderCharacter({
    super.key,
    this.level = 0,
    this.size = 120,
    this.mood = CharacterMood.idle,
    this.disabledModules = const {},
    this.compact = false,
  }) : assert(level >= 0 && level <= 5);
  final int level;
  final double size;
  final CharacterMood mood;
  final Set<int> disabledModules;
  final bool compact;
  static final Future<String> _source = rootBundle.loadString(
    'assets/character.svg',
  );

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'ИИ-ассистент, уровень $level из 5, ${mood.label}',
    image: true,
    child: SizedBox(
      width: size,
      height: size,
      child: FutureBuilder<String>(
        future: _source,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          var svg = snapshot.data!;
          for (var n = 1; n <= 5; n++) {
            svg = svg.replaceAll(
              '{{o$n}}',
              compact
                  ? '0'
                  : level < n
                  ? '0.14'
                  : disabledModules.contains(n)
                  ? '0.35'
                  : '1',
            );
          }
          if (compact) {
            svg = svg.replaceFirst(
              'viewBox="0 0 200 200"',
              'viewBox="38 54 124 112"',
            );
          }
          if (mood == CharacterMood.uncertain) {
            svg = svg.replaceFirst(
              'M88 120 Q100 128 112 120',
              'M88 124 Q100 118 112 124',
            );
          }
          return Stack(
            alignment: Alignment.center,
            children: [
              SvgPicture.string(
                svg,
                width: size,
                height: size,
                excludeFromSemantics: true,
              ),
              if (mood != CharacterMood.idle && !compact && size >= 100)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: mood == CharacterMood.uncertain
                          ? BuilderColors.warningTint
                          : BuilderColors.primaryTint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: BuilderIcon(
                      mood.glyph,
                      color: mood == CharacterMood.uncertain
                          ? BuilderColors.warning
                          : BuilderColors.primary,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
