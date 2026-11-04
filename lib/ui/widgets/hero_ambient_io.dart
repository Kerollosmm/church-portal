import 'package:material_ui/material_ui.dart';

/// Android / iOS / tests: the ambient layers are painted by Flutter.
const bool heroAmbientInDom = false;

/// Not used off the web (see `hero_ambient_web.dart`).
class HeroAmbientLayer extends StatelessWidget {
  final bool haze;
  final double rays;
  final bool play;
  final String cssFilter;
  final String clouds;
  const HeroAmbientLayer({
    super.key,
    required this.haze,
    required this.rays,
    required this.play,
    required this.clouds,
    this.cssFilter = 'none',
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
