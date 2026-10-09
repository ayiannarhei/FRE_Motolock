import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MotoLockApp());
  loadPoppins();
}

const double kAlcoholLimit = 0.050;

const String kFont = 'Poppins';

Future<void> loadPoppins() async {
  const base =
      'https://raw.githubusercontent.com/google/fonts/main/ofl/poppins/Poppins-';
  const weights = ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold', 'Black'];
  try {
    final loader = FontLoader(kFont);
    for (final weight in weights) {
      loader.addFont(http
          .get(Uri.parse('$base$weight.ttf'))
          .then((response) => ByteData.sublistView(response.bodyBytes)));
    }
    await loader.load().timeout(const Duration(seconds: 8));
  } catch (_) {
    // Offline or blocked: keep the default font.
  }
}

final Uint8List kLogoBytes = base64Decode(kLogoPng);

// ============================================================
// BRAND COLORS 
// ============================================================

class C {
  static const red = Color(0xFFED1C24); // MotoLock red (app accent)
  static const darkRed = Color(0xFFA3141A);
  static const softRed = Color(0xFFFFEDEE);
  static const ink = Color(0xFF101217); // logo black / app text
  static const ink2 = Color(0xFF2A2F38);
  static const slate = Color(0xFF3B4252);
  static const gray = Color(0xFF737987); // secondary text
  static const muted = Color(0xFFB0B5C1);
  static const border = Color(0xFFE8EBF0);
  static const surface = Color(0xFFF7F8FA); // app background
  static const white = Colors.white;
  static const green = Color(0xFF0E9F6E); // "allowed" state in the app
  static const amber = Color(0xFFF59E0B);
}

// ============================================================
// OUTCOMES 
// ============================================================

enum Outcome {
  unlocked('Unlocked', 'Motorcycle unlocked', C.green, Icons.lock_open_rounded),
  blocked('Blocked', 'Blocked: alcohol detected', C.red, Icons.no_drinks_rounded),
  face('Face Not Recognized', 'Blocked: rider verification failed', C.slate,
      Icons.face_retouching_off_rounded);

  final String label;
  final String result;
  final Color color;
  final IconData icon;

  const Outcome(this.label, this.result, this.color, this.icon);

  static Outcome of(String status) {
    switch (status) {
      case 'failed_brac':
        return Outcome.blocked;
      case 'failed_face':
        return Outcome.face;
      default:
        // completed, ongoing, unlocked, passed
        return status.startsWith('failed') ? Outcome.blocked : Outcome.unlocked;
    }
  }
}

// ============================================================
// BrAC RANGES 
// ============================================================

class BracRange {
  final String label;
  final double min;
  final double? max; // exclusive; null = no upper bound

  const BracRange(this.label, this.min, this.max);

  bool contains(double v) => v >= min && (max == null || v < max!);
  bool get overLimit => min >= kAlcoholLimit;
}

const bracRanges = [
  BracRange('0.000', 0, 0.001),
  BracRange('0.001–0.019', 0.001, 0.020),
  BracRange('0.020–0.049', 0.020, kAlcoholLimit),
  BracRange('0.050–0.099', kAlcoholLimit, 0.100),
  BracRange('0.100+', 0.100, null),
];

// ============================================================
// RIDE RECORD MODEL
// ============================================================

class Ride {
  final String id;
  final String rider;
  final String riderName;
  final String device;
  final String status;
  final DateTime started;
  final double? initial;
  final double? finalReading;
  final String? failureReason;

  const Ride({
    required this.id,
    required this.rider,
    required this.riderName,
    required this.device,
    required this.status,
    required this.started,
    required this.initial,
    required this.finalReading,
    this.failureReason,
  });

  Outcome get outcome => Outcome.of(status);

  String get result =>
      failureReason?.isNotEmpty == true ? failureReason! : outcome.result;

  /// Final BrAC shown in the records. A blocked attempt ends at the
  /// sobriety test, so its test reading is also its final reading.
  double? get finalShown =>
      finalReading ?? (outcome == Outcome.unlocked ? null : initial);
}

// ============================================================
// CSV PARSING
// ============================================================

List<List<dynamic>> decodeCsv(String text) =>
    csv.decode(text.replaceFirst('﻿', ''));

class RideCsv {
  static const requiredColumns = [
    'id',
    'rider_id',
    'device_id',
    'start_time',
    'initial_brac_level',
    'final_brac_level',
    'status',
  ];

  static List<Ride> parse(String text) {
    final rows = decodeCsv(text);
    if (rows.isEmpty) throw const FormatException('CSV is empty.');

    final headers =
        rows.first.map((v) => v.toString().trim().toLowerCase()).toList();

    // Supabase exports user_id; older exports used rider_id.
    final riderIndex = headers.contains('rider_id')
        ? headers.indexOf('rider_id')
        : headers.indexOf('user_id');

    for (final name in requiredColumns) {
      if (name == 'rider_id' && riderIndex >= 0) continue;
      if (!headers.contains(name)) {
        throw FormatException('Missing CSV column: $name');
      }
    }

    final index = {
      for (final name in [...requiredColumns, 'failure_reason'])
        name: name == 'rider_id' ? riderIndex : headers.indexOf(name),
    };

    String field(List<dynamic> row, String name) {
      final i = index[name]!;
      if (i < 0 || i >= row.length) return '';
      return row[i].toString().trim();
    }

    String? nullable(String value) {
      if (value.isEmpty || value.toLowerCase() == 'null') return null;
      return value;
    }

    double? number(String value) {
      final cleaned = nullable(value);
      return cleaned == null ? null : double.tryParse(cleaned);
    }

    DateTime? time(String value) {
      final cleaned = nullable(value);
      if (cleaned == null) return null;
      // "2026-09-16 06:00:00+00" -> "2026-09-16T06:00:00+00:00"
      final formatted = cleaned.replaceFirst(' ', 'T').replaceFirstMapped(
            RegExp(r'([+-]\d{2})$'),
            (m) => '${m.group(1)}:00',
          );
      return DateTime.tryParse(formatted)?.toUtc();
    }

    // The export may shorten ids to their first 8 characters.
    String nameFor(String rider) {
      final key = rider.toLowerCase();
      if (key.isEmpty) return 'Unknown rider';
      for (final entry in kRiderNames.entries) {
        if (entry.key == key ||
            entry.key.startsWith(key) ||
            key.startsWith(entry.key)) {
          return entry.value;
        }
      }
      return 'Rider ${shortId(rider)}';
    }

    // Pass 1: read the rows that have a valid start time.
    final entries = <(List<dynamic>, DateTime, String, String)>[];
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((cell) => cell.toString().trim().isEmpty)) continue;

