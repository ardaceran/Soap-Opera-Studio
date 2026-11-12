import 'package:flutter/material.dart';
import '../data.dart';
import '../theme.dart';
import '../widgets.dart';
import '../repository.dart';
import 'add_episode_screen.dart';
import 'episode_player_screen.dart';

class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({super.key, required this.series});
  final Series series;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  late Series series = widget.series;

  bool get _isOwner => Repo.userId != null && Repo.userId == series.ownerId;

  Future<void> _reload() async {
    try {
      final s = await Repo.fetchSeriesById(series.id);
      if (mounted) setState(() => series = s);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errText(e))));
      }
    }
  }

  Future<void> _addEpisode() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddEpisodeScreen(series: series),
      ),
    );
    if (added == true) await _reload();
  }

  void _openEpisode(BuildContext context, Episode e) {
    final playable =
        e.status == EpisodeStatus.published || e.status == EpisodeStatus.voting;
    if (!playable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.status == EpisodeStatus.rendering
                ? 'This episode is still being generated.'
                : 'This episode unlocks after the previous episode\'s vote.',
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
      floatingActionButton: _isOwner
          ? FloatingActionButton.extended(
              onPressed: _addEpisode,
              icon: const Icon(Icons.add),
              label: const Text('Add episode'),
            )
          : null,
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
                  Text('Characters',
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
                          'Character lock: faces are kept consistent with reference images.',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('Season plan',
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Text(
                  _isOwner
                      ? 'No episodes yet. Tap "Add episode" to write the first one.'
                      : 'No episodes yet.',
                  style: const TextStyle(color: Colors.white54),
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
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }
}
