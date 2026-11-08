import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/readings_store.dart';
import '../../domain/cairo_time.dart';
import '../../domain/coptic_calendar.dart';
import '../../domain/daily_verse.dart';
import '../../domain/readings.dart';
import '../../domain/season_verses.dart';
import '../../state/providers.dart';

sealed class _KatamerosItem {
  final Key key;
  const _KatamerosItem(this.key);
}

class _CommemorationItem extends _KatamerosItem {
  final String title;
  const _CommemorationItem(this.title) : super(const ValueKey('commemoration_item'));
}

class _SectionHeaderItem extends _KatamerosItem {
  final String sectionKey;
  final ReadingsSection section;
  _SectionHeaderItem(this.sectionKey, this.section) : super(ValueKey('section_$sectionKey'));
}

class _ReadingCardItem extends _KatamerosItem {
  final String sectionKey;
  final int readingIndex;
  final ReadingItem reading;
  _ReadingCardItem(this.sectionKey, this.readingIndex, this.reading)
      : super(ValueKey('reading_${sectionKey}_$readingIndex'));
}

class _AttributionItem extends _KatamerosItem {
  const _AttributionItem() : super(const ValueKey('attribution_item'));
}

/// Reading screen for the day's Verse of the Day and Katameros readings (`/readings/:date`, ADR-058).
///
/// Operates offline from the cached JSON (`ReadingsStore`), provides font-size
/// scaling (A- / A+), day switcher, and responsive tabs for verse / Katameros.
class ReadingsPage extends ConsumerStatefulWidget {
  final String dateIso;
  final String? initialTab;

  const ReadingsPage({
    super.key,
    required this.dateIso,
    this.initialTab,
  });

  @override
  ConsumerState<ReadingsPage> createState() => _ReadingsPageState();
}

class _ReadingsPageState extends ConsumerState<ReadingsPage> {
  late DateTime _currentDate;
  int _selectedTab = 0; // 0 = katameros, 1 = verse
  bool _isLoading = true;
  DayReadings? _readings;
  String? _errorMessage;
  final ReadingsStore _store = ReadingsStore();
  final ScrollController _scrollController = ScrollController();
  double _scrollAccumulator = 0.0;

  @override
  void initState() {
    super.initState();
    _currentDate = _parseDate(widget.dateIso);
    if (widget.initialTab == 'verse') {
      _selectedTab = 1;
    } else {
      _selectedTab = 0;
    }
    _loadReadings();
  }