      final started = time(field(row, 'start_time'));
      if (started == null) {
        throw FormatException('Invalid start_time in CSV row ${i + 1}.');
      }
      entries.add((
        row,
        started,
        nullable(field(row, 'rider_id')) ?? '',
        nullable(field(row, 'device_id')) ?? '',
      ));
    }
    entries.sort((a, b) => a.$2.compareTo(b.$2)); // oldest first

    // Pass 2: give every MotoLock unit a readable code (MOTO-0001, ...),
    // numbered by first use. Rows saved without device_id belong to the
    // unit their rider normally uses; a rider with no recorded unit gets
    // one of their own.
    final usual = <String, Map<String, int>>{};
    for (final e in entries) {
      if (e.$4.isEmpty) continue;
      final counts = usual.putIfAbsent(e.$3, () => {});
      counts[e.$4] = (counts[e.$4] ?? 0) + 1;
    }
    String unitOf(String rider, String device) {
      if (device.isNotEmpty) return device;
      final counts = usual[rider];
      if (counts == null || counts.isEmpty) return 'rider:$rider';
      return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    }

    final codes = <String, String>{};
    final result = <Ride>[];
    for (final (row, started, rider, device) in entries) {
      final unit = unitOf(rider, device);
      final code = codes.putIfAbsent(
          unit, () => 'MOTO-${(codes.length + 1).toString().padLeft(4, '0')}');
      result.add(Ride(
        id: field(row, 'id'),
        rider: rider,
        riderName: nameFor(rider),
        device: code,
        status: field(row, 'status').toLowerCase(),
        started: started,
        initial: number(field(row, 'initial_brac_level')),
        finalReading: number(field(row, 'final_brac_level')),
        failureReason: nullable(field(row, 'failure_reason')),
      ));
    }

    result.sort((a, b) => b.started.compareTo(a.started)); // newest first
    return result;
  }
}

// ============================================================
// ANALYTICS 
// ============================================================

class DayStat {
  final DateTime day;
  final Map<Outcome, int> counts;
  const DayStat(this.day, this.counts);
  int count(Outcome o) => counts[o] ?? 0;
  int get total => counts.values.fold(0, (a, b) => a + b);
}

DateTime dayOf(DateTime d) {
  final local = d.toLocal();
  return DateTime(local.year, local.month, local.day);
}

class Analytics {
  final List<Ride> rides;

  late final int total = rides.length;

  late final Map<Outcome, int> byOutcome = {
    for (final o in Outcome.values)
      o: rides.where((r) => r.outcome == o).length,
  };

  int count(Outcome o) => byOutcome[o] ?? 0;

  double share(Outcome o) => total == 0 ? 0 : count(o) / total * 100;

  late final List<Ride> withInitial =
      rides.where((r) => r.initial != null).toList();

  double? averageOf(Iterable<Ride> list) {
    final values = list.map((r) => r.initial).whereType<double>().toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  late final double? avgInitial = averageOf(withInitial);

  late final double? avgBlocked =
      averageOf(rides.where((r) => r.outcome == Outcome.blocked));

  late final Ride? peakReading = withInitial.isEmpty
      ? null
      : withInitial.reduce((a, b) => a.initial! >= b.initial! ? a : b);

  late final int riders = rides.map((r) => r.rider).toSet().length;

  late final int units = rides.map((r) => r.device).toSet().length;

  late final int overLimit =
      withInitial.where((r) => r.initial! >= kAlcoholLimit).length;

  late final List<int> bracCounts = [
    for (final range in bracRanges)
      withInitial.where((r) => range.contains(r.initial!)).length,
  ];

  /// Days that have at least one ride, oldest first.
  late final List<DayStat> daily = () {
    final map = <DateTime, Map<Outcome, int>>{};
    for (final r in rides) {
      final counts = map.putIfAbsent(dayOf(r.started), () => {});
      counts[r.outcome] = (counts[r.outcome] ?? 0) + 1;
    }
    final days = map.keys.toList()..sort();
    return [for (final d in days) DayStat(d, map[d]!)];
  }();

  late final DayStat? busiestDay = daily.isEmpty
      ? null
      : daily.reduce((a, b) => b.total > a.total ? b : a);

  Analytics(this.rides);
}

// ============================================================
// FORMAT HELPERS
// ============================================================

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String brac(double? v) => v == null ? '—' : v.toStringAsFixed(3);

String pct(num v) => '${v.toStringAsFixed(1)}%';

String shortId(String v) {
  if (v.isEmpty) return '—';
  return v.length > 8 ? v.substring(0, 8) : v;
}

String shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

String longDate(DateTime d) => '${shortDate(d)}, ${d.year}';

String dateTime(DateTime? date) {
  if (date == null) return '—';
  final d = date.toLocal();
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  return '${longDate(d)} · $hour:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
}

String plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

// ============================================================
// APP
// ============================================================

class MotoLockApp extends StatelessWidget {
  const MotoLockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MotoLock',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: C.surface,
        colorScheme: ColorScheme.fromSeed(
          seedColor: C.red,
          primary: C.red,
          surface: C.white,
        ),
        fontFamily: kFont,
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: C.ink,
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(color: C.white, fontSize: 11),
        ),
      ),
      home: const AnalyticsDashboard(),
    );
  }
}

// ============================================================
// DASHBOARD
// ============================================================

class AnalyticsDashboard extends StatefulWidget {
  const AnalyticsDashboard({super.key});

  @override
  State<AnalyticsDashboard> createState() => _AnalyticsDashboardState();
}

class _AnalyticsDashboardState extends State<AnalyticsDashboard> {
  final scrollController = ScrollController();
  final searchController = TextEditingController();

  Analytics a = Analytics(const []);
  String? error;

  // Record filters — set by the search box, chips and charts.
  Outcome? outcomeFilter; // null = all
  int? bracFilter; // index into bracRanges
  DateTime? dayFilter;
  String search = '';

  // Left panel starts collapsed; the menu button expands it.
  bool sidebarOpen = false;

  // Table state. Default order is chronological (oldest first).
  int page = 0;
  int sortColumn = 2;
  bool sortAscending = true;
  static const pageSize = 10;

  @override
  void initState() {
    super.initState();
    loadBuiltInData();
  }

  @override
  void dispose() {
    scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  // ==========================================================
  // DATA LOADING
  // ==========================================================

  /// Loads the ride_history export embedded in this file.
  /// Call inside setState (or from initState).
  void loadBuiltInData() {
    try {
      applyRides(RideCsv.parse(kRideHistoryCsv));
      error = null;
    } catch (e) {
      error = e.toString();
    }
  }

  Future<void> importCsv() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final parsed = RideCsv.parse(utf8.decode(bytes, allowMalformed: true));
      if (!mounted) return;
      setState(() {
        applyRides(parsed);
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = 'Could not import CSV: $e');
    }
  }

  /// Replaces the dataset and resets every filter. Call inside setState.
  void applyRides(List<Ride> parsed) {
    a = Analytics(parsed);
    clearFilters();
  }

  void clearFilters() {
    outcomeFilter = null;
    bracFilter = null;
    dayFilter = null;
    search = '';
    page = 0;
    searchController.clear();
  }

  bool get hasFilters =>
      outcomeFilter != null ||
      bracFilter != null ||
      dayFilter != null ||
      search.isNotEmpty;

  /// Applies a filter coming from a chart. The selection is highlighted
  /// in place and the Records table shows the matching rows.
  void drillDown(void Function() apply) {
    setState(() {
      clearFilters();
      apply();
    });
  }

  // ==========================================================
  // FILTERED + SORTED RECORDS
  // ==========================================================

  List<Ride> get filtered {
    final query = search.trim().toLowerCase();
    final range = bracFilter == null ? null : bracRanges[bracFilter!];

    final rows = a.rides.where((r) {
      if (outcomeFilter != null && r.outcome != outcomeFilter) return false;
      if (dayFilter != null && dayOf(r.started) != dayFilter) return false;
      if (range != null &&
          (r.initial == null || !range.contains(r.initial!))) {
        return false;
      }
      if (query.isEmpty) return true;
      return r.riderName.toLowerCase().contains(query) ||
          r.rider.toLowerCase().contains(query) ||
          r.device.toLowerCase().contains(query) ||
          r.outcome.label.toLowerCase().contains(query) ||
          r.result.toLowerCase().contains(query) ||
          dateTime(r.started).toLowerCase().contains(query);
    }).toList();

    int compare<T extends Comparable>(T? x, T? y) {
      if (x == null && y == null) return 0;
      if (x == null) return 1; // empty values always last
      if (y == null) return -1;
      return sortAscending ? x.compareTo(y) : y.compareTo(x);
    }

    rows.sort((x, y) {
      switch (sortColumn) {
        case 0:
          return compare(x.riderName, y.riderName);
        case 1:
          return compare(x.device, y.device);
        case 3:
          return compare(x.initial, y.initial);
        case 4:
          return compare(x.finalShown, y.finalShown);
        case 5:
          return compare(x.outcome.index, y.outcome.index);
        default:
          return compare(x.started, y.started);
      }
    });
    return rows;
  }

