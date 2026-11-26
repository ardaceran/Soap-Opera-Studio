import 'dart:async';
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
  List<JobInfo> _jobs = const [];
  int _finished = -1; // done + failed jobs seen last time; a change means news
  Timer? _timer;

  bool get _isOwner => Repo.userId != null && Repo.userId == series.ownerId;

  @override
  void initState() {
    super.initState();
    // Generation jobs are only visible to the owner (database rules).
    if (_isOwner) {
      _checkJobs();
      _timer = Timer.periodic(const Duration(seconds: 4), (_) => _checkJobs());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Polls the generation jobs; when one finishes, reloads the series so the
  /// new episode or its video shows up without the user doing anything.
  Future<void> _checkJobs() async {
    try {
      final jobs = await Repo.fetchSeriesJobs(series.id);
      final finished = jobs.where((j) => !j.active).length;
      final changed = _finished >= 0 && finished != _finished;
      _finished = finished;
      if (!mounted) return;
      setState(() => _jobs = jobs);
      if (changed) await _reload();
    } catch (_) {
      // Network hiccup: the next tick tries again.
    }
  }

  /// The job to show: a running one first, else the oldest queued one, else a
  /// failure if it is the most recent thing that happened.
  JobInfo? get _current {
    final running = _jobs.where((j) => j.status == 'running');
    if (running.isNotEmpty) return running.first;
    final queued = _jobs.where((j) => j.status == 'queued');
    if (queued.isNotEmpty) return queued.first;
    if (_jobs.isNotEmpty) {
      final last = _jobs.reduce((a, b) =>
          (b.updatedAt ?? DateTime(0)).isAfter(a.updatedAt ?? DateTime(0)) ? b : a);
      if (last.status == 'failed') return last;
    }
    return null;
  }

  bool _videoInProgress(Episode e) => _jobs.any(
      (j) => j.type == 'assemble' && j.active && j.episodeNumber == e.number);

  Widget _statusBanner() {
    final j = _current;
    if (j == null) return const SizedBox.shrink();
    final failed = j.status == 'failed';
    final waiting = j.status == 'queued';
    final color = failed ? Colors.red.shade300 : kGold;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Row(
        children: [
          if (failed)
            Icon(Icons.error_outline, color: color)
          else
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  failed
                      ? '${j.label} failed'
                      : waiting
                          ? '${j.label} (waiting in the queue)…'
                          : '${j.label}…',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  failed
                      ? (j.error ?? 'Unknown error').split('\n').first
                      : waiting
                          ? 'Starts as soon as the generation worker is free.'
                          : 'This page updates by itself when it is ready.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
          SliverToBoxAdapter(child: _statusBanner()),
          if (series.episodes.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Text(
                  _isOwner
                      ? (_jobs.any((j) => j.active)
                          ? 'The first episode is on its way.'
                          : 'No episodes yet. Tap "Add episode" to write the first one.')
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
                      subtitle: Text(_videoInProgress(e)
                          ? 'Video in progress…'
                          : e.summary),
                      trailing: _videoInProgress(e)
                          ? const Tag('Making video', kBlue)
                          : Tag(statusLabel(e.status), statusColor(e.status)),
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
