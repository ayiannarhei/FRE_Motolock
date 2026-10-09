import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F46E5)),
      ),
      home: const AnalyticsDashboard(),
    );
  }
}

class AnalyticsDashboard extends StatefulWidget {
  const AnalyticsDashboard({super.key});

  @override
  State<AnalyticsDashboard> createState() => _AnalyticsDashboardState();
}

class _AnalyticsDashboardState extends State<AnalyticsDashboard> {
  static const double sectionA = 88;
  static const double sectionB = 84;

  static const List<Map<String, dynamic>> students = [
    {'name': 'Maria Santos', 'grade': 92},
    {'name': 'Juan Cruz', 'grade': 85},
    {'name': 'Ana Reyes', 'grade': 95},
    {'name': 'Carlo Mendoza', 'grade': 78},
    {'name': 'Liza Ramos', 'grade': 86},
    {'name': 'Riezseht Basilio', 'grade': 90},
    {'name': 'Ariane Sudaria', 'grade': 73},
    {'name': 'Ayianna Rhei', 'grade': 88},
  ];

  String getPerformance(int grade) {
    if (grade >= 90) return 'Excellent';
    if (grade >= 80) return 'Good';
    if (grade >= 75) return 'Passing';
    return 'Needs Attention';
  }

  Color getPerformanceColor(String category) {
    switch (category) {
      case 'Excellent':
        return const Color(0xFF10B981); // Emerald
      case 'Good':
        return const Color(0xFF3B82F6); // Blue
      case 'Passing':
        return const Color(0xFFF59E0B); // Amber
      case 'Needs Attention':
        return const Color(0xFFEF4444); // Red
      default:
        return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    double startingValue = (students.first['grade'] as int).toDouble();
    double currentValue = (students.last['grade'] as int).toDouble();
    double percentageChange =
        ((currentValue - startingValue) / startingValue) * 100;
    String trend = currentValue > startingValue
        ? 'Increasing'
        : currentValue < startingValue
        ? 'Decreasing'
        : 'Stable';
    double sectionDifference = (sectionA - sectionB).abs();
    String higherSection = sectionA > sectionB
        ? 'Section A'
        : sectionB > sectionA
        ? 'Section B'
        : 'Equal';

    final performanceCounts = {
      'Excellent': 0,
      'Good': 0,
      'Passing': 0,
      'Needs Attention': 0,
    };

    for (var student in students) {
      final category = getPerformance(student['grade'] as int);
      performanceCounts[category] = performanceCounts[category]! + 1;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Student Analytics Dashboard',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.1),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey[200], height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('Overview'),
                buildKpiSection(
                  startingValue,
                  currentValue,
                  percentageChange,
                  trend,
                ),

                const SizedBox(height: 40),

                // Charts Row
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 700) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionHeader('Performance Trend'),
                                buildLineChart(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionHeader('Performance Split'),
                                buildPieChart(
                                  performanceCounts['Excellent']!,
                                  performanceCounts['Good']!,
                                  performanceCounts['Passing']!,
                                  performanceCounts['Needs Attention']!,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader('Performance Trend'),
                          buildLineChart(),
                          const SizedBox(height: 40),
                          _buildSectionHeader('Performance Split'),
                          buildPieChart(
                            performanceCounts['Excellent']!,
                            performanceCounts['Good']!,
                            performanceCounts['Passing']!,
                            performanceCounts['Needs Attention']!,
                          ),
                        ],
                      );
                    }
                  },
                ),

                const SizedBox(height: 40),
                _buildSectionHeader('Performance Summary'),
                buildPerformanceSummary(performanceCounts),
                const SizedBox(height: 40),
                _buildSectionHeader('Student Records'),
                buildRecordsTable(),
                const SizedBox(height: 40),
                _buildSectionHeader('Group Comparison'),
                buildGroupComparison(sectionDifference, higherSection),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1F2937),
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget buildKpiSection(
    double startingValue,
    double currentValue,
    double percentageChange,
    String trend,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 760) {
          return Row(
            children: [
              Expanded(
                child: _kpiCard(
                  'Starting Value',
                  startingValue.toStringAsFixed(0),
                  Icons.flag_outlined,
                  const Color(0xFF4F46E5),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _kpiCard(
                  'Current Value',
                  currentValue.toStringAsFixed(0),
                  Icons.analytics_outlined,
                  const Color(0xFF0EA5E9),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _kpiCard(
                  'Percentage Change',
                  '${percentageChange.toStringAsFixed(2)}%',
                  Icons.percent,
                  const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _kpiCard(
                  'Trend',
                  trend,
                  Icons.trending_down_outlined,
                  const Color(0xFFF43F5E),
                ),
              ),
            ],
          );
        } else {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _kpiCard(
                      'Starting Value',
                      startingValue.toStringAsFixed(0),
                      Icons.flag_outlined,
                      const Color(0xFF4F46E5),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _kpiCard(
                      'Current Value',
                      currentValue.toStringAsFixed(0),
                      Icons.analytics_outlined,
                      const Color(0xFF0EA5E9),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _kpiCard(
                      'Percentage Change',
                      '${percentageChange.toStringAsFixed(2)}%',
                      Icons.percent,
                      const Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _kpiCard(
                      'Trend',
                      trend,
                      Icons.trending_down_outlined,
                      const Color(0xFFF43F5E),
                    ),
                  ),
                ],
              ),
            ],
          );
        }
      },
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardContainer(Widget child) {
    return Container(
      height: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget buildLineChart() {
    return _buildCardContainer(
      LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                students.length,
                (index) => FlSpot(
                  index.toDouble(),
                  (students[index]['grade'] as int).toDouble(),
                ),
              ),
              isCurved: true,
              color: const Color(0xFF4F46E5),
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF4F46E5).withOpacity(0.1),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (value, meta) {
                  int index = value.toInt();
                  if (index >= 0 && index < students.length) {
                    String firstName = (students[index]['name'] as String)
                        .split(' ')[0];
                    return Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Text(
                        firstName,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 20,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey.withOpacity(0.1),
                strokeWidth: 1,
              );
            },
          ),
          minX: 0,
          maxX: (students.length - 1).toDouble(),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  Widget buildPieChart(
    int excellent,
    int good,
    int passing,
    int needsAttention,
  ) {
    return _buildCardContainer(
      Column(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sectionsSpace: 4,
                centerSpaceRadius: 50,
                sections: [
                  if (excellent > 0)
                    _pieSection(Colors.green, excellent, '$excellent'),
                  if (good > 0) _pieSection(Colors.blue, good, '$good'),
                  if (passing > 0)
                    _pieSection(Colors.orange, passing, '$passing'),
                  if (needsAttention > 0)
                    _pieSection(Colors.red, needsAttention, '$needsAttention'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _indicator(Colors.green, 'Excellent'),
              _indicator(Colors.blue, 'Good'),
              _indicator(Colors.orange, 'Passing'),
              _indicator(Colors.red, 'Needs Attention'),
            ],
          ),
        ],
      ),
    );
  }

  PieChartSectionData _pieSection(Color color, int value, String title) {
    return PieChartSectionData(
      color: color,
      value: value.toDouble(),
      title: title,
      radius: 40,
      titleStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ),
    );
  }

  Widget _indicator(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF4B5563),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget buildRecordsTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: List.generate(students.length, (index) {
            var student = students[index];
            String category = getPerformance(student['grade'] as int);
            Color catColor = getPerformanceColor(category);
            bool isLast = index == students.length - 1;

            return Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: isLast
                      ? BorderSide.none
                      : BorderSide(color: Colors.grey.withOpacity(0.1)),
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFF3F4F6),
                  child: Text(
                    student['name'][0],
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(
                  student['name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                    fontSize: 15,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    'Grade: ${student['grade']}\nPerformance: $category',
                    style: const TextStyle(color: Color(0xFF6B7280)),
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: catColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      color: catColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget buildPerformanceSummary(Map<String, int> counts) {
    const categories = ['Excellent', 'Good', 'Passing', 'Needs Attention'];

    return Container(
      key: const ValueKey('performance-summary'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var index = 0; index < categories.length; index++) ...[
            if (index > 0) const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: getPerformanceColor(categories[index]),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        categories[index],
                        style: const TextStyle(
                          color: Color(0xFF4B5563),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  key: ValueKey('performance-count-${categories[index]}'),
                  '${counts[categories[index]]}',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget buildGroupComparison(double difference, String higherSection) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SECTION COMPARISON',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _comparisonValue('Section A', sectionA)),
              const SizedBox(width: 16),
              Expanded(child: _comparisonValue('Section B', sectionB)),
            ],
          ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: _comparisonValue('Difference', difference, decimals: 2),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Higher Average',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      higherSection,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _comparisonValue(String label, double value, {int decimals = 0}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value.toStringAsFixed(decimals),
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