  // ==========================================================
  // LAYOUT — same shell as the MotoLock admin web dashboard
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 1100;
      final pad = constraints.maxWidth >= 700 ? 36.0 : 16.0;

      return Scaffold(
        drawer: desktop
            ? null
            : Drawer(
                backgroundColor: C.white,
                width: 260,
                child: SafeArea(child: sidebar(closeDrawer: true)),
              ),
        body: Row(
          children: [
            if (desktop)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: sidebarOpen ? 260 : 76,
                child: sidebar(expanded: sidebarOpen),
              ),
            Expanded(
              child: Column(
                children: [
                  topbar(desktop),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(pad, 28, pad, 64),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: content(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  // ==========================================================
  // SIDEBAR 
  // ==========================================================

  Widget logo(double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.25),
      child: Image.memory(
        kLogoBytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            Icon(Icons.shield_rounded, color: C.red, size: size),
      ),
    );
  }

  Widget sidebar({bool expanded = true, bool closeDrawer = false}) {
    return Container(
      decoration: const BoxDecoration(
        color: C.white,
        border: Border(right: BorderSide(color: C.border)),
      ),
      child: ClipRect(
        child: LayoutBuilder(builder: (context, constraints) {
          // Show labels only once the panel is wide enough, so nothing
          // overflows while it animates open or closed.
          final wide = expanded && constraints.maxWidth > 200;
          return Padding(
            padding: EdgeInsets.fromLTRB(wide ? 20 : 14, 24, wide ? 20 : 14, 20),
            child: Column(
              crossAxisAlignment:
                  wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment:
                      wide ? MainAxisAlignment.start : MainAxisAlignment.center,
                  children: [
                    logo(32),
                    if (wide) ...[
                      const SizedBox(width: 8),
                      const Text.rich(
                        TextSpan(children: [
                          TextSpan(text: 'Moto', style: TextStyle(color: C.ink)),
                          TextSpan(text: 'Lock', style: TextStyle(color: C.red)),
                        ]),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(
                    'MAIN',
                    style: TextStyle(
                      fontSize: wide ? 11 : 9,
                      letterSpacing: 1,
                      color: C.gray,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Tooltip(
                  message: wide ? '' : 'Dashboard',
                  child: Material(
                    color: C.red.withAlpha(31),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        if (closeDrawer) Navigator.of(context).pop();
                        scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeInOutCubic,
                        );
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: wide ? 12 : 14,
                          vertical: 11,
                        ),
                        child: Row(
                          mainAxisSize:
                              wide ? MainAxisSize.max : MainAxisSize.min,
                          children: [
                            const Icon(Icons.dashboard_rounded,
                                size: 18, color: C.red),
                            if (wide) ...[
                              const SizedBox(width: 10),
                              const Text(
                                'Dashboard',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: C.red,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                const Divider(color: C.border, height: 32),
                Row(
                  mainAxisAlignment:
                      wide ? MainAxisAlignment.start : MainAxisAlignment.center,
                  children: [
                    Tooltip(
                      message: wide ? '' : 'MotoLock Admin',
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: C.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.group_rounded,
                            size: 16, color: C.white),
                      ),
                    ),
                    if (wide) ...[
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MotoLock Admin',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: C.ink,
                              ),
                            ),
                            Text(
                              'System Administrator',
                              style: TextStyle(fontSize: 11, color: C.gray),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ==========================================================
  // TOP BAR 
  // ==========================================================

  Widget topbar(bool desktop) {
    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: desktop ? 24 : 12),
      decoration: const BoxDecoration(
        color: C.white,
        border: Border(bottom: BorderSide(color: C.border)),
      ),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => IconButton(
              tooltip: desktop && sidebarOpen ? 'Collapse menu' : 'Expand menu',
              onPressed: () => desktop
                  ? setState(() => sidebarOpen = !sidebarOpen)
                  : Scaffold.of(ctx).openDrawer(),
              icon: const Icon(Icons.menu_rounded, color: C.ink),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: LiveClock()),
          IconButton(
            tooltip: 'Reload built-in data',
            onPressed: () => setState(loadBuiltInData),
            icon: const Icon(Icons.refresh_rounded, color: C.gray),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: importCsv,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(desktop ? 'Import CSV' : 'Import'),
            style: FilledButton.styleFrom(
              backgroundColor: C.red,
              foregroundColor: C.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // PAGE CONTENT
  // ==========================================================

  Widget content() {
    if (error != null) {
      return panel(
        title: 'Unable to load ride data',
        subtitle: 'Import a ride_history CSV export or reload the built-in data.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(error!, style: const TextStyle(color: C.darkRed)),
            const SizedBox(height: 16),
            Wrap(spacing: 12, children: [
              OutlinedButton(
                onPressed: () => setState(loadBuiltInData),
                child: const Text('Reload built-in data'),
              ),
              FilledButton(
                onPressed: importCsv,
                style: FilledButton.styleFrom(backgroundColor: C.red),
                child: const Text('Import CSV'),
              ),
            ]),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHeading('Analytics Overview'),
        const SizedBox(height: 18),
        reveal(0, kpiGrid()),
        const SizedBox(height: 44),
        sectionHeading('Charts & Trends'),
        const SizedBox(height: 18),
        reveal(1, chartSection()),
        const SizedBox(height: 44),
        sectionHeading('Ride Session Records'),
        const SizedBox(height: 18),
        reveal(2, recordsSection()),
      ],
    );
  }

  // ==========================================================
  // SHARED UI PIECES
  // ==========================================================

  Widget sectionHeading(String title) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 24,
          decoration: BoxDecoration(
            color: C.red,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: C.ink,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ],
    );
  }

  BoxDecoration card() {
    return BoxDecoration(
      color: C.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: C.border),
      boxShadow: [
        BoxShadow(
          color: C.ink.withAlpha(8),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget panel({
    required String title,
    required String subtitle,
    required Widget child,
    String? insight,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: C.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: C.gray)),
          const SizedBox(height: 22),
          child,
          if (insight != null) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: C.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline_rounded,
                      size: 16, color: C.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      insight,
                      style: const TextStyle(
                        fontSize: 12,
                        color: C.ink2,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget legendItem(String text, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 7),
            Text(text, style: const TextStyle(fontSize: 11.5, color: C.ink2)),
          ],
        ),
      ),
    );
  }

  Widget emptyChart(String text) {
    return SizedBox(
      height: 240,
      child: Center(child: Text(text, style: const TextStyle(color: C.gray))),
    );
  }

  Widget reveal(int index, Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 550 + index * 170),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: child,
        ),
      ),
    );
  }

  Widget responsiveGrid(List<Widget> items,
      {required double minItemWidth, double spacing = 18}) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = math.max(
          1,
          math.min(items.length,
              ((width + spacing) / (minItemWidth + spacing)).floor()));
      final itemWidth = (width - (columns - 1) * spacing) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final item in items) SizedBox(width: itemWidth, child: item),
        ],
      );
    });
  }

  // ==========================================================
  // KPI CARDS
  // ==========================================================

  Widget kpiGrid() {
    final peak = a.peakReading;
    final range = a.daily.isEmpty
        ? 'No ride dates'
        : '${longDate(a.daily.first.day)} – ${longDate(a.daily.last.day)}';

    final cards = [
      KpiCard(
        title: 'Total Ride Sessions',
        value: a.total.toDouble(),
        format: (v) => v.round().toString(),
        caption: range,
        icon: Icons.two_wheeler_rounded,
        featured: true,
      ),
      KpiCard(
        title: 'Unlock Success Rate',
        value: a.share(Outcome.unlocked),
        format: pct,
        caption: '${a.count(Outcome.unlocked)} of ${a.total} sessions unlocked',
        icon: Icons.lock_open_rounded,
        accent: C.green,
        progress: a.share(Outcome.unlocked) / 100,
      ),
      KpiCard(
        title: 'Blocked (Alcohol)',
        value: a.count(Outcome.blocked).toDouble(),
        format: (v) => v.round().toString(),
        caption: '${pct(a.share(Outcome.blocked))} of sessions · '
            'avg BrAC ${brac(a.avgBlocked)}',
        icon: Icons.no_drinks_rounded,
        accent: C.red,
      ),
      KpiCard(
        title: 'Face Not Recognized',
        value: a.count(Outcome.face).toDouble(),
        format: (v) => v.round().toString(),
        caption: '${pct(a.share(Outcome.face))} of sessions',
        icon: Icons.face_retouching_off_rounded,
        accent: C.slate,
      ),
      KpiCard(
        title: 'Average BrAC Reading',
        value: a.avgInitial ?? 0,
        format: (v) => a.avgInitial == null ? '—' : v.toStringAsFixed(3),
        caption: 'Highest ${brac(peak?.initial)} · '
            'limit ${brac(kAlcoholLimit)}',
        icon: Icons.air_rounded,
        accent: C.amber,
      ),
      KpiCard(
        title: 'Active Riders',
        value: a.riders.toDouble(),
        format: (v) => v.round().toString(),
        caption: '${plural(a.units, 'MotoLock unit')} · '
            '${a.riders == 0 ? '0' : (a.total / a.riders).toStringAsFixed(1)} '
            'sessions per rider',
        icon: Icons.groups_rounded,
        accent: C.darkRed,
      ),
    ];

    return responsiveGrid(cards, minItemWidth: 300);
  }

  // ==========================================================
  // CHARTS
  // ==========================================================

  Widget chartSection() {
    final outcome = panel(
      title: 'Unlock Outcomes',
      subtitle: 'Share of ride sessions by result',
      child: outcomeDonut(),
      insight: outcomeInsight(),
    );
    final distribution = panel(
      title: 'BrAC Reading Distribution',
      subtitle: 'Initial alcohol readings by range',
      child: bracBars(),
      insight: bracInsight(),
    );
    final trend = panel(
      title: 'Daily Unlock Activity',
      subtitle: 'Sessions per day by result',
      child: dailyLine(),
      insight: trendInsight(),
    );

    return Column(
      children: [
        LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < 860) {
            return Column(
              children: [outcome, const SizedBox(height: 18), distribution],
            );
          }
          // No IntrinsicHeight here: the charts use LayoutBuilder, which
          // cannot report intrinsic sizes.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: outcome),
              const SizedBox(width: 18),
              Expanded(flex: 6, child: distribution),
            ],
          );
        }),
        const SizedBox(height: 18),
        trend,
      ],
    );
  }

  // ---------- 1. DONUT: unlock outcomes ----------

  String? outcomeInsight() {
    if (a.total == 0) return null;
    final failed = a.count(Outcome.blocked) + a.count(Outcome.face);
    if (failed == 0) return 'Every session was unlocked.';
    final main = a.count(Outcome.blocked) >= a.count(Outcome.face)
        ? 'alcohol detection (${a.count(Outcome.blocked)} of $failed)'
        : 'face recognition (${a.count(Outcome.face)} of $failed)';
    return '${pct(a.share(Outcome.unlocked))} of sessions unlocked. '
        'Most failed attempts were caused by $main.';
  }

  Widget outcomeDonut() {
    if (a.total == 0) return emptyChart('No ride sessions yet');
    final entries = Outcome.values.where((o) => a.count(o) > 0).toList();

    return Column(
      children: [
        SizedBox(
          height: 230,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  startDegreeOffset: -90,
                  centerSpaceRadius: 66,
                  sectionsSpace: 2,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (event is! FlTapUpEvent) return;
                      final i = response?.touchedSection?.touchedSectionIndex;
                      if (i == null || i < 0 || i >= entries.length) return;
                      drillDown(() => outcomeFilter = entries[i]);
                    },
                  ),
                  sections: [
                    for (final o in entries)
                      PieChartSectionData(
                        value: a.count(o).toDouble(),
                        color: o.color,
                        radius: outcomeFilter == o ? 40 : 32,
                        title: a.share(o) >= 6
                            ? pct(a.share(o)).replaceFirst('.0', '')
                            : '',
                        titleStyle: const TextStyle(
                          fontFamily: kFont,
                          color: C.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                        borderSide: const BorderSide(color: C.white, width: 1),
                      ),
                  ],
                ),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOutCubic,
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pct(a.share(Outcome.unlocked)),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: C.ink,
                    ),
                  ),
                  const Text(
                    'UNLOCKED',
                    style: TextStyle(
                      fontSize: 10,
                      color: C.gray,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            for (final o in entries)
              legendItem(
                '${o.label}  ${a.count(o)}',
                o.color,
                onTap: () => drillDown(() => outcomeFilter = o),
              ),
          ],
        ),
      ],
    );
  }

  // ---------- 2. BAR: BrAC reading distribution ----------

  String? bracInsight() {
    if (a.withInitial.isEmpty) return null;
    final top = a.bracCounts.indexOf(a.bracCounts.reduce(math.max));
    return '${a.overLimit} of ${a.withInitial.length} readings '
        '(${pct(a.overLimit / a.withInitial.length * 100)}) reached the '
        '${brac(kAlcoholLimit)} limit. Most readings fall in the '
        '${bracRanges[top].label} range (${a.bracCounts[top]}).';
  }

  Widget bracBars() {
    if (a.withInitial.isEmpty) return emptyChart('No BrAC readings yet');
    final counts = a.bracCounts;
    final peak = counts.reduce(math.max);
    final step = math.max(1, (peak / 4).ceil());
    final maxY = (step * 4).toDouble();

    Color colorFor(int i) {
      final base = bracRanges[i].overLimit ? C.red : C.green;
      return bracFilter == null || bracFilter == i ? base : base.withAlpha(60);
    }

    return Column(
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final barWidth =
              math.min(42.0, constraints.maxWidth / counts.length * 0.5);
          return SizedBox(
            height: 250,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: step.toDouble(),
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: C.border, strokeWidth: 1),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => C.ink,
                    tooltipBorderRadius: BorderRadius.circular(8),
                    getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                      'BrAC ${bracRanges[group.x].label}\n',
                      const TextStyle(
                        fontFamily: kFont,
                        color: C.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                      children: [
                        TextSpan(
                          text: plural(rod.toY.toInt(), 'reading'),
                          style: const TextStyle(
                            fontFamily: kFont,
                            color: C.muted,
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  touchCallback: (event, response) {
                    if (event is! FlTapUpEvent) return;
                    final i = response?.spot?.touchedBarGroupIndex;
                    if (i == null || i < 0 || i >= counts.length) return;
                    drillDown(() => bracFilter = i);
                  },
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: step.toDouble(),
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: const TextStyle(fontSize: 10, color: C.gray),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= counts.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            bracRanges[i].label,
                            style: TextStyle(
                              fontSize: 10,
                              color: bracFilter == i ? C.red : C.gray,
                              fontWeight: bracFilter == i
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (int i = 0; i < counts.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: counts[i].toDouble(),
                          width: barWidth,
                          color: colorFor(i),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeInOutCubic,
            ),
          );
        }),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          alignment: WrapAlignment.center,
          children: [
            legendItem('Below ${brac(kAlcoholLimit)} limit', C.green),
            legendItem('At or above limit', C.red),
          ],
        ),
      ],
    );
  }

  // ---------- 3. LINE: daily activity ----------

  String? trendInsight() {
    final busiest = a.busiestDay;
    if (busiest == null) return null;
    final worst = a.daily.reduce((x, y) =>
        y.total - y.count(Outcome.unlocked) >
                x.total - x.count(Outcome.unlocked)
            ? y
            : x);
    final failed = worst.total - worst.count(Outcome.unlocked);
    final worstText = failed == 0
        ? 'No failed attempts on any day.'
        : 'Most failed attempts happened on ${shortDate(worst.day)} ($failed).';
    return 'Busiest day was ${longDate(busiest.day)} with '
        '${plural(busiest.total, 'session')}. $worstText';
  }

  Widget dailyLine() {
    final days = a.daily;
    if (days.isEmpty) return emptyChart('No ride dates yet');

    final peak = days.fold<int>(
        0,
        (m, d) => math.max(
            m, Outcome.values.map(d.count).reduce(math.max)));
    final step = math.max(1, (peak / 4).ceil());
    final labelStep = math.max(1, (days.length / 7).ceil());
    final selected =
        dayFilter == null ? -1 : days.indexWhere((d) => d.day == dayFilter);

    LineChartBarData series(Outcome o) {
      return LineChartBarData(
        spots: [
          for (int i = 0; i < days.length; i++)
            FlSpot(i.toDouble(), days[i].count(o).toDouble()),
        ],
        isCurved: true,
        preventCurveOverShooting: true,
        color: o.color,
        barWidth: 2.5,
        dotData: FlDotData(
          show: true,
          checkToShowDot: (spot, _) => spot.y > 0 || spot.x == selected,
          getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
            radius: spot.x == selected ? 6 : 3.5,
            color: o.color,
            strokeWidth: 2,
            strokeColor: C.white,
          ),
        ),
        belowBarData: BarAreaData(
          show: o == Outcome.unlocked,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [o.color.withAlpha(40), o.color.withAlpha(0)],
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 270,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: math.max(1, days.length - 1).toDouble(),
              minY: 0,
              maxY: (step * 4).toDouble(),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: step.toDouble(),
                getDrawingHorizontalLine: (_) =>
                    const FlLine(color: C.border, strokeWidth: 1),
              ),
              extraLinesData: ExtraLinesData(
                verticalLines: [
                  if (selected >= 0)
                    VerticalLine(
                      x: selected.toDouble(),
                      color: C.red.withAlpha(90),
                      strokeWidth: 1.5,
                      dashArray: [4, 4],
                    ),
                ],
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: step.toDouble(),
                    reservedSize: 30,
                    getTitlesWidget: (v, _) => Text(
                      v.toInt().toString(),
                      style: const TextStyle(fontSize: 10, color: C.gray),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 30,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      // Label every labelStep-th day, plus the last day
                      // when it is far enough from the previous label.
                      final lastDay = i == days.length - 1 &&
                          i % labelStep >= labelStep / 2;
                      if (v != i.toDouble() ||
                          i < 0 ||
                          i >= days.length ||
                          (i % labelStep != 0 && !lastDay)) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          shortDate(days[i].day),
                          style: const TextStyle(fontSize: 10, color: C.gray),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                getTouchedSpotIndicator: (bar, indexes) => [
                  for (final _ in indexes)
                    TouchedSpotIndicatorData(
                      const FlLine(color: C.border, strokeWidth: 1.5),
                      FlDotData(
                        getDotPainter: (_, _, bar, _) => FlDotCirclePainter(
                          radius: 5,
                          color: bar.color ?? C.ink,
                          strokeWidth: 2,
                          strokeColor: C.white,
                        ),
                      ),
                    ),
                ],
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => C.ink,
                  tooltipBorderRadius: BorderRadius.circular(8),
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${s.barIndex == 0 ? '${longDate(days[s.x.toInt()].day)}\n' : ''}'
                        '${Outcome.values[s.barIndex].label}: ${s.y.toInt()}',
                        TextStyle(
                          fontFamily: kFont,
                          color: s.barIndex == 0 ? C.white : C.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                touchCallback: (event, response) {
                  if (event is! FlTapUpEvent) return;
                  final spots = response?.lineBarSpots;
                  if (spots == null || spots.isEmpty) return;
                  final d = days[spots.first.x.toInt()];
                  drillDown(() => dayFilter = d.day);
                },
              ),
              // Order matches Outcome.values so barIndex maps to an outcome.
              lineBarsData: [for (final o in Outcome.values) series(o)],
            ),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOutCubic,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          alignment: WrapAlignment.center,
          children: [
            for (final o in Outcome.values) legendItem(o.label, o.color),
          ],
        ),
      ],
    );
  }

