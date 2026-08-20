import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'l10n.dart';

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

/// Continued downward pull, in logical pixels, that is swallowed before the
/// header starts expanding. Ordinary upward scrolls that reach the top do not
/// expand the header; only a deliberate continued pull does.
const designHeaderExpandFriction = 24.0;

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

class DesignSwipeToDelete extends StatefulWidget {
  const DesignSwipeToDelete({
    required this.dismissKey,
    required this.onDelete,
    required this.child,
    this.backgroundMargin = EdgeInsets.zero,
  }) : super(key: dismissKey);

  final Key dismissKey;
  final Future<void> Function() onDelete;
  final Widget child;
  final EdgeInsetsGeometry backgroundMargin;

  @override
  State<DesignSwipeToDelete> createState() => _DesignSwipeToDeleteState();
}

class _DesignSwipeToDeleteState extends State<DesignSwipeToDelete>
    with SingleTickerProviderStateMixin {
  static const _actionExtent = 72.0;
  static const _settleThreshold = 0.5;
  late final AnimationController _position;
  var _revealed = false;
  var _deleting = false;

  @override
  void initState() {
    super.initState();
    _position = AnimationController.unbounded(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  void _updateDrag(DragUpdateDetails details) {
    if (_deleting) return;
    _position.value = (_position.value - details.delta.dx / _actionExtent)
        .clamp(0.0, 2.0)
        .toDouble();
  }

  void _endDrag(DragEndDetails details) {
    if (_deleting) return;
    if (_revealed && _position.value >= 1 + _settleThreshold) {
      _delete();
      return;
    }
    final reveal = _position.value >= _settleThreshold;
    if (_revealed != reveal) setState(() => _revealed = reveal);
    _position.animateTo(reveal ? 1 : 0, curve: Curves.easeOutCubic);
  }

  void _cancelDrag() {
    _position.animateTo(_revealed ? 1 : 0, curve: Curves.easeOutCubic);
  }

  void _reveal() {
    if (_revealed || _deleting) return;
    setState(() => _revealed = true);
    _position.animateTo(1, curve: Curves.easeOutCubic);
  }

  Future<void> _delete() async {
    if (_deleting) return;
    _deleting = true;
    _position.animateTo(2, curve: Curves.easeInCubic);
    await widget.onDelete();
    if (!mounted) return;
    setState(() {
      _deleting = false;
      _revealed = false;
    });
    _position.animateTo(0, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _position,
              builder: (_, child) => Opacity(
                opacity: _position.value.clamp(0.0, 1.0).toDouble(),
                child: child,
              ),
              child: Padding(
                padding: widget.backgroundMargin,
                child: ColoredBox(
                  color: scheme.surface,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox.square(
                      dimension: _actionExtent,
                      child: Tooltip(
                        message: tr(context, 'Delete'),
                        child: Material(
                          key: const Key('swipe-delete-action'),
                          color: scheme.primary,
                          child: InkWell(
                            onTap: _revealed && !_deleting ? _delete : null,
                            child: Icon(
                              Icons.delete_outline,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Semantics(
            customSemanticsActions: {
              CustomSemanticsAction(
                label: tr(
                  context,
                  _revealed ? 'Delete' : 'Reveal delete action',
                ),
              ): _revealed ? _delete : _reveal,
            },
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: _updateDrag,
              onHorizontalDragEnd: _endDrag,
              onHorizontalDragCancel: _cancelDrag,
              child: AnimatedBuilder(
                animation: _position,
                child: widget.child,
                builder: (_, child) => Transform.translate(
                  offset: Offset(-_position.value * _actionExtent, 0),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    this.onCollapsedTitleTap,
    this.expandedTitleSize = 28,
    this.collapsedTitleSize = 22,
    this.border = true,
    super.key,
  });

  final double progress;
  final Duration duration;
  final Widget title;
  final Widget? leading;
  final VoidCallback? onCollapsedTitleTap;
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
            AnimatedPositioned(
              duration: animationDuration,
              curve: Curves.easeOutCubic,
              left: 12,
              top: _lerp(12, 208),
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
                child: onCollapsedTitleTap != null && progress == 0
                    ? InkWell(onTap: onCollapsedTitleTap, child: title)
                    : title,
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
    this.onCollapsedTitleTap,
    this.scrollController,
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
  final VoidCallback? onCollapsedTitleTap;
  final ScrollController? scrollController;
  final double expandedTitleSize;
  final double collapsedTitleSize;

  @override
  State<CollapsibleDesignBody> createState() => _CollapsibleDesignBodyState();
}

class _CollapsibleDesignBodyState extends State<CollapsibleDesignBody> {
  late final ScrollController _fallbackScrollController;
  late double _headerExtent;
  var _dragging = false;
  var _headerDragging = false;
  var _overscrollCredit = 0.0;
  var _lastExpandExcess = 0.0;

  ScrollController get _scrollController =>
      widget.scrollController ?? _fallbackScrollController;

  @override
  void initState() {
    super.initState();
    _fallbackScrollController = ScrollController();
    _headerExtent = _designHeadersExpanded.value
        ? designHeaderExpandedHeight
        : designHeaderCollapsedHeight;
    _designHeadersExpanded.addListener(_syncSettledState);
  }

  @override
  void dispose() {
    _designHeadersExpanded.removeListener(_syncSettledState);
    _fallbackScrollController.dispose();
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

  double get _headerRoom =>
      widget.forceCollapsed ? 0 : _headerExtent - designHeaderCollapsedHeight;

  void _setExtent(double extent) {
    final next = extent.clamp(
      designHeaderCollapsedHeight,
      designHeaderExpandedHeight,
    );
    if (next != _headerExtent) setState(() => _headerExtent = next);
  }

  void _settle(bool expanded, {bool keepDragging = false}) {
    final next = expanded
        ? designHeaderExpandedHeight
        : designHeaderCollapsedHeight;
    // Settling ends any expansion pull; reset its accumulators so a later
    // pull starts from a consistent baseline instead of a stale credit.
    _overscrollCredit = 0;
    _lastExpandExcess = 0;
    if ((_dragging && !keepDragging) || next != _headerExtent) {
      setState(() {
        if (!keepDragging) _dragging = false;
        _headerExtent = next;
      });
    }
    if (_designHeadersExpanded.value != expanded) {
      _designHeadersExpanded.value = expanded;
    }
  }

  void _snap() => _settle(_progress >= 0.5);

  void _onHeaderDragStart(DragStartDetails details) {
    setState(() {
      _dragging = true;
      _headerDragging = true;
    });
  }

  void _onHeaderDragUpdate(DragUpdateDetails details) {
    var delta = details.primaryDelta ?? 0;
    final controller = _scrollController;
    if (delta < 0) {
      final collapse = (-delta).clamp(
        0,
        _headerExtent - designHeaderCollapsedHeight,
      );
      _setExtent(_headerExtent - collapse);
      delta += collapse;
      if (delta < 0 && controller.hasClients) {
        controller.jumpTo(
          (controller.offset - delta).clamp(
            controller.position.minScrollExtent,
            controller.position.maxScrollExtent,
          ),
        );
      }
      return;
    }
    if (delta > 0 && controller.hasClients && controller.offset > 0) {
      final scroll = delta.clamp(0, controller.offset);
      controller.jumpTo(controller.offset - scroll);
      delta -= scroll;
    }
    if (delta > 0) _setExtent(_headerExtent + delta);
  }

  void _onHeaderDragEnd(DragEndDetails details) {
    _headerDragging = false;
    _snap();
    final velocity = -(details.primaryVelocity ?? 0);
    if (_headerExtent == designHeaderCollapsedHeight &&
        velocity > 0 &&
        _scrollController.hasClients &&
        _scrollController.position is ScrollPositionWithSingleContext) {
      (_scrollController.position as ScrollPositionWithSingleContext)
          .goBallistic(velocity);
    }
  }

  void _onHeaderDragCancel() {
    _headerDragging = false;
    _snap();
  }

  bool _onScroll(ScrollNotification notification) {
    if (_headerDragging || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    switch (notification) {
      case ScrollStartNotification(dragDetails: != null):
        if (!_dragging) setState(() => _dragging = true);
        _overscrollCredit = 0;
        _lastExpandExcess = 0;
      case ScrollUpdateNotification(:final scrollDelta)
          when _dragging &&
                scrollDelta != null &&
                notification.metrics.pixels >
                    notification.metrics.minScrollExtent:
        if (scrollDelta > 0) {
          // The list itself is moving into its content under the drag, so
          // settle the header collapsed — but keep the drag live so the
          // header still tracks the finger if the gesture reverses. The
          // pixels guard skips bounce-back ballistics at the top edge,
          // which must not collapse a just-expanded header.
          _settle(false, keepDragging: true);
        }
      case OverscrollNotification(:final overscroll, dragDetails: != null):
        if (overscroll > 0) {
          // Bottom overscroll still collapses the header (short lists).
          _setExtent(_headerExtent - overscroll);
        }
      case ScrollEndNotification():
        _snap();
      case UserScrollNotification(direction: ScrollDirection.idle):
        _snap();
      default:
        break;
    }
    return false;
  }

  /// Collapses the header by [pixels] of forward (scroll-down) user drag.
  /// Returns the drag delta that is left for the list to scroll, so the
  /// header always collapses before the content moves (collapse-first
  /// ordering). Called from [_DesignHeaderScrollPhysics].
  double _consumeForwardUserOffset(double pixels) {
    // A forward movement cancels any accumulated expansion pull.
    _overscrollCredit = 0;
    _lastExpandExcess = 0;
    final room = _headerRoom;
    if (room <= 0) return pixels;
    final consumed = pixels.clamp(0.0, room);
    if (consumed > 0) _setExtent(_headerExtent - consumed);
    return pixels - consumed;
  }

  /// Expands the header by [pixels] of continued reverse (scroll-up) user
  /// drag at the top of the list, after a deliberate dead zone. Returns 0
  /// while the pull is still growing the header (the pixels become header
  /// extent, keeping the list pinned at its top edge), or [pixels] once the
  /// header is fully open (a genuine overscroll that can arm pull-to-
  /// refresh). Called from [_DesignHeaderScrollPhysics].
  double _consumeReverseUserOffset(double pixels) {
    if (widget.forceCollapsed) return pixels;
    // Virtual extent where this pull started: the live extent minus what the
    // pull has already granted. Recomputing it each event keeps the mapping
    // absolute (linear in total pull length) while tolerating extent changes
    // from outside this pull, and it can never snap a partially open header
    // down to collapsed.
    final virtualStart = _headerExtent - _lastExpandExcess;
    final available = designHeaderExpandedHeight - virtualStart;
    if (available <= 0) return pixels;
    _overscrollCredit += pixels;
    final excess = _overscrollCredit - designHeaderExpandFriction;
    final target = excess.clamp(0.0, available);
    final delta = target - _lastExpandExcess;
    _lastExpandExcess = target;
    if (delta != 0) _setExtent(_headerExtent + delta);
    // Nothing reaches the list until the header is fully open: the dead
    // zone and the growth itself are swallowed, so the RefreshIndicator
    // cannot arm from the expansion pull. A pull past a fully open header
    // overscrolls normally and lets pull-to-refresh arm.
    if (delta == 0 && _headerExtent >= designHeaderExpandedHeight) {
      return pixels;
    }
    return 0;
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
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: _onHeaderDragStart,
            onVerticalDragUpdate: _onHeaderDragUpdate,
            onVerticalDragEnd: _onHeaderDragEnd,
            onVerticalDragCancel: _onHeaderDragCancel,
            child: DesignHeader(
              progress: widget.forceCollapsed ? 0 : _progress,
              duration: _dragging ? Duration.zero : designMotionDuration,
              title: widget.title,
              leading: leading,
              onCollapsedTitleTap: widget.onCollapsedTitleTap,
              actions: widget.actions,
              expandedTitleSize: widget.expandedTitleSize,
              collapsedTitleSize: widget.collapsedTitleSize,
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: ScrollConfiguration(
                behavior: _DesignScrollBehavior(state: this),
                child: PrimaryScrollController(
                  controller: _scrollController,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [ScrollBehavior] for bodies under a [CollapsibleDesignBody]: always
/// scrollable, and forward user drags collapse the header before the list
/// scrolls.
class _DesignScrollBehavior extends MaterialScrollBehavior {
  const _DesignScrollBehavior({required this.state});

  /// The enclosing header state.
  final _CollapsibleDesignBodyState state;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final alwaysScrollable = AlwaysScrollableScrollPhysics(
      parent: super.getScrollPhysics(context),
    );
    return _DesignHeaderScrollPhysics(state: state, parent: alwaysScrollable);
  }
}

/// Physics that hand the forward (scroll-down) part of a user drag to the
/// collapsible header first, so the header collapses before the list starts
/// scrolling (collapse-first ordering). The leftover delta then scrolls the
/// list normally.
class _DesignHeaderScrollPhysics extends ScrollPhysics {
  const _DesignHeaderScrollPhysics({required this.state, super.parent});

  final _CollapsibleDesignBodyState state;

  @override
  _DesignHeaderScrollPhysics applyTo(ScrollPhysics? child) =>
      _DesignHeaderScrollPhysics(state: state, parent: buildParent(child));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (position.axis != Axis.vertical ||
        state._headerDragging ||
        !state.mounted) {
      return super.applyPhysicsToUserOffset(position, offset);
    }
    if (offset < 0) {
      // Finger-up drag (toward the list end): collapse the header first; the
      // list receives only the leftover, so content stays pinned until the
      // header is fully collapsed. applyUserOffset does
      // setPixels(pixels - applied), so negative offsets grow pixels.
      final leftover = state._consumeForwardUserOffset(-offset);
      return super.applyPhysicsToUserOffset(position, -leftover);
    }
    // Finger-down drag at the top edge (positive offsets shrink pixels)
    // expands the header after a deliberate dead zone; the leftover stays at
    // the edge so the list does not overscroll while the header grows.
    final positionAtTop = position.pixels <= position.minScrollExtent;
    if (positionAtTop) {
      final leftover = state._consumeReverseUserOffset(offset);
      return super.applyPhysicsToUserOffset(position, leftover);
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }
}

