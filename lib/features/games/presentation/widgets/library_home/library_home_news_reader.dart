import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../../core/localization/app_localization.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/cover_art_utils.dart';
import '../../../../../core/utils/date_time_format.dart';
import '../../../../../models/game_news_item.dart';
import '../../../../../models/news_body.dart';
import '../../../../../providers/cover_art/cover_art_provider.dart';
import '../../../../../providers/games/single_game_provider.dart';
import '../../../../../providers/system/platform_shell_provider.dart';
import 'library_home_news_card.dart';

/// Opens [item] in the in-app reader.
///
/// A plain modal route, so closing it is what frees it: the route, its state,
/// and its subtree are disposed on pop and nothing outside holds a reference to
/// either the route or the article text — the string it renders belongs to the
/// news provider, which owns it whether the reader is open or not. The artwork
/// is the same [ImageProvider] the shelf tile behind it already painted, at the
/// same resolution, so opening the reader decodes no second copy of it.
Future<void> showLibraryHomeNewsReader(
  BuildContext context,
  GameNewsItem item,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: AppColors.nightDune.withValues(alpha: 0.82),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => _NewsReader(item: item),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _NewsReader extends ConsumerStatefulWidget {
  const _NewsReader({required this.item});

  final GameNewsItem item;

  /// Test seam for the reader's root.
  static const Key readerKey = ValueKey<String>('libraryHomeNewsReader');

  /// The panel takes the window, minus a margin thin enough that the app
  /// behind it reads as background rather than as a second thing to look at.
  static const double _windowInset = 20;
  static const double _heroHeight = 200;

  /// A line much longer than this is hard to track back to the next one, so
  /// the prose column stops here however wide the panel gets.
  static const double _textMeasure = 760;

  @override
  ConsumerState<_NewsReader> createState() => _NewsReaderState();
}

class _NewsReaderState extends ConsumerState<_NewsReader> {
  /// Shared by the scroll view and its scrollbar on purpose. Windows does not
  /// hand a widget the primary scroll controller the way the touch platforms
  /// do, so a scrollbar left to find one on its own paints a thumb it cannot
  /// drag: the wheel scrolled, grabbing the bar did nothing.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final l10n = context.l10n;
    final gameName = ref.watch(
      singleGameProvider(item.gamePath).select((g) => g?.name),
    );
    final body = item.body;

    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      label: item.title,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).maybePop(),
        },
        child: FocusScope(
          autofocus: true,
          child: Padding(
            padding: const EdgeInsets.all(_NewsReader._windowInset),
            // The reader is its own route, so it brings the Material the rest
            // of the app's text styling is defined against.
            child: Material(
              key: _NewsReader.readerKey,
              color: AppColors.surface,
              shape: const Border.fromBorderSide(
                BorderSide(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReaderHero(
                    item: item,
                    gameName: gameName,
                    height: _NewsReader._heroHeight,
                  ),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.borderSubtle,
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: _scrollController,
                      // A long announcement is the normal case here, so the bar
                      // stays put rather than fading in on the first scroll.
                      thumbVisibility: true,
                      interactive: true,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(32, 30, 32, 36),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: _NewsReader._textMeasure,
                            ),
                            child: SelectionArea(
                              child: _ReaderBody(
                                body: body,
                                fallback: l10n.libraryHomeNewsBodyUnavailable,
                                onOpenLink: (url) => ref
                                    .read(platformShellServiceProvider)
                                    .launchUri(url),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.borderSubtle,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => ref
                              .read(platformShellServiceProvider)
                              .launchUri(item.url),
                          icon: const Icon(LucideIcons.externalLink, size: 16),
                          label: Text(l10n.libraryHomeNewsOpenAction),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          child: Text(l10n.libraryHomeNewsCloseAction),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The announcement itself, as spaced paragraphs rather than one wall of text.
///
/// The sanitizer hands over plain text whose only structure is blank lines
/// between paragraphs and `- ` in front of list items. Rendering that as a
/// single [Text] leaves the paragraphs a bare line-height apart, which is what
/// made a patch-notes post unreadable; each block gets its own widget and real
/// space around it instead.
class _ReaderBody extends StatefulWidget {
  const _ReaderBody({
    required this.body,
    required this.fallback,
    required this.onOpenLink,
  });

  final String? body;
  final String fallback;
  final ValueChanged<String> onOpenLink;

  @override
  State<_ReaderBody> createState() => _ReaderBodyState();
}

class _ReaderBodyState extends State<_ReaderBody> {
  static const double _paragraphGap = 18;
  static const double _bulletGap = 8;
  static const double _headingGap = 30;

  /// Blocks paired with their spans, prepared once rather than per build: the
  /// recognizers below are owned objects, so rebuilding them on every frame
  /// would mean disposing objects a painted paragraph still points at.
  late List<(ReaderBodyBlock, List<ReaderBodySpan>)> _blocks;

  /// One recognizer per link target, prepared alongside [_blocks] and held
  /// until the body itself changes. Built per build instead, they were disposed
  /// out from under the paragraph still holding them: this widget rebuilds on
  /// any library refresh, so a refresh landing between a link's press and its
  /// release swallowed the tap — and tripped `debugAssertNotDisposed`.
  final Map<String, TapGestureRecognizer> _recognizers =
      <String, TapGestureRecognizer>{};

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(_ReaderBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) {
      _prepare();
    }
  }

  @override
  void dispose() {
    _releaseRecognizers();
    super.dispose();
  }

  void _prepare() {
    _releaseRecognizers();
    final body = widget.body;
    _blocks = body == null
        ? const <(ReaderBodyBlock, List<ReaderBodySpan>)>[]
        : <(ReaderBodyBlock, List<ReaderBodySpan>)>[
            for (final block in readerBodyBlocks(body))
              (block, readerBodySpans(block.text)),
          ];
    for (final (_, spans) in _blocks) {
      for (final span in spans) {
        final url = span.url;
        if (url != null) {
          // The callback is read at tap time, so a recognizer outlives a
          // rebuild that hands this widget a different one.
          _recognizers[url] ??= TapGestureRecognizer()
            ..onTap = () => widget.onOpenLink(url);
        }
      }
    }
  }

  void _releaseRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.bodyLarge.copyWith(
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w400,
      height: 1.7,
    );

    if (widget.body == null) {
      return Text(
        widget.fallback,
        style: style.copyWith(color: AppColors.textMuted),
      );
    }

    final headingStyle = AppTypography.headingSmall.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w700,
      height: 1.4,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < _blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(top: _gapBefore(i)),
            child: switch (_blocks[i].$1) {
              (isHeading: true, text: _, isBullet: _) => _paragraph(
                _blocks[i].$2,
                headingStyle,
              ),
              (isBullet: true, text: _, isHeading: _) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 12),
                    child: Text('•', style: style),
                  ),
                  Expanded(child: _paragraph(_blocks[i].$2, style)),
                ],
              ),
              _ => _paragraph(_blocks[i].$2, style),
            },
          ),
      ],
    );
  }

  Widget _paragraph(List<ReaderBodySpan> spans, TextStyle style) {
    if (spans.length == 1 && spans.single.url == null) {
      return Text(spans.single.text, style: style);
    }

    final linkStyle = style.copyWith(
      color: AppColors.accent,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.accent.withValues(alpha: 0.5),
    );

    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          for (final span in spans)
            if (span.url == null)
              TextSpan(text: span.text)
            else
              TextSpan(
                text: span.text,
                style: linkStyle,
                mouseCursor: SystemMouseCursors.click,
                recognizer: _recognizers[span.url],
              ),
        ],
      ),
      style: style,
    );
  }

  /// Runs of bullets sit tight together; a heading gets extra air above it so
  /// it reads as the start of a section rather than another paragraph.
  double _gapBefore(int index) {
    if (index == 0) return 0;
    if (_blocks[index].$1.isHeading) return _headingGap;
    if (_blocks[index].$1.isBullet && _blocks[index - 1].$1.isBullet) {
      return _bulletGap;
    }
    return _paragraphGap;
  }
}