  // ==========================================================
  // RECORDS
  // ==========================================================

  Widget recordsSection() {
    final rows = filtered;
    final totalPages = rows.isEmpty ? 1 : (rows.length - 1) ~/ pageSize + 1;
    final current = page.clamp(0, totalPages - 1);
    final visible = rows.skip(current * pageSize).take(pageSize).toList();
    final first = rows.isEmpty ? 0 : current * pageSize + 1;
    final last = current * pageSize + visible.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- search + outcome filter ----
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  controller: searchController,
                  onChanged: (text) => setState(() {
                    search = text;
                    page = 0;
                  }),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search rider, device, date…',
                    hintStyle: const TextStyle(fontSize: 13, color: C.gray),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: search.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => setState(() {
                              searchController.clear();
                              search = '';
                              page = 0;
                            }),
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: C.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(
                      borderSide: const BorderSide(color: C.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: C.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: C.red, width: 1.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              outcomeChoice(null, 'All', a.total, C.ink),
              for (final o in Outcome.values)
                outcomeChoice(o, o.label, a.count(o), o.color),
              if (hasFilters)
                TextButton.icon(
                  onPressed: () => setState(clearFilters),
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Clear filters'),
                  style: TextButton.styleFrom(foregroundColor: C.red),
                ),
            ],
          ),

          // ---- filters coming from the charts ----
          if (bracFilter != null || dayFilter != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (bracFilter != null)
                  activeFilter('BrAC ${bracRanges[bracFilter!].label}',
                      () => setState(() => bracFilter = null)),
                if (dayFilter != null)
                  activeFilter(longDate(dayFilter!),
                      () => setState(() => dayFilter = null)),
              ],
            ),
          ],
          const SizedBox(height: 18),

          // ---- table ----
          if (visible.isEmpty)
            Container(
              height: 170,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: C.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off_rounded, color: C.muted, size: 34),
                  SizedBox(height: 8),
                  Text('No ride sessions match these filters.',
                      style: TextStyle(color: C.gray)),
                ],
              ),
            )
          else
            recordsTable(visible),
          const SizedBox(height: 18),

          // ---- pagination ----
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Text(
                rows.isEmpty
                    ? 'Showing 0 of 0'
                    : 'Showing $first–$last of ${rows.length} records',
                style: const TextStyle(fontSize: 12, color: C.gray),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  pageButton(
                      Icons.chevron_left_rounded,
                      current > 0
                          ? () => setState(() => page = current - 1)
                          : null),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      'Page ${current + 1} of $totalPages',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  pageButton(
                      Icons.chevron_right_rounded,
                      current < totalPages - 1
                          ? () => setState(() => page = current + 1)
                          : null),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget outcomeChoice(Outcome? value, String label, int count, Color dot) {
    final selected = outcomeFilter == value;
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() {
        outcomeFilter = value;
        page = 0;
      }),
      avatar: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: selected ? C.white : dot,
          shape: BoxShape.circle,
        ),
      ),
      label: Text('$label  $count'),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: selected ? C.white : C.ink2,
      ),
      selectedColor: C.ink,
      backgroundColor: C.white,
      side: BorderSide(color: selected ? C.ink : C.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget activeFilter(String label, VoidCallback onRemove) {
    return InputChip(
      label: Text(label),
      labelStyle: const TextStyle(
        fontSize: 12,
        color: C.darkRed,
        fontWeight: FontWeight.w500,
      ),
      backgroundColor: C.softRed,
      side: BorderSide(color: C.red.withAlpha(50)),
      deleteIconColor: C.darkRed,
      onDeleted: () => setState(() {
        onRemove();
        page = 0;
      }),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget recordsTable(List<Ride> visible) {
    const header = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: C.gray,
      letterSpacing: 0.6,
    );
    const cell = TextStyle(fontSize: 12.5, color: C.ink);

    DataColumn column(String label, {bool numeric = false}) {
      return DataColumn(
        numeric: numeric,
        label: Text(label, style: header),
        onSort: (index, ascending) => setState(() {
          sortColumn = index;
          sortAscending = ascending;
          page = 0;
        }),
      );
    }

    Widget reading(double? v, String missing) {
      final high = v != null && v >= kAlcoholLimit;
      return Text(
        v == null ? missing : brac(v),
        style: TextStyle(
          fontSize: 12.5,
          color: high ? C.red : (v == null ? C.gray : C.ink),
          fontWeight: high ? FontWeight.w600 : FontWeight.w400,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              sortColumnIndex: sortColumn,
              sortAscending: sortAscending,
              headingRowColor: WidgetStateProperty.all(C.surface),
              headingRowHeight: 46,
              dataRowMinHeight: 54,
              dataRowMaxHeight: 54,
              horizontalMargin: 18,
              columnSpacing: 28,
              dividerThickness: 0.6,
              columns: [
                column('RIDER'),
                column('DEVICE'),
                column('DATE & TIME'),
                column('INITIAL BrAC', numeric: true),
                column('FINAL BrAC', numeric: true),
                column('OUTCOME'),
              ],
              rows: [
                for (final r in visible)
                  DataRow(
                    color: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.hovered)) {
                        return C.surface;
                      }
                      return r.outcome == Outcome.unlocked
                          ? null
                          : C.softRed.withAlpha(110);
                    }),
                    cells: [
                      DataCell(Text(
                        r.riderName,
                        style: cell.copyWith(fontWeight: FontWeight.w500),
                      )),
                      DataCell(Text(r.device, style: cell)),
                      DataCell(Text(dateTime(r.started), style: cell)),
                      DataCell(reading(r.initial, 'Not recorded')),
                      DataCell(reading(r.finalShown, 'Not recorded')),
                      DataCell(Tooltip(
                        message: r.result,
                        child: outcomeBadge(r.outcome),
                      )),
                    ],
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget outcomeBadge(Outcome o) {
    final ok = o == Outcome.unlocked;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ok ? C.white : C.softRed,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ok ? C.border : C.red.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(o.icon, size: 13, color: o.color),
          const SizedBox(width: 6),
          Text(
            o.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: ok ? C.ink2 : C.darkRed,
            ),
          ),
        ],
      ),
    );
  }

  Widget pageButton(IconData icon, VoidCallback? onPressed) {
    final enabled = onPressed != null;
    return Material(
      color: enabled ? C.ink : C.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: enabled ? C.white : C.muted),
        ),
      ),
    );
  }
}

