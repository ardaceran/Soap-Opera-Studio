import 'package:flutter/material.dart';
import '../data.dart';
import '../theme.dart';
import '../widgets.dart';
import 'series_detail_screen.dart';
import 'vote_sheet.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Series? votingSeries;
    Episode? votingEpisode;
    for (final s in kSeries) {
      for (final e in s.episodes) {
        if (e.status == EpisodeStatus.voting && votingSeries == null) {
          votingSeries = s;
          votingEpisode = e;
        }
      }
    }
    final vs = votingSeries;
    final ve = votingEpisode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dizilerim',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (vs != null && ve != null)
            Card(
              color: kCard,
              margin: const EdgeInsets.only(bottom: 20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.how_to_vote, color: kGold),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Oylama açık',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            '${vs.title} · Bölüm ${ve.number} sonrası',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: () => showVoteSheet(
                        context,
                        seriesTitle: vs.title,
                        nextEpisode: ve.number + 1,
                      ),
                      child: const Text('Oy ver'),
                    ),
                  ],
                ),
              ),
            ),
          Text(
            'Dizilerin',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (final s in kSeries)
            SeriesCard(
              series: s,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SeriesDetailScreen(series: s),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
