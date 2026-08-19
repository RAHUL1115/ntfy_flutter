import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

/// Design tokens for the "functional minimalist" mobile design in
/// `docs/new_design`: flat surfaces, hairline outlines, square corners and a
/// single deep-teal accent. Elevation is expressed as an offset hard shadow
/// rather than a blur, so [ColorScheme.shadow] is used directly.
const _forest = Color(0xff004f45);
const _forestShadow = Color(0xff00201b);
const _shell = Color(0xfff8fafa);
const _paper = Color(0xffffffff);
const _ink = Color(0xff191c1d);
const _slate = Color(0xff3e4946);
const _outline = Color(0xffbec9c5);
const _hairline = Color(0xffe1e3e3);

const _mintDark = Color(0xff84d6c2);
const _mintOnDark = Color(0xff00382e);
const _shellDark = Color(0xff0f1413);
const _paperDark = Color(0xff171f1e);
const _inkDark = Color(0xffe0e4e3);
const _slateDark = Color(0xffbfc9c5);
const _outlineDark = Color(0xff3d4a47);
const _hairlineDark = Color(0xff28322f);

/// Offset shadow used under raised surfaces (FAB, primary actions).
const hardShadowOffset = Offset(0, 2);

/// The primary actions use square corners throughout the app.
const fabRadius = 0.0;

const designHeaderExpandedHeight = 268.0;
const designHeaderCollapsedHeight = 72.0;
const designMotionDuration = Duration(milliseconds: 250);

final _designHeadersExpanded = ValueNotifier(true);

const _lightScheme = ColorScheme.light(
  primary: _forest,
  onPrimary: _paper,
  secondary: _forest,
  onSecondary: _paper,
  surface: _shell,
  onSurface: _ink,
  onSurfaceVariant: _slate,
  surfaceContainerLowest: _paper,
  surfaceContainerLow: _paper,
  surfaceContainer: _shell,
  surfaceContainerHigh: _shell,
  surfaceContainerHighest: _hairline,
  outline: _outline,
  outlineVariant: _hairline,
  shadow: _forestShadow,
);

const _darkScheme = ColorScheme.dark(
  primary: _mintDark,
  onPrimary: _mintOnDark,
  secondary: _mintDark,
  onSecondary: _mintOnDark,
  surface: _shellDark,
  onSurface: _inkDark,
  onSurfaceVariant: _slateDark,
  surfaceContainerLowest: _paperDark,
  surfaceContainerLow: _paperDark,
  surfaceContainer: _shellDark,
  surfaceContainerHigh: _shellDark,
  surfaceContainerHighest: _hairlineDark,
  outline: _outlineDark,
  outlineVariant: _hairlineDark,
  shadow: Color(0xff000000),
);

/// Type scale of the design. The mockups use Hanken Grotesk for headings and
/// Inter for body text; neither is bundled with the app, so the platform sans
/// carries the design's weights, sizes and tracking instead.
const _textTheme = TextTheme(
  headlineSmall: TextStyle(
    fontFamily: 'HankenGrotesk',
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  ),
  titleLarge: TextStyle(
    fontFamily: 'HankenGrotesk',
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  ),
  titleMedium: TextStyle(
    fontFamily: 'HankenGrotesk',
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  ),
  titleSmall: TextStyle(
    fontFamily: 'HankenGrotesk',
    fontSize: 15,
    fontWeight: FontWeight.w600,
  ),
  bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 15, height: 1.4),
  bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.4),
  bodySmall: TextStyle(fontFamily: 'Inter', fontSize: 12, height: 1.4),
  labelLarge: TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
  ),
  labelMedium: TextStyle(
    fontFamily: 'Inter',
    fontSize: 13,
    fontWeight: FontWeight.w600,
  ),
  labelSmall: TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  ),
);

/// Monospaced label used for section headings and technical values.
const monoLabel = TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 11,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.9,
);

const _square = RoundedRectangleBorder();

/// The design applied to [brightness]. [fontFamily] overrides the platform
/// sans across every text style, including the component themes, so golden
/// tests can render with a bundled font.
ThemeData designTheme({
  required Brightness brightness,
  String? fontFamily,
  ColorScheme? colorScheme,
}) => _theme(
  colorScheme ?? (brightness == Brightness.light ? _lightScheme : _darkScheme),
  fontFamily == null ? _textTheme : _textTheme.apply(fontFamily: fontFamily),
);

