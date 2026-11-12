import 'package:flutter/material.dart';
import '../data.dart';
import '../theme.dart';
import '../widgets.dart';

class CostPanelScreen extends StatefulWidget {
  const CostPanelScreen({super.key});

  @override
  State<CostPanelScreen> createState() => _CostPanelScreenState();
}

class _CostPanelScreenState extends State<CostPanelScreen> {
  static const int _stillCents = 5; // örnek still maliyeti (cent)
  double _budget = 450; // cent

  /// 0-1 knapsack: toplam maliyeti bütçeyi aşmadan önem toplamını maksimize eder.
  List<bool> _solve(int budget) {
    final n = kScenePlan.length;
    final dp = List.generate(n + 1, (_) => List<int>.filled(budget + 1, 0));
    for (var i = 1; i <= n; i++) {
      final w = kScenePlan[i - 1].importance;
      final c = kScenePlan[i - 1].videoCostCents;
      for (var b = 0; b <= budget; b++) {
        dp[i][b] = dp[i - 1][b];
        if (c <= b) {
          final v = dp[i - 1][b - c] + w;
          if (v > dp[i][b]) dp[i][b] = v;
        }
      }
    }
    final pick = List<bool>.filled(n, false);
    var b = budget;
    for (var i = n; i >= 1; i--) {
      if (dp[i][b] != dp[i - 1][b]) {
        pick[i - 1] = true;
        b -= kScenePlan[i - 1].videoCostCents;
      }
    }
    return pick;
  }

  Widget _stat(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final budget = _budget.round();
    final pick = _solve(budget);
    var videoCount = 0;
    var importance = 0;
    var videoCost = 0;
    var totalImportance = 0;
    for (var i = 0; i < kScenePlan.length; i++) {
      totalImportance += kScenePlan[i].importance;
      if (pick[i]) {
        videoCount++;
        importance += kScenePlan[i].importance;
        videoCost += kScenePlan[i].videoCostCents;
      }
    }
    final total = kScenePlan.length * _stillCents + videoCost;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maliyet ve bütçe',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const Text(
            'Bütçe arttıkça daha fazla sahne video olur. Seçimi 0-1 knapsack yapar: en dramatik sahneler önce video alır.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Text(
            'Bölüm video bütçesi: ${usd(budget)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Slider(
            value: _budget,
            min: 0,
            max: 1000,
            divisions: 100,
            label: usd(budget),
            onChanged: (v) => setState(() => _budget = v),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final p in const [
                (200, 'Düşük'),
                (450, 'Orta'),
                (900, 'Yüksek'),
              ])
                ActionChip(
                  label: Text('${p.$2} ${usd(p.$1)}'),
                  onPressed: () => setState(() => _budget = p.$1.toDouble()),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat('Video sahne', '$videoCount / ${kScenePlan.length}'),
              const SizedBox(width: 10),
              _stat('Önem', '$importance / $totalImportance'),
              const SizedBox(width: 10),
              _stat('Bölüm maliyeti', usd(total)),
            ],
          ),
          const SizedBox(height: 20),
          Text('Sahneler',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (var i = 0; i < kScenePlan.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: pick[i] ? kGold.withAlpha(140) : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(kScenePlan[i].title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          'önem ${kScenePlan[i].importance} · video ${usd(kScenePlan[i].videoCostCents)}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  pick[i] ? const Tag('VİDEO', kGold) : const Tag('STILL', kGrey),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Örnek birim maliyetler, gerçek fiyat değildir. Gerçek uygulamada rakamlar cost_events tablosundan gelir.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
