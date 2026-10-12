// Thèmes clair et sombre construits uniquement à partir des jetons (UI-06, DES-02).
import 'package:flutter/material.dart';

import 'jetons.dart';

ThemeData construireTheme(Couleurs c, Brightness luminosite) {
  final schema = ColorScheme(
    brightness: luminosite,
    primary: c.violet,
    onPrimary: c.surViolet,
    secondary: c.rose,
    onSecondary: c.surAccent,
    tertiary: c.turquoise,
    onTertiary: c.vertTexte,
    error: c.erreurTexte,
    onError: c.surViolet,
    surface: c.surface,
    onSurface: c.encre,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: schema,
    brightness: luminosite,
    scaffoldBackgroundColor: c.fond,
    fontFamily: Polices.corps,
    extensions: [c],
    splashFactory: NoSplash.splashFactory,
    focusColor: c.violet.withValues(alpha: Opacites.appui),
    hoverColor: c.encre.withValues(alpha: Opacites.survol),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _TransitionDouce(),
        TargetPlatform.windows: _TransitionDouce(),
        TargetPlatform.linux: _TransitionDouce(),
        TargetPlatform.macOS: _TransitionDouce(),
        TargetPlatform.iOS: _TransitionDouce(),
        TargetPlatform.fuchsia: _TransitionDouce(),
      },
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.encre, displayColor: c.encre),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.encre,
      contentTextStyle: Textes.etiquette.copyWith(color: c.fond),
      actionTextColor: c.jaune,
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.violet),
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.violet),
  );
}

/// Fondu et glissement de 16 px sur 200 ms ; aucun mouvement si les animations sont réduites
/// (DES-18, UI-08).
class _TransitionDouce extends PageTransitionsBuilder {
  const _TransitionDouce();

  static const _glissement = 16.0;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (context.animationsReduites) return child;
    final courbe = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    return FadeTransition(
      opacity: courbe,
      child: AnimatedBuilder(
        animation: courbe,
        builder: (context, enfant) =>
            Transform.translate(offset: Offset(0, (1 - courbe.value) * _glissement), child: enfant),
        child: child,
      ),
    );
  }
}