/// Title block over the game's artwork — the tile the reader was opened from,
/// grown to a banner.
class _ReaderHero extends ConsumerWidget {
  const _ReaderHero({
    required this.item,
    required this.gameName,
    required this.height,
  });

  final GameNewsItem item;
  final String? gameName;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final cover = imageProviderFromCover(
      ref.watch(coverArtProvider(item.gamePath)).value,
    );

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null)
            Image(
              image: coverDecodedFor(
                cover,
                context: context,
                // The hero spans the panel, which is the window less its inset
                // on each side.
                logicalWidth:
                    MediaQuery.sizeOf(context).width -
                    _NewsReader._windowInset * 2,
              ),
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.3),
              filterQuality: FilterQuality.low,
              errorBuilder: (_, _, _) => const SizedBox.expand(),
            ),
          const DecoratedBox(decoration: BoxDecoration(gradient: _heroScrim)),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  newsByline(l10n, gameName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    color: AppColors.richGold,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.headingMedium.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatLocalMonthDayTime(
                    item.publishedAt,
                    locale: Localizations.localeOf(context),
                  ),
                  style: AppTypography.label.copyWith(
                    color: AppColors.textPrimary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Tooltip(
              message: l10n.libraryHomeNewsCloseAction,
              child: Material(
                color: AppColors.nightDune.withValues(alpha: 0.6),
                child: InkWell(
                  onTap: () => Navigator.of(context).maybePop(),
                  mouseCursor: SystemMouseCursors.click,
                  hoverColor: AppColors.hoverSurface,
                  highlightColor: Colors.transparent,
                  splashFactory: NoSplash.splashFactory,
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(
                      LucideIcons.x,
                      size: 17,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Heavier at the bottom than the tile's scrim: the hero carries a heading, not
/// a caption.
const LinearGradient _heroScrim = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: <Color>[Color(0x66121B24), Color(0xCC121B24), Color(0xFA121B24)],
  stops: <double>[0, 0.5, 1],
);
