
import 'dart:convert';
import 'dart:math' as math;
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ============================================================
// MOTOLOCK ANALYTICS — CSV VERSION
// Compatible with csv 8.0.0, file_picker 13.1.0,
// and fl_chart 1.2.0
// ============================================================
void main() => runApp(const MotoLockApp());
// ============================================================
// COLORS
// ============================================================
class C {
  static const red = Color(0xFFD90429);
  static const darkRed = Color(0xFF9E0320);
  static const softRed = Color(0xFFFDECEF);
  static const black = Color(0xFF111111);
  static const gray = Color(0xFF777777);
  static const white = Colors.white;
  static const background = Color(0xFFF6F4F2);
  static const border = Color(0xFFEAE7E4);
}
// ============================================================
// RIDE RECORD MODEL
// ============================================================
class Ride {
  final String id;
  final String rider;
  final String device;
  final String status;
  final DateTime started;
  final DateTime? ended;
  final double? initial;
  final double? finalReading;
  const Ride({
    required this.id,
    required this.rider,
    required this.device,
    required this.status,
    required this.started,
    required this.ended,
    required this.initial,
    required this.finalReading,
  });
}
// ============================================================
// CSV PARSER — FIXED FOR CSV 8.0.0
// ============================================================
class RideCsv {
  static List<Ride> parse(String text) {
    final List<List<dynamic>> rows = csv.decode(
      text.replaceFirst('\uFEFF', ''),
    );
    if (rows.isEmpty) {
      throw const FormatException('CSV is empty.');
    }
    final headers = rows.first
        .map(
          (value) =>
              value.toString().trim().toLowerCase(),
        )
        .toList();
    const requiredColumns = [
      'id',
      'rider_id',
      'device_id',
      'start_time',
      'end_time',
      'initial_brac_level',
      'final_brac_level',
      'status',
    ];
    for (final name in requiredColumns) {
      if (!headers.contains(name)) {
        throw FormatException(
          'Missing CSV column: $name',
        );
      }
    }
    String field(
      List<dynamic> row,
      String name,
    ) {
      final index = headers.indexOf(name);
      if (index >= row.length) return '';
      return row[index].toString().trim();
    }
    String? nullable(String value) {
      if (value.isEmpty ||
          value.toLowerCase() == 'null') {
        return null;
      }
      return value;
    }
    double? brac(String value) {
      final cleaned = nullable(value);
      if (cleaned == null) return null;
      return double.tryParse(cleaned);
    }

DateTime? time(String value) {
  final cleaned = nullable(value);
  if (cleaned == null) return null;
  // Convert the space between date and time to T.
  String formatted = cleaned.replaceFirst(' ', 'T');
  // Convert timezone +00 into +00:00.
  // Also supports other offsets such as +08 or -05.
  formatted = formatted.replaceFirstMapped(
    RegExp(r'([+-]\d{2})$'),
    (match) => '${match.group(1)}:00',
  );
  // Parse the date and normalize it to UTC.
  return DateTime.tryParse(formatted)?.toUtc();
}

    final result = <Ride>[];
    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every(
        (cell) => cell.toString().trim().isEmpty,
      )) {
        continue;
      }
      final started = time(
        field(row, 'start_time'),
      );
      if (started == null) {
        throw FormatException(
          'Invalid start_time in CSV row ${i + 1}.',
        );
      }
      result.add(
        Ride(
          id: field(row, 'id'),
          rider: field(row, 'rider_id'),
          device: nullable(
                field(row, 'device_id'),
              ) ??
              '',
          status: field(
            row,
            'status',
          ).toLowerCase(),
          started: started,
          ended: time(
            field(row, 'end_time'),
          ),
          initial: brac(
            field(row, 'initial_brac_level'),
          ),
          finalReading: brac(
            field(row, 'final_brac_level'),
          ),
        ),
      );
    }
    result.sort(
      (a, b) => b.started.compareTo(a.started),
    );
    return result;
  }
}
// ============================================================
// APP
// ============================================================
class MotoLockApp extends StatelessWidget {
  const MotoLockApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MotoLock Analytics',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: C.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: C.red,
        ),
      ),
      home: const AnalyticsDashboard(),
    );
  }
}
// ============================================================
// ANALYTICS DASHBOARD
// ============================================================
class AnalyticsDashboard extends StatefulWidget {
  const AnalyticsDashboard({super.key});
  @override
  State<AnalyticsDashboard> createState() =>
      _AnalyticsDashboardState();
}
class _AnalyticsDashboardState
    extends State<AnalyticsDashboard> {
  final overviewKey = GlobalKey();
  final chartsKey = GlobalKey();
  final recordsKey = GlobalKey();
  final searchController = TextEditingController();
  List<Ride> rides = [];
  bool loading = true;
  String? error;
  String sourceName = 'assets/ride_history.csv';
  String menu = 'Overview';
  String filter = 'all';
  bool filterOpen = false;
  String search = '';
  int page = 0;
  static const pageSize = 10;
  @override
  void initState() {
    super.initState();
    loadBundledCsv();
  }
  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
  // ==========================================================
  // LOAD CSV FROM ASSETS
  // ==========================================================
  Future<void> loadBundledCsv() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final text = await rootBundle.loadString(
        'assets/ride_history.csv',
      );
      final parsed = RideCsv.parse(text);
      if (!mounted) return;
      setState(() {
        rides = parsed;
        sourceName = 'assets/ride_history.csv';
        filter = 'all';
        search = '';
        page = 0;
        searchController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }
  // ==========================================================
  // IMPORT CSV — FIXED FOR FILE_PICKER 13.1.0
  // ==========================================================
  Future<void> importCsv() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final parsed = RideCsv.parse(
        utf8.decode(bytes),
      );
      if (!mounted) return;
      setState(() {
        rides = parsed;
        sourceName = file.name;
        error = null;
        loading = false;
        filter = 'all';
        search = '';
        page = 0;
        searchController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${parsed.length} ride sessions.',
          ),
          backgroundColor: C.black,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not import CSV: $e',
          ),
          backgroundColor: C.red,
        ),
      );
    }
  }
  // ==========================================================
  // KPI CALCULATIONS
  // ==========================================================
  int count(String status) {
    return rides.where(
      (r) => r.status == status,
    ).length;
  }
  Map<String, int> get statuses {
    final map = <String, int>{};
    for (final ride in rides) {
      map[ride.status] =
          (map[ride.status] ?? 0) + 1;
    }
    return map;
  }
  // ==========================================================
  // BrAC CALCULATIONS
  // ==========================================================
  List<double> readings(bool initial) {
    return rides
        .map(
          (r) => initial
              ? r.initial
              : r.finalReading,
        )
        .whereType<double>()
        .toList();
  }
  double? average(bool initial) {
    final values = readings(initial);
    if (values.isEmpty) return null;
    final total = values.reduce(
      (a, b) => a + b,
    );
    return total / values.length;
  }
  // ==========================================================
  // DAILY ACTIVITY
  // ==========================================================
  List<MapEntry<DateTime, int>> get dailyCounts {
    if (rides.isEmpty) return [];
    DateTime day(DateTime d) {
      return DateTime.utc(
        d.year,
        d.month,
        d.day,
      );
    }
    final first = day(rides.last.started);
    final last = day(rides.first.started);
    final counts = <DateTime, int>{};
    for (final ride in rides) {
      final date = day(ride.started);
      counts[date] = (counts[date] ?? 0) + 1;
    }
    final totalDays =
        last.difference(first).inDays + 1;
    return List.generate(totalDays, (i) {
      final date = first.add(
        Duration(days: i),
      );
      return MapEntry(
        date,
        counts[date] ?? 0,
      );
    });
  }
  // ==========================================================
  // SEARCH AND FILTER
  // ==========================================================
  List<Ride> get filtered {
    final query = search.trim().toLowerCase();
    return rides.where((ride) {
      final matchesStatus =
          filter == 'all' ||
          ride.status == filter;
      final matchesSearch =
          ride.id.toLowerCase().contains(query) ||
          ride.rider.toLowerCase().contains(query) ||
          ride.device.toLowerCase().contains(query) ||
          ride.status.toLowerCase().contains(query);
      return matchesStatus && matchesSearch;
    }).toList();
  }
  // ==========================================================
  // TEXT HELPERS
  // ==========================================================
  String statusName(String status) {
    return status
        .split('_')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}'
                    '${word.substring(1)}',
        )
        .join(' ');
  }
  String bracText(double? value) {
    if (value == null) return '—';
    return value.toStringAsFixed(3);
  }
  String shortId(String value) {
    if (value.isEmpty) return '—';
    if (value.length > 12) {
      return '${value.substring(0, 8)}…';
    }
    return value;
  }
  String shortDate(DateTime date) {
    return '${date.month}/${date.day}';
  }
  String dateText(DateTime? date) {
    if (date == null) return '—';
    final utc = date.toUtc();
    String pad(int number) {
      return number.toString().padLeft(2, '0');
    }
    return '${utc.month}/${utc.day}/${utc.year} '
        '${pad(utc.hour)}:${pad(utc.minute)} UTC';
  }
  // ==========================================================
  // NAVIGATION
  // ==========================================================
  void jump(
    String title,
    GlobalKey key, {
    bool drawer = false,
  }) {
    if (drawer) {
      Navigator.of(context).pop();
    }
    setState(() {
      menu = title;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(
          milliseconds: 500,
        ),
        curve: Curves.easeInOutCubic,
        alignment: 0.03,
      );
    });
  }
  // ==========================================================
  // MAIN LAYOUT
  // ==========================================================
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop =
            constraints.maxWidth >= 1050;
        return Scaffold(
          drawer: desktop
              ? null
              : Drawer(
                  child: SafeArea(
                    child: sidebar(true),
                  ),
                ),
          body: Row(
            children: [
              if (desktop)
                SizedBox(
                  width: 225,
                  child: sidebar(false),
                ),
              Expanded(
                child: Column(
                  children: [
                    topbar(desktop),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          desktop ? 38 : 18,
                          38,
                          desktop ? 38 : 18,
                          70,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(
                              maxWidth: 1150,
                            ),
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
      },
    );
  }
  // ==========================================================
  // SIDEBAR
  // ==========================================================
  Widget sidebar(bool drawer) {
    return Container(
      color: C.white,
      padding: const EdgeInsets.fromLTRB(
        18,
        28,
        18,
        22,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                backgroundColor: C.red,
                child: Icon(
                  Icons.shield_rounded,
                  color: C.white,
                ),
              ),
              SizedBox(width: 12),
              Text(
                'MotoLock',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 55),
          const Padding(
            padding: EdgeInsets.only(
              left: 14,
              bottom: 15,
            ),
            child: Text(
              'ANALYTICS',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                color: C.gray,
              ),
            ),
          ),
          nav(
            'Overview',
            Icons.grid_view_rounded,
            overviewKey,
            drawer,
          ),
          nav(
            'Charts',
            Icons.bar_chart_rounded,
            chartsKey,
            drawer,
          ),
          nav(
            'Records',
            Icons.table_rows_rounded,
            recordsKey,
            drawer,
          ),
          const Spacer(),
          const Divider(
            color: C.border,
          ),
          const SizedBox(height: 10),
          const Text(
            'MOTOLOCK · ANALYTICS',
            style: TextStyle(
              color: C.gray,
              letterSpacing: 1,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
  Widget nav(String title, IconData icon, GlobalKey key, bool drawer) {
    final selected = menu == title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => jump(title, key, drawer: drawer),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 270),
            curve: Curves.easeOutCubic,
            height: 52,
            decoration: BoxDecoration(
              color: selected ? C.softRed : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 270),
                width: 3,
                height: selected ? 26 : 8,
                decoration: BoxDecoration(
                  color: selected ? C.red : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 14),
              Icon(icon, size: 20, color: selected ? C.red : C.gray),
              const SizedBox(width: 13),
              Text(title, style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? C.red : C.black,
              )),
            ]),
          ),
        ),
      ),
    );
  }
  Widget topbar(bool desktop) {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: C.white,
        border: const Border(bottom: BorderSide(color: C.border)),
        boxShadow: [BoxShadow(
          color: C.black.withAlpha(7), blurRadius: 12,
          offset: const Offset(0, 3),
        )],
      ),
      child: Row(children: [
        if (!desktop)
          Builder(builder: (ctx) => IconButton(
            onPressed: () => Scaffold.of(ctx).openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          )),
        const Expanded(child: Text('Analytics / Overview',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
        HoverCard(child: FilledButton.icon(
          onPressed: importCsv,
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: Text(desktop ? 'Import CSV' : 'Import'),
          style: FilledButton.styleFrom(
            backgroundColor: C.red,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        )),
        const SizedBox(width: 14),
        const CircleAvatar(
          backgroundColor: C.softRed,
          child: Icon(Icons.person_outline_rounded, color: C.red),
        ),
      ]),
    );
  }
  Widget content() {
    if (loading) {
      return const SizedBox(
        height: 400,
        child: Center(
          child: CircularProgressIndicator(
            color: C.red,
          ),
        ),
      );
    }
    if (error != null) {
      return panel(
        'Unable to load CSV',
        'Check assets/ride_history.csv or import a CSV file.',
        Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            SelectableText(error!),
            const SizedBox(height: 15),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  onPressed: loadBundledCsv,
                  child: const Text('Try Again'),
                ),
                FilledButton(
                  onPressed: importCsv,
                  child: const Text('Import CSV'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // OVERVIEW
        Column(
          key: overviewKey,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Analytics Overview',
              style: TextStyle(
                fontSize: 30,
                letterSpacing: -0.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              'MotoLock ride activity, alcohol readings, '
              'and verification results.',
              style: TextStyle(
                color: C.gray,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            badge(
              'CSV DATA · $sourceName',
            ),
          ],
        ),
        const SizedBox(height: 36),
        // KPI CARDS
        reveal(
          0,
          kpiGrid(),
        ),
        const SizedBox(height: 55),
        // CHARTS
        Column(
          key: chartsKey,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            heading(
              'Performance & Trends',
              'Three charts calculated from your actual ride records.',
            ),
            const SizedBox(height: 25),
            reveal(
              1,
              chartSection(),
            ),
          ],
        ),
        const SizedBox(height: 55),
        // RECORDS — LAST SECTION
        Column(
          key: recordsKey,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            heading(
              'Ride Session Records',
              'Search and review the same records '
              'used by the analytics.',
            ),
            const SizedBox(height: 25),
            reveal(
              2,
              recordsSection(),
            ),
          ],
        ),
      ],
    );
  }
  // ==========================================================
  // UI COMPONENTS
  // ==========================================================
  Widget heading(
    String title,
    String subtitle,
  ) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(
            color: C.gray,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
  Widget badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: C.softRed,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          color: C.darkRed,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
  Widget panel(String title, String subtitle, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(27),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: C.border.withAlpha(180)),
        boxShadow: [
          BoxShadow(color: C.black.withAlpha(9), blurRadius: 24,
            offset: const Offset(0, 9)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 4, height: 26, decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [C.red, C.darkRed]),
            borderRadius: BorderRadius.circular(4),
          )),
          const SizedBox(width: 11),
          Expanded(child: Text(title, style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: C.black))),
        ]),
        const SizedBox(height: 9),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: C.gray)),
        const SizedBox(height: 29),
        child,
      ]),
    );
  }
  Widget reveal(
    int index,
    Widget child,
  ) {
    return TweenAnimationBuilder<double>(
      tween: Tween(
        begin: 0,
        end: 1,
      ),
      duration: Duration(
        milliseconds: 600 + index * 180,
      ),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(
              0,
              22 * (1 - value),
            ),
            child: child,
          ),
        );
      },
    );
  }
  // ==========================================================
  // KPI GRID
  // ==========================================================
  Widget kpiGrid() {
    final items = [
      (
        'Total Ride Sessions',
        rides.length,
        Icons.two_wheeler_rounded,
      ),
      (
        'Completed Rides',
        count('completed'),
        Icons.check_circle_outline,
      ),
      (
        'Failed BrAC',
        count('failed_brac'),
        Icons.warning_amber_rounded,
      ),
      (
        'Failed Face Checks',
        count('failed_face'),
        Icons.gpp_bad_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 850
            ? 4
            : width >= 470
                ? 2
                : 1;
        const spacing = 19.0;
        final itemWidth =
            (width - (columns - 1) * spacing) /
                columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (int i = 0; i < items.length; i++)
              SizedBox(
                width: itemWidth,
                child: kpi(
                  items[i].$1,
                  items[i].$2,
                  items[i].$3,
                  featured: i == 0,
                ),
              ),
          ],
        );
      },
    );
  }
  // ==========================================================
  // KPI CARD
  // ==========================================================
  Widget kpi(
    String title,
    int value,
    IconData icon, {
    bool featured = false,
  }) {
    return HoverCard(
      child: Container(
        height: 168,
        padding: const EdgeInsets.all(21),
        decoration: BoxDecoration(
          gradient: featured
              ? const LinearGradient(
                  colors: [
                    C.red,
                    C.darkRed,
                  ],
                )
              : null,
          color: featured ? null : C.white,
          borderRadius: BorderRadius.circular(20),
          border: featured
              ? null
              : Border.all(color: C.border.withAlpha(160)),
          boxShadow: [BoxShadow(
            color: (featured ? C.red : C.black).withAlpha(featured ? 32 : 10),
            blurRadius: 22, offset: const Offset(0, 9),
          )],
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: featured
                          ? C.white
                          : C.gray,
                    ),
                  ),
                ),
                Icon(
                  icon,
                  size: 22,
                  color: featured
                      ? C.white
                      : C.red,
                ),
              ],
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(
                begin: 0,
                end: value.toDouble(),
              ),
              duration: const Duration(
                milliseconds: 1100,
              ),
              curve: Curves.easeOutCubic,
              builder: (context, current, child) {
                return Text(
                  '${current.round()}',
                  style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    color: featured
                        ? C.white
                        : C.black,
                  ),
                );
              },
            ),
            Text(
              'Calculated from CSV',
              style: TextStyle(
                fontSize: 11,
                color: featured
                    ? Colors.white70
                    : C.gray,
              ),
            ),
          ],
        ),
      ),
    );
  }
  // ==========================================================
  // CHART LAYOUT
  // ==========================================================
  Widget chartSection() {
    final pie = panel(
      'Ride Status Distribution',
      'Share of sessions by recorded status',
      pieChart(),
    );
    final bar = panel(
      'Alcohol Reading Analysis',
      'Average initial vs. final BrAC',
      barChart(),
    );
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 790) {
              return Column(
                children: [
                  pie,
                  const SizedBox(height: 22),
                  bar,
                ],
              );
            }
            return Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: pie,
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: bar,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        panel(
          'Ride Activity Over Time',
          'Number of ride sessions per day (UTC)',
          lineChart(),
        ),
      ],
    );
  }
  Widget legend(
    String text,
    Color color,
  ) {
    return Row(
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
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            color: C.gray,
          ),
        ),
      ],
    );
  }
  Widget chartEmpty(String text) {
    return SizedBox(
      height: 255,
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: C.gray,
          ),
        ),
      ),
    );
  }
  // ==========================================================
  // PIE CHART — RIDE STATUS DISTRIBUTION
  // ==========================================================
  Widget pieChart() {
    if (rides.isEmpty) {
      return chartEmpty('No rides in CSV');
    }
    final entries = statuses.entries.toList()
      ..sort(
        (a, b) => b.value.compareTo(a.value),
      );
    const colors = [
      C.black,
      Color(0xFF777777),
      C.red,
      Color(0xFFB9485C),
      Color(0xFFBABABA),
      C.darkRed,
    ];
    return Column(
      children: [
        SizedBox(
          height: 225,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  startDegreeOffset: -90,
                  centerSpaceRadius: 62,
                  sectionsSpace: 3,
                  sections: [
                    for (int i = 0;
                        i < entries.length;
                        i++)
                      PieChartSectionData(
                        value: entries[i]
                            .value
                            .toDouble(),
                        title: '',
                        radius: 30,
                        color: colors[
                            i % colors.length],
                      ),
                  ],
                ),
                duration: const Duration(
                  milliseconds: 850,
                ),
                curve: Curves.easeInOutCubic,
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${rides.length}',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'SESSIONS',
                    style: TextStyle(
                      fontSize: 10,
                      color: C.gray,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 17),
        Wrap(
          spacing: 18,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            for (int i = 0;
                i < entries.length;
                i++)
              legend(
                '${statusName(entries[i].key)} '
                '(${entries[i].value})',
                colors[i % colors.length],
              ),
          ],
        ),
      ],
    );
  }
  // ==========================================================
  // BAR CHART — AVERAGE BrAC
  // ==========================================================
  Widget barChart() {
    final initial = average(true);
    final finalReading = average(false);
    if (initial == null &&
        finalReading == null) {
      return chartEmpty(
        'No BrAC readings',
      );
    }
    final values = [
      initial ?? 0.0,
      finalReading ?? 0.0,
    ];
    final highest = math.max(
      values[0],
      values[1],
    );
    final maxY = math.max(
      0.01,
      highest * 1.4,
    );
    return Column(
      children: [
        SizedBox(
          height: 225,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              alignment:
                  BarChartAlignment.spaceAround,
              borderData: FlBorderData(
                show: false,
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine:
                    (value) {
                  return const FlLine(
                    color: C.border,
                    strokeWidth: 1,
                  );
                },
              ),
              barGroups: [
                for (int i = 0; i < 2; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: values[i],
                        width: 43,
                        color: i == 0
                            ? C.red
                            : C.black,
                        borderRadius:
                            const BorderRadius.vertical(
                          top: Radius.circular(9),
                        ),
                      ),
                    ],
                  ),
              ],
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: false,
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: false,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 47,
                    interval: maxY / 4,
                    getTitlesWidget:
                        (value, meta) {
                      return Text(
                        value.toStringAsFixed(3),
                        style: const TextStyle(
                          fontSize: 9,
                          color: C.gray,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 35,
                    getTitlesWidget:
                        (value, meta) {
                      if (value != 0 &&
                          value != 1) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding:
                            const EdgeInsets.only(
                          top: 8,
                        ),
                        child: Text(
                          value == 0
                              ? 'Initial'
                              : 'Final',
                          style: const TextStyle(
                            fontSize: 11,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            duration: const Duration(
              milliseconds: 850,
            ),
            curve: Curves.easeInOutCubic,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 18,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            legend(
              'Initial: ${bracText(initial)}',
              C.red,
            ),
            legend(
              'Final: ${bracText(finalReading)}',
              C.black,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '${readings(true).length} initial readings · '
          '${readings(false).length} final readings',
          style: const TextStyle(
            fontSize: 11,
            color: C.gray,
          ),
        ),
      ],
    );
  }
  // ==========================================================
  // LINE CHART — DAILY ACTIVITY
  // ==========================================================
  Widget lineChart() {
    final days = dailyCounts;
    if (days.isEmpty) {
      return chartEmpty(
        'No dates available',
      );
    }
    final peak = days.fold<int>(
      0,
      (value, day) => math.max(
        value,
        day.value,
      ),
    );
    final step = math.max(
      1,
      (peak / 4).ceil(),
    );
    final labelStep = math.max(
      1,
      (days.length / 6).ceil(),
    );
    return SizedBox(
      height: 278,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: math.max(
            1,
            days.length - 1,
          ).toDouble(),
          minY: 0,
          maxY: (step * 4).toDouble(),
          borderData: FlBorderData(
            show: false,
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval:
                step.toDouble(),
            getDrawingHorizontalLine:
                (value) {
              return const FlLine(
                color: C.border,
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(
                showTitles: false,
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(
                showTitles: false,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: step.toDouble(),
                reservedSize: 32,
                getTitlesWidget:
                    (value, meta) {
                  return Text(
                    '${value.toInt()}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: C.gray,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 35,
                getTitlesWidget:
                    (value, meta) {
                  final index = value.toInt();
                  if (index < 0 ||
                      index >= days.length ||
                      (index % labelStep != 0 &&
                          index !=
                              days.length - 1)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding:
                        const EdgeInsets.only(
                      top: 8,
                    ),
                    child: Text(
                      shortDate(
                        days[index].key,
                      ),
                      style: const TextStyle(
                        fontSize: 10,
                        color: C.gray,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData:
                LineTouchTooltipData(
              getTooltipItems: (spots) {
                return spots.map((spot) {
                  final index = spot.x.toInt();
                  return LineTooltipItem(
                    '${shortDate(days[index].key)}: '
                    '${days[index].value} sessions',
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (int i = 0;
                    i < days.length;
                    i++)
                  FlSpot(
                    i.toDouble(),
                    days[i].value.toDouble(),
                  ),
              ],
              isCurved: true,
              color: C.red,
              barWidth: 3,
              dotData: FlDotData(
                show: false,
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    C.red.withAlpha(45),
                    C.red.withAlpha(0),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(
          milliseconds: 850,
        ),
        curve: Curves.easeInOutCubic,
      ),
    );
  }
  // ==========================================================
  // STATUS BADGE
  // ==========================================================
  Widget statusChip(String status) {
    final failed = status.startsWith(
      'failed',
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: failed ? C.softRed : C.background,
        border: Border.all(color: failed ? C.red.withAlpha(35) : C.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        statusName(status),
        style: TextStyle(
          color: failed
              ? C.red
              : C.black,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }
  // ==========================================================
  // RECORDS SECTION — BOTTOM
  // ==========================================================
  Widget recordsSection() {
    final rows = filtered;
    final totalPages = rows.isEmpty
        ? 1
        : ((rows.length - 1) ~/ pageSize) + 1;
    final current = page.clamp(
      0,
      totalPages - 1,
    );
    final visible = rows
        .skip(current * pageSize)
        .take(pageSize)
        .toList();
    final availableStatuses = statuses.keys.toList()
      ..sort();
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: C.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: C.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'Ride History',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${rides.length} records from $sourceName',
            style: const TextStyle(
              fontSize: 12,
              color: C.gray,
            ),
          ),
          const SizedBox(height: 25),
          // SEARCH AND FILTER
          Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: searchController,
                  onChanged: (text) {
                    setState(() {
                      search = text;
                      page = 0;
                    });
                  },
                  decoration: InputDecoration(
                    hintText:
                        'Search rider, device, status…',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                    ),
                    filled: true,
                    fillColor: C.background,
                    contentPadding: const EdgeInsets.symmetric(vertical: 17, horizontal: 15),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: C.red, width: 1.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Filter ride status',
                offset: const Offset(0, 7),
                elevation: 12,
                color: C.white,
                surfaceTintColor: C.white,
                constraints: const BoxConstraints(minWidth: 210, maxWidth: 250),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: C.border),
                ),
                onOpened: () => setState(() => filterOpen = true),
                onCanceled: () => setState(() => filterOpen = false),
                onSelected: (value) => setState(() {
                  filter = value;
                  page = 0;
                  filterOpen = false;
                }),
                itemBuilder: (context) => [
                  for (final value in ['all', ...availableStatuses])
                    PopupMenuItem<String>(
                      value: value,
                      height: 46,
                      child: Row(children: [
                        Icon(value == filter
                          ? Icons.check_circle_rounded : Icons.circle_outlined,
                          size: 17, color: value == filter ? C.red : C.gray),
                        const SizedBox(width: 10),
                        Text(value == 'all' ? 'All Statuses' : statusName(value),
                          style: TextStyle(
                            fontWeight: value == filter
                              ? FontWeight.w700 : FontWeight.w500,
                            color: value == filter ? C.red : C.black,
                            fontSize: 13,
                          )),
                      ]),
                    ),
                ],
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  width: 205,
                  height: 54,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: filterOpen ? C.softRed : C.background,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: filterOpen ? C.red.withAlpha(140) : C.border,
                    ),
                  ),
                  child: Row(children: [
                    const Icon(Icons.tune_rounded, color: C.red, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(filter == 'all' ? 'All Statuses'
                      : statusName(filter), overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w600))),
                    AnimatedRotation(
                      turns: filterOpen ? .5 : 0,
                      duration: const Duration(milliseconds: 230),
                      child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: C.gray, size: 20),
                    ),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),
          // RECORD TABLE
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'No matching records.',
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 740) {
                  return Column(
                    children: [
                      for (final ride in visible)
                        mobileRide(ride),
                    ],
                  );
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(C.softRed.withAlpha(110)),
                    dataRowColor: WidgetStateProperty.resolveWith((states) =>
                      states.contains(WidgetState.hovered) ? C.softRed.withAlpha(110) : C.white),
                    dividerThickness: 0.5,
                    horizontalMargin: 13,
                    columnSpacing: 27,
                    headingRowHeight: 54,
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 65,
                    columns: const [
                      DataColumn(
                        label: Text('RIDER'),
                      ),
                      DataColumn(
                        label: Text('DEVICE'),
                      ),
                      DataColumn(
                        label: Text('INITIAL BrAC'),
                      ),
                      DataColumn(
                        label: Text('FINAL BrAC'),
                      ),
                      DataColumn(
                        label: Text('STATUS'),
                      ),
                      DataColumn(
                        label: Text('STARTED (UTC)'),
                      ),
                      DataColumn(
                        label: Text('ENDED (UTC)'),
                      ),
                    ],
                    rows: [
                      for (final ride in visible)
                        DataRow(
                          cells: [
                            DataCell(
                              Text(
                                shortId(ride.rider),
                              ),
                            ),
                            DataCell(
                              Text(
                                shortId(ride.device),
                              ),
                            ),
                            DataCell(
                              Text(
                                bracText(
                                  ride.initial,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                bracText(
                                  ride.finalReading,
                                ),
                              ),
                            ),
                            DataCell(
                              statusChip(
                                ride.status,
                              ),
                            ),
                            DataCell(
                              Text(
                                dateText(
                                  ride.started,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                dateText(
                                  ride.ended,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 22),
          const Divider(
            color: C.border,
          ),
          const SizedBox(height: 10),
          // PAGINATION
          Row(
            children: [
              Expanded(
                child: Text(
                  '${rows.length} records · '
                  'Page ${current + 1} of $totalPages',
                  style: const TextStyle(
                    fontSize: 11,
                    color: C.gray,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Previous page',
                onPressed: current == 0
                    ? null
                    : () {
                        setState(() {
                          page = current - 1;
                        });
                      },
                icon: const Icon(
                  Icons.chevron_left_rounded,
                ),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed:
                    current >= totalPages - 1
                        ? null
                        : () {
                            setState(() {
                              page = current + 1;
                            });
                          },
                icon: const Icon(
                  Icons.chevron_right_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  // ==========================================================
  // MOBILE RECORD DESIGN
  // ==========================================================
  Widget mobileRide(Ride ride) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: C.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Rider ${shortId(ride.rider)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              statusChip(
                ride.status,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Device: ${shortId(ride.device)}',
          ),
          const SizedBox(height: 5),
          Text(
            'Initial BrAC: ${bracText(ride.initial)}',
          ),
          const SizedBox(height: 5),
          Text(
            'Final BrAC: ${bracText(ride.finalReading)}',
          ),
          const SizedBox(height: 9),
          Text(
            'Started: ${dateText(ride.started)}',
            style: const TextStyle(
              fontSize: 11,
              color: C.gray,
            ),
          ),
          Text(
            'Ended: ${dateText(ride.ended)}',
            style: const TextStyle(
              fontSize: 11,
              color: C.gray,
            ),
          ),
        ],
      ),
    );
  }
}
// ============================================================
// HOVER ANIMATIONS
// ============================================================
class HoverCard extends StatefulWidget {
  final Widget child;
  const HoverCard({super.key, required this.child});
  @override
  State<HoverCard> createState() => _HoverCardState();
}
class _HoverCardState extends State<HoverCard> {
  bool hovering = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 270),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, hovering ? -5 : 0, 0),
        child: widget.child,
      ),
    );
  }
}