  @override
  void didUpdateWidget(ReadingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateIso != widget.dateIso) {
      _currentDate = _parseDate(widget.dateIso);
      _resetScroll(postFrame: true);
      _loadReadings();
    }
    if (oldWidget.initialTab != widget.initialTab && widget.initialTab != null) {
      final newTab = widget.initialTab == 'verse' ? 1 : 0;
      if (_selectedTab != newTab) {
        if (newTab == 1) {
          _resetFocusPostFrame();
        }
        _selectedTab = newTab;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ref.read(readerFocusModeProvider.notifier).setFocus(false);
      } catch (_) {}
    });
    super.dispose();
  }

  void _resetFocusPostFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(readerFocusModeProvider.notifier).setFocus(false);
      }
    });
  }

  void _resetScroll({bool postFrame = false}) {
    _scrollAccumulator = 0.0;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0.0);
    }
    if (postFrame) {
      _resetFocusPostFrame();
    } else {
      ref.read(readerFocusModeProvider.notifier).setFocus(false);
    }
  }

  bool _onScrollNotification(ScrollUpdateNotification n) {
    if (_selectedTab != 0) return false;
    final offset = n.metrics.pixels;
    if (offset <= 24.0) {
      _scrollAccumulator = 0.0;
      ref.read(readerFocusModeProvider.notifier).setFocus(false);
      return false;
    }
    final dy = n.scrollDelta ?? 0.0;
    if (dy > 0) {
      // Scrolling down (reading forward)
      if (_scrollAccumulator < 0) _scrollAccumulator = 0;
      _scrollAccumulator += dy;
      if (_scrollAccumulator >= 40.0 && offset >= 60.0) {
        ref.read(readerFocusModeProvider.notifier).setFocus(true);
      }
    } else if (dy < 0) {
      // Scrolling up (returning towards top)
      if (_scrollAccumulator > 0) _scrollAccumulator = 0;
      _scrollAccumulator += dy; // dy is negative
      if (_scrollAccumulator <= -40.0) {
        ref.read(readerFocusModeProvider.notifier).setFocus(false);
      }
    }
    return false;
  }

  DateTime _parseDate(String iso) {
    try {
      final parts = iso.split('-');
      if (parts.length == 3) {
        final y = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final d = int.parse(parts[2]);
        return DateTime.utc(y, m, d);
      }
    } catch (_) {}
    final now = CairoTime.now();
    return DateTime.utc(now.year, now.month, now.day);
  }

  String get _currentIso {
    final y = _currentDate.year.toString().padLeft(4, '0');
    final m = _currentDate.month.toString().padLeft(2, '0');
    final d = _currentDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Bumped per request: a slower answer for a date the user already left is dropped, so the page
  /// never shows one day's header with another day's readings.
  int _loadGeneration = 0;

  Future<void> _loadReadings({bool forceFetch = false}) async {
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _store.getReadings(_currentIso, forceFetch: forceFetch);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _readings = data;
        _isLoading = false;
        if (data == null) {
          _errorMessage = context.isAr
              ? 'تعذّر تحميل قراءات هذا اليوم — اتصل بالإنترنت وحاول مجددًا'
              : 'Could not load readings for this day. Connect to the internet and try again.';
        }
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _readings = null;
        _isLoading = false;
        _errorMessage = context.isAr
            ? 'تعذّر تحميل قراءات هذا اليوم — اتصل بالإنترنت وحاول مجددًا'
            : 'Could not load readings for this day. Connect to the internet and try again.';
      });
    }
  }

  void _shiftDay(int deltaDays) {
    _resetScroll();
    final next = _currentDate.add(Duration(days: deltaDays));
    final y = next.year.toString().padLeft(4, '0');
    final m = next.month.toString().padLeft(2, '0');
    final d = next.day.toString().padLeft(2, '0');
    final targetIso = '$y-$m-$d';
    final tabParam = _selectedTab == 1 ? '?tab=verse' : '?tab=katameros';
    try {
      context.go('/readings/$targetIso$tabParam');
    } catch (_) {
      setState(() {
        _currentDate = next;
      });
      _loadReadings();
    }
  }

  void _shareReading() {
    final url =
        'https://maximos-domadios-church.web.app/readings/$_currentIso?tab=${_selectedTab == 1 ? 'verse' : 'katameros'}';
    Clipboard.setData(ClipboardData(text: url));
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.isAr ? 'تم نسخ الرابط' : 'Link copied'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {}
  }

  List<_KatamerosItem> _buildKatamerosItems(DayReadings readings, bool isAr) {
    final items = <_KatamerosItem>[];
    final feastTitle = readings.title(isAr);
    if (feastTitle.isNotEmpty) {
      items.add(_CommemorationItem(feastTitle));
    }

    for (final section in readings.sections) {
      items.add(_SectionHeaderItem(section.key, section));
      for (var i = 0; i < section.readings.length; i++) {
        items.add(_ReadingCardItem(section.key, i, section.readings[i]));
      }
    }

    items.add(const _AttributionItem());
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final isAr = context.isAr;
    final textScale = ref.watch(readingTextScaleProvider);
    final versesAsync = ref.watch(dailyVersesProvider);
    final verses = versesAsync.value ?? const [];
    final features = ref.watch(featuresProvider);
    final seasons = features.seasonVerses.isEmpty ? null : ref.watch(seasonsProvider);
    final noon = CairoTime.at(_currentDate.year, _currentDate.month, _currentDate.day, 12 * 60);
    final seasonSet = seasons == null
        ? const <Verse>[]
        : features.seasonVerses.activeSet(seasons.value ?? const [], noon);
    final verse = resolveSeasonalVerse(features.dailyVerse, verses, noon, day: _currentDate, seasonSet: seasonSet);
    final coptic = _readings != null && _readings!.coptic.isNotEmpty
        ? _readings!.coptic
        : CopticDate.fromGregorian(_currentDate).format(arabic: isAr);

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        bottom: false,
        child: _selectedTab == 0
            ? _buildKatamerosTab(pal, isAr, textScale, coptic)
            : _buildVerseTab(verse, pal, isAr, textScale, coptic),
      ),
    );
  }

  Widget _buildHeader(OccasionColors pal, bool isAr, double textScale, String coptic) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      color: pal.background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDayNavBar(pal, isAr, coptic),
          const SizedBox(height: 6),
          _buildTabSelector(pal, isAr),
          const SizedBox(height: 6),
          _buildControlsRow(pal, isAr, textScale),
        ],
      ),
    );
  }

  Widget _buildDayNavBar(OccasionColors pal, bool isAr, String coptic) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(kPanelRadius),
        border: Border.all(color: pal.hairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            key: const Key('prevDayButton'),
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: isAr ? 'اليوم السابق' : 'Previous day',
            onPressed: () => _shiftDay(-1),
          ),
          Expanded(
            child: Text(
              '$_currentIso • $coptic',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: pal.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            key: const Key('nextDayButton'),
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: isAr ? 'اليوم التالي' : 'Next day',
            onPressed: () => _shiftDay(1),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector(OccasionColors pal, bool isAr) {
    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: pal.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: const Key('katamerosTabButton'),
              borderRadius: BorderRadius.circular(999),
              onTap: () {
                if (_selectedTab != 0) {
                  setState(() => _selectedTab = 0);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedTab == 0 ? pal.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  isAr ? 'القطمارس' : 'Katameros',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: _selectedTab == 0 ? pal.onPrimary : pal.ink,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              key: const Key('verseTabButton'),
              borderRadius: BorderRadius.circular(999),
              onTap: () {
                if (_selectedTab != 1) {
                  ref.read(readerFocusModeProvider.notifier).setFocus(false);
                  setState(() => _selectedTab = 1);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedTab == 1 ? pal.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  isAr ? 'آية اليوم' : 'Daily Verse',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: _selectedTab == 1 ? pal.onPrimary : pal.ink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsRow(OccasionColors pal, bool isAr, double textScale) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildFontSizeControl(pal, isAr, textScale),
        IconButton(
          key: const Key('shareReadingButton'),
          tooltip: isAr ? 'مشاركة' : 'Share',
          icon: Icon(Icons.share_rounded, color: pal.primary),
          onPressed: _shareReading,
        ),
      ],
    );
  }

  Widget _buildFontSizeControl(OccasionColors pal, bool isAr, double textScale) {
    return Container(
      key: const Key('fontSizeControl'),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: pal.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('fontSizeMinus'),
            tooltip: isAr ? 'تصغير الخط' : 'Smaller text',
            icon: const Icon(Icons.remove_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: textScale > 0.85
                ? () => ref.read(readingTextScaleProvider.notifier).decrease()
                : null,
          ),
          InkWell(
            key: const Key('fontSizeReset'),
            borderRadius: BorderRadius.circular(4),
            onTap: textScale != 1.0
                ? () => ref.read(readingTextScaleProvider.notifier).reset()
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                '${(textScale * 100).round()}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: textScale != 1.0 ? pal.primary : pal.ink,
                ),
              ),
            ),
          ),
          IconButton(
            key: const Key('fontSizePlus'),
            tooltip: isAr ? 'تكبير الخط' : 'Larger text',
            icon: const Icon(Icons.add_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: textScale < 2.0
                ? () => ref.read(readingTextScaleProvider.notifier).increase()
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildKatamerosTab(OccasionColors pal, bool isAr, double textScale, String coptic) {
    final sliverHeader = SliverAppBar(
      automaticallyImplyLeading: false,
      floating: true,
      snap: true,
      pinned: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: pal.background,
      toolbarHeight: 148,
      titleSpacing: 0,
      title: _buildHeader(pal, isAr, textScale, coptic),
    );

    if (_isLoading) {
      return CustomScrollView(
        controller: _scrollController,
        scrollCacheExtent: ScrollCacheExtent.pixels(500),
        slivers: [
          sliverHeader,
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: CircularProgressIndicator(color: pal.primary),
            ),
          ),
        ],
      );
    }

    if (_errorMessage != null || _readings == null) {
      return CustomScrollView(
        controller: _scrollController,
        scrollCacheExtent: ScrollCacheExtent.pixels(500),
        slivers: [
          sliverHeader,
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 48, color: pal.muted),
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: pal.ink, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _loadReadings(forceFetch: true),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(isAr ? 'إعادة المحاولة' : 'Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final items = _buildKatamerosItems(_readings!, isAr);

    return NotificationListener<ScrollUpdateNotification>(
      onNotification: _onScrollNotification,
      child: CustomScrollView(
        controller: _scrollController,
        scrollCacheExtent: ScrollCacheExtent.pixels(500),
        slivers: [
          sliverHeader,
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverList.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _buildKatamerosItemWidget(item, pal, isAr, textScale);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKatamerosItemWidget(_KatamerosItem item, OccasionColors pal, bool isAr, double textScale) {
    return KeyedSubtree(
      key: item.key,
      child: switch (item) {
        _CommemorationItem(:final title) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: pal.panel,
                borderRadius: BorderRadius.circular(kPanelRadius),
                border: Border.all(color: pal.ornamentLine),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAr ? 'مناسبة اليوم' : "Today's Commemoration",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: pal.goldText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15 * textScale,
                      fontWeight: FontWeight.bold,
                      color: pal.primary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        _SectionHeaderItem(:final section) => Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: pal.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: pal.primary, width: 3)),
              ),
              child: Text(
                section.title(isAr),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: pal.primary,
                ),
              ),
            ),
          ),
        _ReadingCardItem(:final reading) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildReadingCard(reading, pal, isAr, textScale),
          ),
        _AttributionItem() => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              isAr ? 'المصدر: القطمارس (katameros.app)' : 'Source: Katameros (katameros.app)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: pal.muted),
            ),
          ),
      },
    );
  }

  Widget _buildReadingCard(ReadingItem item, OccasionColors pal, bool isAr, double textScale) {
    final ref = item.reference(isAr);
    final text = item.text(isAr);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pal.panel,
        borderRadius: BorderRadius.circular(kPanelRadius),
        border: Border.all(color: pal.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Kind & Reference
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                item.title(isAr),
                style: TextStyle(
                  fontSize: 14.5 * textScale,
                  fontWeight: FontWeight.bold,
                  color: pal.primary,
                ),
              ),
              if (ref.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: pal.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: pal.hairline),
                  ),
                  child: Text(
                    ref,
                    style: TextStyle(
                      fontSize: 12 * textScale,
                      fontWeight: FontWeight.w600,
                      color: pal.ink,
                    ),
                  ),
                ),
            ],
          ),

          // Introduction
          if (item.intro(isAr).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.intro(isAr),
              style: TextStyle(
                fontSize: 13 * textScale,
                fontStyle: FontStyle.italic,
                color: pal.muted,
                height: 1.4,
              ),
            ),
          ],

          // Main text
          if (text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              text,
              style: TextStyle(
                fontSize: 14.5 * textScale,
                height: 1.6,
                color: pal.ink,
              ),
            ),
          ],

          // Conclusion
          if (item.conclusion(isAr).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.conclusion(isAr),
              style: TextStyle(
                fontSize: 13 * textScale,
                fontStyle: FontStyle.italic,
                color: pal.muted,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerseTab(Verse? verse, OccasionColors pal, bool isAr, double textScale, String coptic) {
    if (verse == null) {
      return Column(
        children: [
          _buildHeader(pal, isAr, textScale, coptic),
          Expanded(
            child: Center(
              child: Text(
                isAr ? 'لا توجد آية محددة لهذا اليوم' : 'No verse available for this day',
                style: TextStyle(fontSize: 14, color: pal.muted),
              ),
            ),
          ),
        ],
      );
    }

    final disp = verse.display(english: !isAr);

    return Column(
      children: [
        _buildHeader(pal, isAr, textScale, coptic),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: pal.panel,
                    borderRadius: BorderRadius.circular(kPanelRadius),
                    border: Border.all(color: pal.ornamentLine),
                    boxShadow: pal.panelShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.format_quote_rounded, size: 36, color: pal.primary),
                      const SizedBox(height: 12),
                      Text(
                        disp.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18 * textScale,
                          height: 1.7,
                          fontWeight: FontWeight.bold,
                          color: pal.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: pal.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: pal.hairline),
                        ),
                        child: Text(
                          disp.ref,
                          style: TextStyle(
                            fontSize: 13 * textScale,
                            fontWeight: FontWeight.w600,
                            color: pal.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: _shareReading,
                        icon: const Icon(Icons.share_rounded, size: 16),
                        label: Text(isAr ? 'مشاركة الآية' : 'Share verse'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
