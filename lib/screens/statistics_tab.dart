import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../database/database_helper.dart';

class StatisticsTab extends StatefulWidget {
  const StatisticsTab({super.key});

  @override
  State<StatisticsTab> createState() => _StatisticsTabState();
}

class _StatisticsTabState extends State<StatisticsTab> {
  bool _isLoading = true;
  Map<String, double> _dailyReadingMinutes = {};
  int _totalReadingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    final sessions = await DatabaseHelper.instance.getReadingSessions();
    
    int totalSec = 0;
    Map<String, int> dailySec = {};
    
    for (var session in sessions) {
      final date = session['date'] as String;
      final duration = session['duration_seconds'] as int;
      totalSec += duration;
      dailySec[date] = (dailySec[date] ?? 0) + duration;
    }

    final dailyMin = dailySec.map((key, value) => MapEntry(key, value / 60.0));

    setState(() {
      _totalReadingSeconds = totalSec;
      _dailyReadingMinutes = dailyMin;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Get last 7 days including today
    final now = DateTime.now();
    final last7Days = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return d.toIso8601String().split('T')[0];
    });

    final maxY = _dailyReadingMinutes.values.isEmpty ? 10.0 : _dailyReadingMinutes.values.reduce((a, b) => a > b ? a : b);

    final int hours = _totalReadingSeconds ~/ 3600;
    final int minutes = (_totalReadingSeconds % 3600) ~/ 60;
    final int seconds = _totalReadingSeconds % 60;

    return Scaffold(
      appBar: AppBar(title: const Text('Reading Statistics')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text('Total Reading Time', style: TextStyle(fontSize: 18, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text(
                      '${hours}h ${minutes}m ${seconds}s',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text('Last 7 Days (Minutes)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (maxY * 1.2).clamp(1.0, double.infinity),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem('${rod.toY.toStringAsFixed(1)} min', const TextStyle(color: Colors.white));
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= last7Days.length) return const SizedBox();
                          final dateStr = last7Days[idx];
                          final parts = dateStr.split('-');
                          if (parts.length == 3) {
                            return Padding(padding: const EdgeInsets.only(top: 8), child: Text('${parts[1]}/${parts[2]}', style: const TextStyle(fontSize: 10)));
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: (maxY / 5).clamp(1.0, double.infinity),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(7, (i) {
                    final dateStr = last7Days[i];
                    final minutes = (_dailyReadingMinutes[dateStr] ?? 0.0);
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: minutes,
                          color: Colors.blueAccent,
                          width: 22,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