ThemeData _theme(ColorScheme scheme, TextTheme text) {
  final square = RoundedRectangleBorder(
    side: BorderSide(color: scheme.outline),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text,
    fontFamily: 'Inter',
    iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 72,
      titleTextStyle: text.titleLarge!.copyWith(color: scheme.onSurface),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
      actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: square,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      dense: true,
      minVerticalPadding: 8,
      titleTextStyle: text.bodyMedium!.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      subtitleTextStyle: text.bodySmall!.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      iconColor: scheme.onSurfaceVariant,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
      ),
      labelStyle: monoLabel.copyWith(color: scheme.onSurfaceVariant),
      floatingLabelStyle: monoLabel.copyWith(color: scheme.primary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(fabRadius)),
      ),
      extendedTextStyle: text.titleSmall,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: Border(
        top: BorderSide(color: scheme.outline),
        left: BorderSide(color: scheme.outline),
        right: BorderSide(color: scheme.outline),
        bottom: BorderSide(color: scheme.shadow, width: 2),
      ),
      menuPadding: EdgeInsets.zero,
      textStyle: text.bodyLarge!.copyWith(
        color: scheme.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      labelTextStyle: WidgetStatePropertyAll(
        text.bodyLarge!.copyWith(
          color: scheme.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLowest),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(square),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(side: BorderSide(color: scheme.onSurface)),
      titleTextStyle: text.titleMedium!.copyWith(color: scheme.onSurface),
      contentTextStyle: text.bodyLarge!.copyWith(color: scheme.onSurface),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: _square,
      dragHandleColor: scheme.outline,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      contentTextStyle: text.bodyMedium!.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      actionTextColor: scheme.primary,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: square,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.surfaceContainerLowest,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.outlineVariant,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.outline,
      ),
      trackOutlineWidth: const WidgetStatePropertyAll(1),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.onSurfaceVariant,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(),
      side: BorderSide(color: scheme.onSurfaceVariant, width: 2),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.outlineVariant,
      selectedColor: scheme.primary,
      surfaceTintColor: Colors.transparent,
      checkmarkColor: scheme.onPrimary,
      showCheckmark: false,
      elevation: 0,
      pressElevation: 0,
      side: BorderSide.none,
      shape: _square,
      labelStyle: text.labelMedium!.copyWith(
        fontWeight: FontWeight.w400,
        color: scheme.onSurface,
      ),
      secondaryLabelStyle: text.labelMedium!.copyWith(
        fontWeight: FontWeight.w400,
        color: scheme.onPrimary,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: _square,
        elevation: 0,
        textStyle: text.titleSmall,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(shape: _square, elevation: 0),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: _square,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: _square,
        foregroundColor: scheme.primary,
        textStyle: text.labelLarge,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
  );
}

final lightTheme = designTheme(brightness: Brightness.light);

final darkTheme = designTheme(brightness: Brightness.dark);

class DesignDeleteBackground extends StatelessWidget {
  const DesignDeleteBackground({this.margin = EdgeInsets.zero, super.key});

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    color: _ink,
    child: Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.delete_outline, color: _paper),
      ),
    ),
  );
}

/// Large centered header that settles into the compact toolbar shown in the
/// updated mobile design.
class DesignHeader extends StatelessWidget {
  const DesignHeader({
    required this.progress,
    required this.duration,
    required this.title,
    required this.actions,
    this.leading,
    this.expandedTitleSize = 28,
    this.collapsedTitleSize = 22,
    this.border = true,
    super.key,
  });

  final double progress;
  final Duration duration;
  final Widget title;
  final Widget? leading;
  final List<Widget> actions;
  final double expandedTitleSize;
  final double collapsedTitleSize;
  final bool border;

  double _lerp(double collapsed, double expanded) =>
      collapsed + ((expanded - collapsed) * progress);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final animationDuration = reduceMotion ? Duration.zero : duration;
    return AnimatedContainer(
      duration: animationDuration,
      curve: Curves.easeOutCubic,
      height: _lerp(designHeaderCollapsedHeight, designHeaderExpandedHeight),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: border
            ? Border(bottom: BorderSide(color: theme.colorScheme.outline))
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (leading != null)
            Positioned(
              left: 12,
              top: 12,
              width: 48,
              height: 48,
              child: leading!,
            ),
          AnimatedPositioned(
            duration: animationDuration,
            curve: Curves.easeOutCubic,
            left: _lerp(leading == null ? 16 : 68, 16),
            right: _lerp(16 + (actions.length * 48), 16),
            top: _lerp(16, 110),
            height: 40,
            child: AnimatedDefaultTextStyle(
              duration: animationDuration,
              curve: Curves.easeOutCubic,
              style: theme.textTheme.headlineSmall!.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: _lerp(collapsedTitleSize, expandedTitleSize),
              ),
              textAlign: progress >= 0.5 ? TextAlign.center : TextAlign.left,
              child: AnimatedAlign(
                duration: animationDuration,
                curve: Curves.easeOutCubic,
                alignment: Alignment.lerp(
                  Alignment.centerLeft,
                  Alignment.center,
                  progress,
                )!,
                child: title,
              ),
            ),
          ),
          AnimatedPositioned(
            duration: animationDuration,
            curve: Curves.easeOutCubic,
            right: 16,
            top: _lerp(12, 208),
            height: 48,
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
        ],
      ),
    );
  }
}

