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
import '../../state/providers.dart';

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
  double _textScale = 1.0;
  bool _isLoading = true;
  DayReadings? _readings;
  String? _errorMessage;
  final ReadingsStore _store = ReadingsStore();

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
      _loadReadings();
    }
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

  Future<void> _loadReadings({bool forceFetch = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _store.getReadings(_currentIso, forceFetch: forceFetch);
      if (!mounted) return;
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
      if (!mounted) return;
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
    final next = _currentDate.add(Duration(days: deltaDays));
    final y = next.year.toString().padLeft(4, '0');
    final m = next.month.toString().padLeft(2, '0');
    final d = next.day.toString().padLeft(2, '0');
    final targetIso = '$y-$m-$d';
    final tabParam = _selectedTab == 1 ? '?tab=verse' : '?tab=katameros';
    context.go('/readings/$targetIso$tabParam');
  }

  void _shareReading() {
    final url = 'https://maximos-domadios-church.web.app/readings/$_currentIso';
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.isAr ? 'تم نسخ الرابط' : 'Link copied'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final isAr = context.isAr;
    final versesAsync = ref.watch(dailyVersesProvider);
    final verses = versesAsync.value ?? const [];
    final verse = verseForDate(verses, _currentDate);
    final coptic = _readings != null && _readings!.coptic.isNotEmpty
        ? _readings!.coptic
        : CopticDate.fromGregorian(_currentDate).format(arabic: isAr);

    return Scaffold(
      backgroundColor: pal.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation & Date Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: pal.surface,
                border: Border(bottom: BorderSide(color: pal.hairline)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: pal.primary),
                    tooltip: isAr ? 'الرجوع' : 'Back',
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/');
                      }
                    },
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isAr ? 'قراءات اليوم' : 'Daily Readings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: pal.primary,
                          ),
                        ),
                        Text(
                          '$_currentIso • $coptic',
                          style: TextStyle(
                            fontSize: 12,
                            color: pal.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.share_rounded, color: pal.primary),
                    tooltip: isAr ? 'مشاركة' : 'Share',
                    onPressed: _shareReading,
                  ),
                ],
              ),
            ),

            // Date Switcher Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: pal.panel,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    key: const Key('prevDayButton'),
                    icon: Icon(Icons.chevron_left_rounded, color: pal.ink),
                    tooltip: isAr ? 'اليوم السابق' : 'Previous day',
                    onPressed: () => _shiftDay(-1),
                  ),
                  // Font Size Adjusters
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        key: const Key('fontSizeMinus'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(36, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: _textScale > 0.85
                            ? () => setState(() => _textScale = (_textScale - 0.1).clamp(0.85, 1.45))
                            : null,
                        child: Text(
                          'A−',
                          style: TextStyle(fontSize: 13, color: pal.ink, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        key: const Key('fontSizePlus'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(36, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: _textScale < 1.45
                            ? () => setState(() => _textScale = (_textScale + 0.1).clamp(0.85, 1.45))
                            : null,
                        child: Text(
                          'A+',
                          style: TextStyle(fontSize: 13, color: pal.ink, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    key: const Key('nextDayButton'),
                    icon: Icon(Icons.chevron_right_rounded, color: pal.ink),
                    tooltip: isAr ? 'اليوم التالي' : 'Next day',
                    onPressed: () => _shiftDay(1),
                  ),
                ],
              ),
            ),

            // Tab Selector: Katameros vs Verse
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                      onTap: () => setState(() => _selectedTab = 0),
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
                      onTap: () => setState(() => _selectedTab = 1),
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
            ),

            // Content Area
            Expanded(
              child: _selectedTab == 0
                  ? _buildKatamerosTab(pal, isAr)
                  : _buildVerseTab(verse, pal, isAr),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKatamerosTab(OccasionColors pal, bool isAr) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: pal.primary),
      );
    }

    if (_errorMessage != null || _readings == null) {
      return Center(
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
      );
    }

    final feastTitle = _readings!.title(isAr);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (feastTitle.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
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
                    feastTitle,
                    style: TextStyle(
                      fontSize: 15 * _textScale,
                      fontWeight: FontWeight.bold,
                      color: pal.primary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

          // Render Sections
          for (final section in _readings!.sections) ...[
            _buildSectionHeader(section, pal, isAr),
            const SizedBox(height: 8),
            for (final reading in section.readings) ...[
              _buildReadingCard(reading, pal, isAr),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 16),
          ],

          // Attribution
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              isAr ? 'المصدر: القطمارس (katameros.app)' : 'Source: Katameros (katameros.app)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: pal.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ReadingsSection section, OccasionColors pal, bool isAr) {
    return Container(
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
    );
  }

  Widget _buildReadingCard(ReadingItem item, OccasionColors pal, bool isAr) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  item.title(isAr),
                  style: TextStyle(
                    fontSize: 14.5 * _textScale,
                    fontWeight: FontWeight.bold,
                    color: pal.primary,
                  ),
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
                      fontSize: 12 * _textScale,
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
                fontSize: 13 * _textScale,
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
                fontSize: 14.5 * _textScale,
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
                fontSize: 13 * _textScale,
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

  Widget _buildVerseTab(Verse? verse, OccasionColors pal, bool isAr) {
    if (verse == null) {
      return Center(
        child: Text(
          isAr ? 'لا توجد آية محددة لهذا اليوم' : 'No verse available for this day',
          style: TextStyle(fontSize: 14, color: pal.muted),
        ),
      );
    }

    final disp = verse.display(english: !isAr);

    return SingleChildScrollView(
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
                    fontSize: 18 * _textScale,
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
                      fontSize: 13 * _textScale,
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
    );
  }
}
