import 'package:flutter/material.dart';

/// LinkDrop's theme, transcribed from the "LinkDrop Design Spec" design
/// project (sections 01 Color, 02 Type, 03 Components, 05 Flutter).
///
/// Replaces the previous `ColorScheme.fromSeed(seedColor: Colors.deepPurple)`,
/// which was the entire theme and left every surface, weight and radius at
/// Material's defaults.
///
/// Two principles from the spec worth preserving when editing:
///
/// - **The accent is a line, a glow and an outline — never a flood.** Primary
///   actions are an accent *outline*, not a filled button. Reach for
///   [OutlinedButton], not [FilledButton].
/// - **"Declined" is not an error.** A user declining a transfer, a timeout,
///   or a sender hanging up are expected outcomes and render in neutral grey
///   ([TransferColors.declined]) — deliberately without chroma. Red is
///   reserved for genuine failures. This mirrors the engine's existing
///   split between `onError` and `onRejected` (Decision 014).
///
/// Dark is the default mode; light is a full peer, not a tint.

/// Semantic colors Material 3 has no `ColorScheme` slot for.
///
/// [declined] exists so a cancelled or refused transfer never has to borrow
/// [ColorScheme.error] and read as a failure.
@immutable
class TransferColors extends ThemeExtension<TransferColors> {
  const TransferColors({
    required this.success,
    required this.warning,
    required this.declined,
  });

  /// Complete, verified.
  final Color success;

  /// Will drop your network — e.g. hosting a hotspot disconnects Wi-Fi.
  final Color warning;

  /// Declined or cancelled. Grey on purpose: an expected outcome, not a fault.
  final Color declined;

  static const dark = TransferColors(
    success: Color(0xFF63B98C),
    warning: Color(0xFFD3A75F),
    declined: Color(0xFF9397AB),
  );

  static const light = TransferColors(
    success: Color(0xFF2F7D55),
    warning: Color(0xFF8A6318),
    declined: Color(0xFF75798C),
  );

  @override
  TransferColors copyWith({Color? success, Color? warning, Color? declined}) =>
      TransferColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        declined: declined ?? this.declined,
      );

  @override
  TransferColors lerp(ThemeExtension<TransferColors>? other, double t) {
    if (other is! TransferColors) return this;
    return TransferColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      declined: Color.lerp(declined, other.declined, t)!,
    );
  }
}

/// Convenience accessor so screens can read semantic colors without the
/// null-assertion dance at every call site.
extension LinkDropTheme on BuildContext {
  TransferColors get transferColors =>
      Theme.of(this).extension<TransferColors>() ?? TransferColors.dark;
}

const _darkScheme = ColorScheme.dark(
  surface: Color(0xFF161826),
  surfaceContainer: Color(0xFF232532),
  primary: Color(0xFF9184D9),
  primaryContainer: Color(0xFF2B2741),
  onSurface: Color(0xFFE9E9ED),
  onSurfaceVariant: Color(0xFF9397AB),
  error: Color(0xFFDD6F6F),
  outlineVariant: Color(0xFF3F424D),
);

const _lightScheme = ColorScheme.light(
  surface: Color(0xFFE4E7F5),
  surfaceContainer: Color(0xFFF3F5FE),
  primary: Color(0xFF5D5294),
  primaryContainer: Color(0xFFD2CEFD),
  onSurface: Color(0xFF292B31),
  onSurfaceVariant: Color(0xFF595D6C),
  error: Color(0xFFA63D3D),
  // NOTE: the spec lists outlineVariant only for dark (#3F424D). This is a
  // derived value for the light ramp — dividers and progress tracks. Replace
  // if the design supplies one.
  outlineVariant: Color(0xFFC7CBDE),
);

/// The spec's type scale (§02): "four roles, plus one number."
///
/// `displaySmall` is the transfer percentage — the thing people actually
/// watch, which is why it gets a display role of its own. The spec sizes it
/// 96 on desktop and 64 on phone; 96 is the base here and screens step it
/// down at the phone breakpoint.
const _textTheme = TextTheme(
  displaySmall:
      TextStyle(fontSize: 96, fontWeight: FontWeight.w500, letterSpacing: -2.8),
  headlineMedium: TextStyle(fontSize: 32, fontWeight: FontWeight.w500),
  labelLarge:
      TextStyle(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 1.0),
  bodyMedium: TextStyle(fontSize: 15, height: 1.55),
  bodySmall: TextStyle(fontSize: 12),
);

ThemeData buildTheme(ColorScheme scheme, TransferColors transfer) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    // The design specifies Inter. It is deliberately *not* declared here:
    // naming a family with no matching asset does not fall back to Inter, it
    // silently falls back to the platform default while the code claims
    // otherwise. Bundling it means adding the .ttf files under assets/fonts/
    // and a `fonts:` block to pubspec.yaml; until then the platform default
    // is what actually renders, and this stays honest about that.
    //
    // Inter is metrically close enough to Roboto that the layouts hold.
    textTheme: _textTheme,

    // Primary action = accent outline, never a fill (§03). 44dp minimum keeps
    // touch targets honest; desktop tightens this per-screen.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.primary),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    // Cancel / Decline: the neutral peer. A full button, never a text link —
    // but not destructive red either, since cancelling is not a failure.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: scheme.onSurfaceVariant,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    // 64dp device row (§03).
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 12,
      minTileHeight: 64,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.outlineVariant,
      linearMinHeight: 10,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    extensions: <ThemeExtension<dynamic>>[transfer],
  );
}

ThemeData get linkDropLightTheme => buildTheme(_lightScheme, TransferColors.light);
ThemeData get linkDropDarkTheme => buildTheme(_darkScheme, TransferColors.dark);
