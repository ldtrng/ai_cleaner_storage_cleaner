import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../core/format.dart';
import '../data/media_repository.dart';
import '../theme/app_theme.dart';

/// Scaffold with the soft vertical gradient used throughout the app.
class GradientScaffold extends StatelessWidget {
  const GradientScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottom,
    this.title,
    this.actions,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottom;
  final String? title;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [t.bgTop, t.bgBottom],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar:
            appBar ??
            (title != null
                ? AppBar(title: Text(title!), actions: actions)
                : null),
        body: body,
        bottomNavigationBar: bottom,
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.radius = 28,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? context.tokens.card,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Bottom action area: a stadium button over a fade.
class BottomAction extends StatelessWidget {
  const BottomAction({
    super.key,
    required this.label,
    this.onPressed,
    this.secondary,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? secondary;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.tokens.bgBottom.withValues(alpha: 0),
            context.tokens.bgBottom,
          ],
          stops: const [0, 0.35],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (secondary != null) ...[secondary!, const SizedBox(height: 8)],
          FilledButton(
            onPressed: onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                ],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The five palette pills stacked, as in the brand artwork.
class PillStack extends StatelessWidget {
  const PillStack({super.key, this.width = 220, this.progress = 1, this.child});

  final double width;

  /// 0..1 entrance animation.
  final double progress;
  final Widget? child;

  static const colors = [
    Palette.forest,
    Palette.moss,
    Palette.sage,
    Palette.mist,
    Palette.cream,
  ];

  @override
  Widget build(BuildContext context) {
    final h = width * 0.42;
    final step = h * 0.48;
    return SizedBox(
      width: width,
      height: step * 4 + h,
      child: Stack(
        children: [
          for (var i = 0; i < 5; i++)
            Builder(
              builder: (context) {
                final local = ((progress * 5) - i).clamp(0.0, 1.0);
                final eased = Curves.easeOutBack.transform(local);
                return Positioned(
                  left: 0,
                  right: 0,
                  top: step * i * eased,
                  child: Opacity(
                    opacity: local,
                    child: Container(
                      height: h,
                      decoration: BoxDecoration(
                        color: colors[i],
                        borderRadius: BorderRadius.circular(h),
                        boxShadow: [
                          BoxShadow(
                            color: Palette.forest.withValues(alpha: 0.18),
                            blurRadius: 18,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      alignment: const Alignment(0, -0.45),
                      child: i == 4 ? child : null,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = Icons.spa_rounded,
    this.title = 'Nothing to clean here.',
    this.message,
  });

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: context.tokens.card,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: Palette.sage),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: context.text.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: context.text.bodyMedium?.copyWith(
                  color: context.tokens.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NoAccessView extends StatelessWidget {
  const NoAccessView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.onAllow,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PillIcon(icon: icon, size: 88),
            const SizedBox(height: 24),
            Text(
              title,
              style: context.text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: context.text.bodyMedium?.copyWith(
                color: context.tokens.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton(onPressed: onAllow, child: const Text('Allow access')),
          ],
        ),
      ),
    );
  }
}

/// Icon on a rounded tile using palette colours.
class PillIcon extends StatelessWidget {
  const PillIcon({
    super.key,
    required this.icon,
    this.size = 48,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final double size;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? (dark ? Palette.moss : Palette.cream),
        borderRadius: BorderRadius.circular(size * 0.36),
      ),
      child: Icon(
        icon,
        size: size * 0.5,
        color: foreground ?? (dark ? Palette.cream : Palette.moss),
      ),
    );
  }
}

/// Horizontal chips used as category tabs.
class CategoryChips<T> extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.items,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<T> items;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          final on = item == selected;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: on
                  ? (dark ? Palette.cream : Palette.moss)
                  : context.tokens.card,
              borderRadius: BorderRadius.circular(22),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => onSelected(item),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Center(
                  child: Text(
                    label(item),
                    style: font(
                      14,
                      FontWeight.w600,
                      color: on
                          ? (dark ? Palette.forest : Palette.cream)
                          : (dark ? Palette.cream : Palette.forest),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Square gallery thumbnail with selection state.
class MediaThumb extends StatelessWidget {
  const MediaThumb({
    super.key,
    required this.item,
    this.selected = false,
    this.best = false,
    this.onTap,
    this.onLongPress,
    this.showSize = false,
    this.selectable = true,
  });

  final MediaItem item;
  final bool selected;
  final bool best;
  final bool showSize;
  final bool selectable;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: context.tokens.track),
            Image(
              image: AssetEntityImageProvider(
                item.entity,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize.square(240),
              ),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined, color: Palette.sage),
            ),
            if (selected)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Palette.forest.withValues(alpha: 0.28),
                ),
              ),
            if (item.isVideo)
              Positioned(
                left: 6,
                bottom: 6,
                child: _Badge(
                  icon: Icons.play_arrow_rounded,
                  text: formatDuration(item.durationMs),
                ),
              ),
            if (showSize)
              Positioned(
                left: 6,
                bottom: item.isVideo ? 32 : 6,
                child: _Badge(text: formatBytes(item.size)),
              ),
            if (best)
              const Positioned(
                left: 6,
                top: 6,
                child: _Badge(
                  icon: Icons.star_rounded,
                  text: 'Best',
                  light: true,
                ),
              ),
            if (selectable)
              Positioned(
                right: 6,
                bottom: 6,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? Palette.cream
                        : Colors.black.withValues(alpha: 0.15),
                    border: Border.all(
                      color: selected ? Palette.moss : Colors.white,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: Palette.moss,
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({this.icon, required this.text, this.light = false});
  final IconData? icon;
  final String text;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final fg = light ? Palette.forest : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: light ? Palette.cream : Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) Icon(icon, size: 13, color: fg),
          if (icon != null) const SizedBox(width: 2),
          Text(text, style: font(11, FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

class SelectAllButton extends StatelessWidget {
  const SelectAllButton({
    super.key,
    required this.allSelected,
    required this.onChanged,
  });
  final bool allSelected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => onChanged(!allSelected),
      child: Text(allSelected ? 'Deselect all' : 'Select all'),
    );
  }
}

Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirm = 'Delete',
  String cancel = "Don't allow",
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message != null ? Text(message) : null,
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(cancel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirm),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return r ?? false;
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Runs [task] behind a full-screen "Cleaning…" overlay.
Future<T> runWithProgress<T>(
  BuildContext context,
  Future<T> Function(ValueNotifier<double?> progress) task, {
  String title = 'Cleaning...',
  String message = "We're sweeping away the clutter for you",
}) async {
  final progress = ValueNotifier<double?>(null);
  final nav = Navigator.of(context);
  nav.push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: false,
      pageBuilder: (_, _, _) => PopScope(
        canPop: false,
        child: ProgressOverlay(
          title: title,
          message: message,
          progress: progress,
        ),
      ),
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
  try {
    return await task(progress);
  } finally {
    nav.pop();
    progress.dispose();
  }
}

class ProgressOverlay extends StatefulWidget {
  const ProgressOverlay({
    super.key,
    required this.title,
    required this.message,
    required this.progress,
  });
  final String title;
  final String message;
  final ValueNotifier<double?> progress;

  @override
  State<ProgressOverlay> createState() => _ProgressOverlayState();
}

class _ProgressOverlayState extends State<ProgressOverlay>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder(
                valueListenable: widget.progress,
                builder: (context, p, _) => SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      RotationTransition(
                        turns: _spin,
                        child: CustomPaint(
                          size: const Size.square(180),
                          painter: _OrbitPainter(context.isDark),
                        ),
                      ),
                      SizedBox(
                        width: 132,
                        height: 132,
                        child: CircularProgressIndicator(
                          value: p,
                          strokeWidth: 10,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Text(
                        p == null ? '' : '${(p * 100).round()}%',
                        style: context.text.headlineSmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(widget.title, style: context.text.headlineSmall),
              const SizedBox(height: 8),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(
                  color: context.tokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const colors = PillStack.colors;
    for (var i = 0; i < 5; i++) {
      final angle = i * 2 * 3.14159 / 5;
      final o = c + Offset.fromDirection(angle, size.width / 2 - 8);
      canvas.drawCircle(
        o,
        7 - i * 0.6,
        Paint()..color = colors[dark ? 4 - i : i],
      );
    }
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => old.dark != dark;
}
