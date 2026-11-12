import 'package:flutter/material.dart';
import '../data.dart';
import '../theme.dart';
import '../widgets.dart';
import 'episode_player_screen.dart';

class SeriesDetailScreen extends StatelessWidget {
  const SeriesDetailScreen({super.key, required this.series});
  final Series series;

  void _openEpisode(BuildContext context, Episode e) {
    final playable =
        e.status == EpisodeStatus.published || e.status == EpisodeStatus.voting;
    if (!playable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.status == EpisodeStatus.rendering
                ? 'Bölüm hâlâ üretiliyor.'
                : 'Bu bölüm önceki bölümün oylamasından sonra açılır.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EpisodePlayerScreen(series: series, episode: e),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 180,
            backgroundColor: series.colors.last,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(series.title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: series.colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${series.genre} · ${series.setting}',
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 20),
                  Text('Karakterler',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final c in series.characters)
                          Padding(
                            padding: const EdgeInsets.only(right: 18),
                            child: Column(
                              children: [
                                CharacterAvatar(c, radius: 28),
                                const SizedBox(height: 6),
                                Text(c.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Text(c.role,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 11)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Row(
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: kGold),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Karakter kilidi: yüzler referans görsellerle sabit tutulur.',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Sezon planı',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          if (series.episodes.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Text(
                  'Henüz bölüm yok. Üretim hattı bağlanınca sezon planı ve bölümler burada görünecek.',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final e = series.episodes[i];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Card(
                    color: kCard,
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      onTap: () => _openEpisode(context, e),
                      leading: CircleAvatar(
                        backgroundColor: statusColor(e.status).withAlpha(50),
                        child: Text('${e.number}',
                            style: TextStyle(
                                color: statusColor(e.status),
                                fontWeight: FontWeight.bold)),
                      ),
                      title: Text(e.title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(e.summary),
                      trailing: Tag(statusLabel(e.status), statusColor(e.status)),
                    ),
                  ),
                );
              },
              childCount: series.episodes.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
