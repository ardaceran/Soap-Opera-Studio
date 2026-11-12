import 'package:flutter/material.dart';
import '../data.dart';
import '../repository.dart';
import '../theme.dart';

/// Real cost per episode from the `episode_costs` view (sum of the episode's jobs).
class CostPanelScreen extends StatefulWidget {
  const CostPanelScreen({super.key});

  @override
  State<CostPanelScreen> createState() => _CostPanelScreenState();
}

class _CostPanelScreenState extends State<CostPanelScreen> {
  late Future<List<EpisodeCost>> _costs = Repo.fetchEpisodeCosts();

  void _reload() => setState(() => _costs = Repo.fetchEpisodeCosts());

  String _usd(double v) => '\$${v.toStringAsFixed(4)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cost per episode',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<EpisodeCost>>(
        future: _costs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load costs:\n${errText(snap.error!)}',
                    textAlign: TextAlign.center),
              ),
            );
          }
          final list = snap.data ?? const <EpisodeCost>[];
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  Repo.signedIn
                      ? 'No cost data yet.\nCosts appear here when your episodes are generated.'
                      : 'Sign in to see the cost of your own series.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            );
          }
          final total = list.fold<double>(0, (a, c) => a + c.usd);
          final avg = total / list.length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  _stat('Episodes', '${list.length}'),
                  const SizedBox(width: 10),
                  _stat('Total', _usd(total)),
                  const SizedBox(width: 10),
                  _stat('Average', _usd(avg)),
                ],
              ),
              const SizedBox(height: 16),
              for (final c in list)
                Card(
                  color: kCard,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(c.seriesTitle,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Episode ${c.number}'),
                    trailing: Text(_usd(c.usd),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'Each episode cost is the sum of its generation jobs (Claude, images, video, voice).',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
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
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
      );
}