class CollapsibleDesignBody extends StatefulWidget {
  const CollapsibleDesignBody({
    required this.title,
    required this.child,
    this.leading,
    this.actions = const [],
    this.automaticallyImplyLeading = true,
    this.forceCollapsed = false,
    this.expandedTitleSize = 28,
    this.collapsedTitleSize = 22,
    super.key,
  });

  final Widget title;
  final Widget child;
  final Widget? leading;
  final List<Widget> actions;
  final bool automaticallyImplyLeading;
  final bool forceCollapsed;
  final double expandedTitleSize;
  final double collapsedTitleSize;

  @override
  State<CollapsibleDesignBody> createState() => _CollapsibleDesignBodyState();
}

class _CollapsibleDesignBodyState extends State<CollapsibleDesignBody> {
  late double _headerExtent;
  var _dragging = false;

  @override
  void initState() {
    super.initState();
    _headerExtent = _designHeadersExpanded.value
        ? designHeaderExpandedHeight
        : designHeaderCollapsedHeight;
    _designHeadersExpanded.addListener(_syncSettledState);
  }

  @override
  void dispose() {
    _designHeadersExpanded.removeListener(_syncSettledState);
    super.dispose();
  }

  void _syncSettledState() {
    if (_dragging) return;
    _setExtent(
      _designHeadersExpanded.value
          ? designHeaderExpandedHeight
          : designHeaderCollapsedHeight,
    );
  }

  double get _progress =>
      (_headerExtent - designHeaderCollapsedHeight) /
      (designHeaderExpandedHeight - designHeaderCollapsedHeight);

  void _setExtent(double extent) {
    final next = extent.clamp(
      designHeaderCollapsedHeight,
      designHeaderExpandedHeight,
    );
    if (next != _headerExtent) setState(() => _headerExtent = next);
  }

  void _snap() {
    final expanded = _progress >= 0.5;
    final next = expanded
        ? designHeaderExpandedHeight
        : designHeaderCollapsedHeight;
    if (_dragging || next != _headerExtent) {
      setState(() {
        _dragging = false;
        _headerExtent = next;
      });
    }
    if (_designHeadersExpanded.value != expanded) {
      _designHeadersExpanded.value = expanded;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    switch (notification) {
      case ScrollStartNotification(dragDetails: != null):
        if (!_dragging) setState(() => _dragging = true);
      case ScrollUpdateNotification(:final dragDetails)
          when dragDetails != null:
        final delta = dragDetails.delta.dy;
        final collapse = delta < 0;
        final nearTop =
            notification.metrics.pixels <=
            designHeaderExpandedHeight - designHeaderCollapsedHeight;
        if (collapse || nearTop) _setExtent(_headerExtent + delta);
      case OverscrollNotification(:final overscroll, dragDetails: != null):
        _setExtent(_headerExtent - overscroll);
      case ScrollEndNotification():
        _snap();
      case UserScrollNotification(direction: ScrollDirection.idle):
        _snap();
      default:
        break;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final leading =
        widget.leading ??
        (widget.automaticallyImplyLeading && Navigator.canPop(context)
            ? IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back),
              )
            : null);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          DesignHeader(
            progress: widget.forceCollapsed ? 0 : _progress,
            duration: _dragging ? Duration.zero : designMotionDuration,
            title: widget.title,
            leading: leading,
            actions: widget.actions,
            expandedTitleSize: widget.expandedTitleSize,
            collapsedTitleSize: widget.collapsedTitleSize,
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: ScrollConfiguration(
                behavior: const _DesignScrollBehavior(),
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesignScrollBehavior extends MaterialScrollBehavior {
  const _DesignScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      AlwaysScrollableScrollPhysics(parent: super.getScrollPhysics(context));
}
