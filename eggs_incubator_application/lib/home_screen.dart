import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'mqtt_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<MqttService>();
    final d = svc.data;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          '🥚 Inkubator Telur',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                Icon(
                  svc.connected ? Icons.wifi : Icons.wifi_off,
                  color: svc.connected ? Colors.greenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 4),
                Text(
                  svc.status,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      body: d == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.orange),
                  const SizedBox(height: 16),
                  Text(svc.status),
                  const SizedBox(height: 8),
                  const Text(
                    'Pastikan ESP32 menyala\ndan terhubung ke WiFi',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _HariCard(hari: d.hari),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SensorCard(
                        label: 'Suhu',
                        value: '${d.suhu.toStringAsFixed(1)}°C',
                        icon: Icons.thermostat,
                        color: d.suhu > 37.5
                            ? Colors.red
                            : d.suhu < 36.5
                            ? Colors.blue
                            : Colors.green,
                        sub: d.suhu > 37.5
                            ? 'Terlalu panas!'
                            : d.suhu < 36.5
                            ? 'Terlalu dingin!'
                            : 'Normal ✓',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SensorCard(
                        label: 'Kelembaban',
                        value: '${d.humidity.toStringAsFixed(0)}%',
                        icon: Icons.water_drop,
                        color: Colors.lightBlue,
                        sub: 'Target: 55–65%',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatusCard(
                        label: 'Lampu',
                        aktif: d.lampu,
                        icon: Icons.lightbulb,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatusCard(
                        label: 'Kipas',
                        aktif: d.kipas,
                        icon: Icons.air,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ServoCard(
                  posisi: d.posServo,
                  sisaMenit: d.sisaRotasiMenit,
                  hari: d.hari,
                  onManual: (deg) => svc.servoManual(deg),
                ),
                const SizedBox(height: 12),
                _GrafikCard(
                  title: 'Grafik Suhu (°C)',
                  data: svc.suhuHistory,
                  color: Colors.orange,
                  minY: 30,
                  maxY: 45,
                  garisBawah: 36.5,
                  garisAtas: 37.5,
                ),
                const SizedBox(height: 12),
                _GrafikCard(
                  title: 'Grafik Kelembaban (%)',
                  data: svc.humHistory,
                  color: Colors.lightBlue,
                  minY: 30,
                  maxY: 100,
                  garisBawah: 55,
                  garisAtas: 65,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text(
                      'Reset Hari (Telur Baru)',
                      style: TextStyle(fontSize: 16),
                    ),
                    onPressed: () => _confirmReset(context, svc),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  void _confirmReset(BuildContext context, MqttService svc) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset Hari?'),
        content: const Text(
          'Hitungan hari akan kembali ke 1. Lakukan jika ada telur baru.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              svc.resetHari();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Hari direset ke 1')),
              );
            },
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
// WIDGETS
// ─────────────────────────────────────────

class _HariCard extends StatelessWidget {
  final int hari;
  const _HariCard({required this.hari});

  @override
  Widget build(BuildContext context) {
    double progress = hari / 21;
    bool hatch = hari >= 19;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hari ke-$hari dari 21',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Chip(
                  label: Text(
                    hatch ? '🐣 Hatch!' : '🥚 Inkubasi',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: hatch ? Colors.green : Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 12,
                backgroundColor: Colors.orange.shade100,
                valueColor: AlwaysStoppedAnimation(
                  hatch ? Colors.green : Colors.orange,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Sisa ${21 - hari} hari lagi',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  final String label, value, sub;
  final IconData icon;
  final Color color;
  const _SensorCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
              sub,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String label;
  final bool aktif;
  final IconData icon;
  const _StatusCard({
    required this.label,
    required this.aktif,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      color: aktif ? Colors.orange.shade50 : Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: aktif ? Colors.orange : Colors.grey, size: 28),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  aktif ? 'AKTIF' : 'MATI',
                  style: TextStyle(
                    color: aktif ? Colors.orange : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServoCard extends StatelessWidget {
  final int posisi, sisaMenit, hari;
  final Function(int) onManual;
  const _ServoCard({
    required this.posisi,
    required this.sisaMenit,
    required this.hari,
    required this.onManual,
  });

  @override
  Widget build(BuildContext context) {
    bool hatch = hari >= 19;
    int jam = sisaMenit ~/ 60;
    int menit = sisaMenit % 60;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Servo Rotasi Telur',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Posisi: $posisi°',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      hatch
                          ? 'Mode Hatch — servo diam'
                          : 'Berikutnya: ${jam}j ${menit}m',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                if (!hatch)
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => onManual(45),
                        child: const Text('45°'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => onManual(135),
                        child: const Text('135°'),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GrafikCard extends StatelessWidget {
  final String title;
  final List<ChartPoint> data;
  final Color color;
  final double minY, maxY, garisBawah, garisAtas;
  const _GrafikCard({
    required this.title,
    required this.data,
    required this.color,
    required this.minY,
    required this.maxY,
    required this.garisBawah,
    required this.garisAtas,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 130,
              child: data.isEmpty
                  ? const Center(child: Text('Menunggu data...'))
                  : LineChart(
                      LineChartData(
                        minY: minY,
                        maxY: maxY,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            HorizontalLine(
                              y: garisBawah,
                              color: Colors.blue.withOpacity(0.5),
                              strokeWidth: 1,
                              dashArray: [4, 4],
                            ),
                            HorizontalLine(
                              y: garisAtas,
                              color: Colors.red.withOpacity(0.5),
                              strokeWidth: 1,
                              dashArray: [4, 4],
                            ),
                          ],
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                              getTitlesWidget: (v, _) => Text(
                                v.toInt().toString(),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: data.map((e) => FlSpot(e.x, e.y)).toList(),
                            isCurved: true,
                            color: color,
                            barWidth: 2,
                            dotData: FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: color.withOpacity(0.1),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