// ============================================================
// LIVE CLOCK
// ============================================================

class LiveClock extends StatefulWidget {
  const LiveClock({super.key});

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  DateTime now = DateTime.now();
  late final Timer timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    String two(int n) => n.toString().padLeft(2, '0');
    final time =
        '$hour:${two(now.minute)}:${two(now.second)} ${now.hour < 12 ? 'AM' : 'PM'}';

    return Row(
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '${_days[now.weekday - 1]}, ${longDate(now)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: C.ink,
                ),
              ),
              TextSpan(
                text: '   $time',
                style: const TextStyle(color: C.gray),
              ),
            ]),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// KPI CARD
// ============================================================

class KpiCard extends StatelessWidget {
  final String title;
  final double value;
  final String Function(double) format;
  final String caption;
  final IconData icon;
  final Color accent;
  final bool featured;
  final double? progress;

  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.format,
    required this.caption,
    required this.icon,
    this.accent = C.red,
    this.featured = false,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final fg = featured ? C.white : C.ink;
    final sub = featured ? Colors.white70 : C.gray;

    return Container(
      height: 160,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: featured
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [C.red, C.darkRed],
              )
            : null,
        color: featured ? null : C.white,
        borderRadius: BorderRadius.circular(20),
        border: featured ? null : Border.all(color: C.border),
        boxShadow: [
          BoxShadow(
            color: (featured ? C.red : C.ink).withAlpha(featured ? 55 : 8),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: featured ? C.white.withAlpha(40) : accent.withAlpha(24),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 20, color: featured ? C.white : accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: sub,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => Text(
              format(v),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                color: fg,
                letterSpacing: -0.8,
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (progress != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress!.clamp(0, 1),
                minHeight: 5,
                color: accent,
                backgroundColor: C.red.withAlpha(40),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: sub),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DATABASE
// ============================================================

const Map<String, String> kRiderNames = {
  '007f347f-3305-5316-b7c2-74ad965b73b5': 'Joeseht Basilio',
  'c8307178-1baa-5dcb-a98b-52bca632ec1c': 'Nathaniel Baculi',
  '7d0c47ab-8f3d-507b-9fee-4915c646aae6': 'Rose Marie Roxas',
  '75921ea1-7dfb-5db3-b03a-8733e40134ab': 'Jenna Diaz',
  '16431207-211f-5d42-a0f0-470d8fb58543': 'Jefferson Attractivo',
  '39004512-17d0-5082-8238-c5599c7c6b61': 'Jeric Rotoni',
  'cbb02af8-dd60-56bc-b609-d4fded04b73c': 'Alexis Olaybal',
  '326745a9': 'Mark Anthony Reyes',
  'd7ecdb22': 'Kristine Joy Santos',
};

/// MotoLock logo (96x96 PNG).
const String kLogoPng =
    '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';

/// public.ride_history export (Supabase).
const String kRideHistoryCsv = r'''
id,rider_id,device_id,start_time,end_time,initial_brac_level,final_brac_level,status
19f78aa1-1d2e-4ce5-bea8-dc84137ea52f,d7ecdb22,3668c57a,2026-10-07 09:25:51+00,null,0.000,null,ongoing
ce727113-0176-48a0-921d-405659aac73f,326745a9,null,2026-10-07 06:43:27+00,null,0.001,null,ongoing
63276738-4210-4401-9eae-b24151a45328,326745a9,null,2026-09-28 20:24:47+00,null,0.000,null,ongoing
aa790b45-af2c-4af5-9cbc-c9e7f2e4ca8d,326745a9,null,2026-09-28 20:24:14+00,null,0.000,null,ongoing
99b5a7cb-ecc2-4d23-b271-83f81dc21e94,326745a9,null,2026-09-28 20:21:34+00,null,0.000,null,ongoing
fad5c034-da73-4416-b910-4717b36cd5c2,326745a9,null,2026-09-28 20:17:50+00,null,0.053,null,failed_brac
eb0f4835-8f36-436b-85f5-0e81f9f6fba3,326745a9,null,2026-09-28 20:16:45+00,null,0.000,null,ongoing
60471be9-65ed-4aeb-ae34-a46f444b92ed,326745a9,null,2026-09-28 19:57:03+00,null,0.000,null,ongoing
8786728e-b572-467b-bd66-e9170baab278,326745a9,null,2026-09-28 19:55:14+00,null,0.000,null,ongoing
1305432a-6118-4531-a208-f9c58c00418d,326745a9,null,2026-09-28 19:53:39+00,null,0.000,null,ongoing
56098a2f-d27c-4b81-914f-53c6e1b3c895,326745a9,null,2026-09-28 19:07:10+00,null,0.013,null,ongoing
c042d7d3-ceeb-4b0e-a978-919cf2147deb,326745a9,null,2026-09-28 19:03:22+00,null,0.224,null,failed_brac
a203eed9-34fa-401c-8304-4b2e399c45d6,326745a9,null,2026-09-28 18:23:59+00,null,0.180,null,failed_brac
76295aac-c9e2-4c2d-9d5e-13b351b408ae,326745a9,null,2026-09-28 18:10:56+00,null,0.000,null,ongoing
95aa7e05-e138-4761-b4a9-c65d65d87ca5,326745a9,null,2026-09-28 17:41:02+00,null,0.000,null,ongoing
0bf9f218-5bbe-5813-8802-795ecbedbed4,cbb02af8,null,2026-09-23 09:17:00+00,null,0.000,null,ongoing
12f4b863-2f44-55d8-ade7-b7400f8d50be,39004512,null,2026-09-23 09:16:00+00,null,0.000,null,ongoing
12bbbbe4-8d4b-5875-9278-a908172999f2,16431207,74d1cc98,2026-09-23 09:15:00+00,null,0.000,null,ongoing
01103545-f7eb-5127-9d5a-d433cb0076f3,75921ea1,efee6efc,2026-09-23 09:14:00+00,null,0.000,null,ongoing
8477c81b-5bf2-5cd4-9ac7-b1dd68bd795c,7d0c47ab,28125a54,2026-09-23 09:13:00+00,null,0.000,null,ongoing
efcf21d9-9b8a-5adb-9cca-a02967dca016,c8307178,ee8c63e2,2026-09-23 09:12:00+00,null,0.000,null,ongoing
598f83de-7131-53e8-9f37-17332575f6fe,007f347f,5ab0effe,2026-09-23 09:11:00+00,null,0.000,null,ongoing
01b46040-01a2-56ca-8847-18aa99085af4,cbb02af8,60f300c8,2026-09-22 06:00:00+00,null,0.000,null,passed
77d0aa67-6ee9-5ca0-a661-0ffc6ba06020,39004512,15a143a0,2026-09-22 05:00:00+00,null,0.000,null,passed
84fce36f-2ce3-5ec8-9137-c66b784bb9bc,16431207,74d1cc98,2026-09-22 04:00:00+00,null,0.000,null,passed
fc538076-0205-5ac6-80bb-2e6d3654d1fd,75921ea1,efee6efc,2026-09-22 03:00:00+00,null,0.000,null,passed
ad51a19e-2b32-5930-8f49-ce0d48720022,7d0c47ab,28125a54,2026-09-22 02:00:00+00,null,0.000,null,passed
ea7cfbac-f0f1-574d-a423-521d08a0a4f4,c8307178,ee8c63e2,2026-09-22 01:00:00+00,null,0.000,null,passed
bdb13673-802f-5c01-9e81-5ac0af73b73c,007f347f,5ab0effe,2026-09-22 00:00:00+00,null,0.000,null,passed
d8208ae2-48bb-5af0-af01-b303dbf5ade4,cbb02af8,60f300c8,2026-09-18 06:00:00+00,null,0.000,null,failed_face
fdd00013-b4ee-54f3-8e27-fedb598b70bf,39004512,15a143a0,2026-09-18 05:00:00+00,null,0.000,null,failed_face
d986989a-c748-5b5f-809b-8512e0752174,16431207,74d1cc98,2026-09-18 04:00:00+00,null,0.000,null,failed_face
c57ef480-67f2-54ec-a0ac-0199c2e24884,75921ea1,efee6efc,2026-09-18 03:00:00+00,null,0.000,null,failed_face
22cb7d75-0f3c-5865-8295-94dde1b6f128,7d0c47ab,28125a54,2026-09-18 02:00:00+00,null,0.000,null,failed_face
07eec919-5118-572d-9179-45865d6b398b,c8307178,ee8c63e2,2026-09-18 01:00:00+00,null,0.000,null,failed_face
962fa3db-6fde-53e0-af9d-0f0aed2d083e,007f347f,5ab0effe,2026-09-18 00:00:00+00,null,0.000,null,failed_face
524e02eb-7e73-5143-a3f0-0db5e1e39b08,cbb02af8,60f300c8,2026-09-17 06:00:00+00,null,0.050,null,failed_brac
c3eca3fe-5731-558a-9372-5ec99e216a36,39004512,15a143a0,2026-09-17 05:00:00+00,null,0.080,null,failed_brac
79ccc403-f18a-52c5-a440-fa3ed71f51cf,16431207,74d1cc98,2026-09-17 04:00:00+00,null,0.050,null,failed_brac
c55d2290-dba0-54ea-9e75-bbf1eefb815e,75921ea1,efee6efc,2026-09-17 03:00:00+00,null,0.080,null,failed_brac
e4543eab-a32f-5f12-bf23-cf90e17cefa2,7d0c47ab,28125a54,2026-09-17 02:00:00+00,null,0.050,null,failed_brac
51529080-0c6c-5b9c-ba33-f05eca718582,c8307178,ee8c63e2,2026-09-17 01:00:00+00,null,0.080,null,failed_brac
541ca3a0-f77e-5fb6-a721-1eb60887b454,007f347f,5ab0effe,2026-09-17 00:00:00+00,null,0.050,null,failed_brac
cc1b239b-c2f4-519e-a0ca-024e8d45643a,cbb02af8,60f300c8,2026-09-16 06:00:00+00,2026-09-16 06:44:00+00,0.010,0.005,completed
2dd187b1-8e91-51eb-85c6-15d780c0d0ac,39004512,15a143a0,2026-09-16 05:00:00+00,2026-09-16 05:41:00+00,0.010,0.005,completed
5fdcfbb1-7f52-5a8a-aa80-9b820229dd5a,16431207,74d1cc98,2026-09-16 04:00:00+00,2026-09-16 04:38:00+00,0.010,0.005,completed
bd23e049-d008-55be-b50c-24388af7c754,75921ea1,efee6efc,2026-09-16 03:00:00+00,2026-09-16 03:35:00+00,0.010,0.005,completed
37122691-fcf7-5397-82df-9877a15a698c,7d0c47ab,28125a54,2026-09-16 02:00:00+00,2026-09-16 02:32:00+00,0.010,0.005,completed
359240d5-dec4-537a-875a-18d752f00a2d,c8307178,ee8c63e2,2026-09-16 01:00:00+00,2026-09-16 01:29:00+00,0.010,0.005,completed
29685a52-e5e8-5f63-a9e5-29044c98bcd5,007f347f,5ab0effe,2026-09-16 00:00:00+00,2026-09-16 00:26:00+00,0.010,0.005,completed
49e65d28-c49a-5a1a-b45d-1cc478ba5d2e,cbb02af8,60f300c8,2026-09-13 06:00:00+00,2026-09-13 06:43:00+00,0.000,0.000,completed
2324fcc3-f0fd-533b-b2ab-03d33b254ccb,39004512,15a143a0,2026-09-13 05:00:00+00,2026-09-13 05:40:00+00,0.000,0.000,completed
7bfae710-d452-5388-bc85-54d9ea9b86b9,16431207,74d1cc98,2026-09-13 04:00:00+00,2026-09-13 04:37:00+00,0.000,0.000,completed
a422721e-791a-5965-b3cd-ab3941746919,75921ea1,efee6efc,2026-09-13 03:00:00+00,2026-09-13 03:34:00+00,0.000,0.000,completed
4a093c0f-f836-5fb8-b3c0-a4c7c4ddef2b,7d0c47ab,28125a54,2026-09-13 02:00:00+00,2026-09-13 02:31:00+00,0.000,0.000,completed
34112425-118b-5b56-b472-8d2ea9cf8378,c8307178,ee8c63e2,2026-09-13 01:00:00+00,2026-09-13 01:28:00+00,0.000,0.000,completed
97ce7e96-0a3d-5862-a462-4eb9833f728f,007f347f,5ab0effe,2026-09-13 00:00:00+00,2026-09-13 00:25:00+00,0.000,0.000,completed
e228f887-fcc0-599f-aeeb-b18768b1e9fc,cbb02af8,60f300c8,2026-09-10 06:00:00+00,2026-09-10 06:42:00+00,0.049,0.044,completed
13cfd662-f728-50e6-b192-1aa6eff91c2f,39004512,15a143a0,2026-09-10 05:00:00+00,2026-09-10 05:39:00+00,0.049,0.044,completed
9373acec-e410-58e2-b996-b145eb93e1a7,16431207,74d1cc98,2026-09-10 04:00:00+00,2026-09-10 04:36:00+00,0.049,0.044,completed
ff6864a4-bc06-5d11-b5bd-2addadbc5492,75921ea1,efee6efc,2026-09-10 03:00:00+00,2026-09-10 03:33:00+00,0.049,0.044,completed
bfcc8f1f-4c37-55c8-9476-f9c701376628,7d0c47ab,28125a54,2026-09-10 02:00:00+00,2026-09-10 02:30:00+00,0.049,0.044,completed
2c9d515a-dd47-5df8-a8ba-d466a9a21577,c8307178,ee8c63e2,2026-09-10 01:00:00+00,2026-09-10 01:27:00+00,0.049,0.044,completed
c6b9fbb7-3ea3-5ebf-970c-6ae5461e9de7,007f347f,5ab0effe,2026-09-10 00:00:00+00,2026-09-10 00:24:00+00,0.049,0.044,completed
14b42d8c-eb93-519c-8a3a-3c0d7b6b645d,cbb02af8,60f300c8,2026-09-07 06:00:00+00,2026-09-07 06:41:00+00,0.020,0.015,completed
914e82fe-fd12-59d0-ad23-9e8c41873f7f,39004512,15a143a0,2026-09-07 05:00:00+00,2026-09-07 05:38:00+00,0.020,0.015,completed
9c1340d6-0318-575c-8f74-28fab113140d,16431207,74d1cc98,2026-09-07 04:00:00+00,2026-09-07 04:35:00+00,0.020,0.015,completed
de3489ec-411f-504b-9af2-a43be7717aa0,75921ea1,efee6efc,2026-09-07 03:00:00+00,2026-09-07 03:32:00+00,0.020,0.015,completed
bae733cc-81b8-5846-8ea3-9538edafe611,7d0c47ab,28125a54,2026-09-07 02:00:00+00,2026-09-07 02:29:00+00,0.020,0.015,completed
fb8f7a5b-fcce-545d-b439-754b6796b6f6,c8307178,ee8c63e2,2026-09-07 01:00:00+00,2026-09-07 01:26:00+00,0.020,0.015,completed
3318f436-d0bc-5103-aec8-8f581b445cc3,007f347f,5ab0effe,2026-09-07 00:00:00+00,2026-09-07 00:23:00+00,0.020,0.015,completed
447face9-aebf-5592-bd61-a4450a18458d,cbb02af8,60f300c8,2026-09-04 06:00:00+00,2026-09-04 06:40:00+00,0.010,0.005,completed
1e1362f0-3c46-596b-9592-305f9f2d14c6,39004512,15a143a0,2026-09-04 05:00:00+00,2026-09-04 05:37:00+00,0.010,0.005,completed
c6f30244-4dbf-5b18-a7b0-2bcbc694ddaf,16431207,74d1cc98,2026-09-04 04:00:00+00,2026-09-04 04:34:00+00,0.010,0.005,completed
1409ae5d-9652-530a-a2ca-8bd78a88a35f,75921ea1,efee6efc,2026-09-04 03:00:00+00,2026-09-04 03:31:00+00,0.010,0.005,completed
b2475bcc-9e81-5b16-a07a-1e80a428351d,7d0c47ab,28125a54,2026-09-04 02:00:00+00,2026-09-04 02:28:00+00,0.010,0.005,completed
945e4c74-d30a-5cfd-9b05-86cd2cf661f5,c8307178,ee8c63e2,2026-09-04 01:00:00+00,2026-09-04 01:25:00+00,0.010,0.005,completed
98acc642-7487-5c35-8efe-2f72cbe95e13,007f347f,5ab0effe,2026-09-04 00:00:00+00,2026-09-04 00:22:00+00,0.010,0.005,completed
acdaa00f-d49f-5a0f-a31b-8b6b2d9c1957,cbb02af8,60f300c8,2026-09-01 06:00:00+00,2026-09-01 06:39:00+00,0.000,0.000,completed
5a9f59e0-0c0d-5cd5-918c-68fc6a0db653,39004512,15a143a0,2026-09-01 05:00:00+00,2026-09-01 05:36:00+00,0.000,0.000,completed
2f5e2303-a5ab-581f-821c-af4709d8b42c,16431207,74d1cc98,2026-09-01 04:00:00+00,2026-09-01 04:33:00+00,0.000,0.000,completed
140c4224-6906-52f9-80e9-36d72e681de7,75921ea1,efee6efc,2026-09-01 03:00:00+00,2026-09-01 03:30:00+00,0.000,0.000,completed
9778d6eb-c72f-5dce-b7fe-fa28d3ef86ac,7d0c47ab,28125a54,2026-09-01 02:00:00+00,2026-09-01 02:27:00+00,0.000,0.000,completed
9f883548-1ed5-5b9d-89df-45806ee786e8,c8307178,ee8c63e2,2026-09-01 01:00:00+00,2026-09-01 01:24:00+00,0.000,0.000,completed
27cf606a-a8f1-5f23-8b33-6c19bd66a99b,007f347f,5ab0effe,2026-09-01 00:00:00+00,2026-09-01 00:21:00+00,0.000,0.000,completed
''';
