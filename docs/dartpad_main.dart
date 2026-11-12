// Soap Opera Studio - single-file version (for DartPad). Mock data, no backend.
import 'dart:async';
import 'package:flutter/material.dart';

// ===== theme.dart =====
const Color kGold = Color(0xFFE6B450);
const Color kBg = Color(0xFF120A10);
const Color kCard = Color(0xFF1E131B);
const Color kGreen = Color(0xFF4CAF7A);
const Color kBlue = Color(0xFF5AA9E6);
const Color kGrey = Color(0xFF8A7F86);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8E1B3A),
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      elevation: 0,
      centerTitle: false,
    ),
  );
}

String usd(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

// ===== data.dart =====
// Sample (mock) data. In the real app this comes from Supabase.

class Character {
  const Character(this.name, this.role, this.color);
  final String name;
  final String role;
  final Color color;
}

enum EpisodeStatus { published, voting, rendering, locked }

class Episode {
  const Episode(this.number, this.title, this.summary, this.status);
  final int number;
  final String title;
  final String summary;
  final EpisodeStatus status;
}

class Series {
  const Series({
    required this.id,
    required this.title,
    required this.genre,
    required this.setting,
    required this.colors,
    required this.characters,
    required this.episodes,
  });
  final String id;
  final String title;
  final String genre;
  final String setting;
  final List<Color> colors;
  final List<Character> characters;
  final List<Episode> episodes;
}

/// Scene plan for the knapsack example on the cost screen.
class ScenePlan {
  const ScenePlan(this.title, this.importance, this.videoCostCents);
  final String title;
  final int importance; // 1-10 dramatic importance
  final int videoCostCents; // sample video cost (cents)
}

const List<Series> kSeries = [
  Series(
    id: 's1',
    title: 'Red Villa',
    genre: 'Drama · Intrigue',
    setting: 'A seaside villa in Izmir',
    colors: [Color(0xFF8E1B3A), Color(0xFF2A0F1E)],
    characters: [
      Character('Defne', 'Heir of the villa', Color(0xFFE6B450)),
      Character('Kerem', 'Gizemli avukat', Color(0xFF5AA9E6)),
      Character('Nilufer', 'Stepmother', Color(0xFFB06AB3)),
    ],
    episodes: [
      Episode(1, 'The Will', 'Defne returns to the villa for her father\'s will.',
          EpisodeStatus.published),
      Episode(2, 'The Locked Room', 'An old letter is found in the locked room.',
          EpisodeStatus.voting),
      Episode(3, 'The Secret', 'The letter\'s author is revealed.',
          EpisodeStatus.rendering),
      Episode(4, 'Confrontation', 'The family settles scores at dinner.',
          EpisodeStatus.locked),
      Episode(5, 'Finale', 'The season\'s big secret comes out.',
          EpisodeStatus.locked),
    ],
  ),
  Series(
    id: 's2',
    title: 'The Last Ferry',
    genre: 'Romance · Drama',
    setting: 'Karsiyaka pier',
    colors: [Color(0xFF1B5E8E), Color(0xFF0F1E2A)],
    characters: [
      Character('Ece', 'Ship captain\'s daughter', Color(0xFFE6B450)),
      Character('Baris', 'Young journalist', Color(0xFF4CAF7A)),
    ],
    episodes: [
      Episode(1, 'First Voyage', 'Ece and Baris meet on the ferry.',
          EpisodeStatus.published),
      Episode(2, 'Fog', 'Plans change on a foggy evening.',
          EpisodeStatus.locked),
      Episode(3, 'The Letter', 'An old secret reaches the pier.',
          EpisodeStatus.locked),
    ],
  ),
];

const List<ScenePlan> kScenePlan = [
  ScenePlan('Surprise guest at the villa door', 6, 90),
  ScenePlan('Tense looks at the breakfast table', 3, 70),
  ScenePlan('The letter is found', 8, 110),
  ScenePlan('Confrontation on the stairs', 9, 120),
  ScenePlan('Phone call', 2, 60),
  ScenePlan('Secret meeting in the garden', 7, 100),
  ScenePlan('Reading of the will', 8, 110),
  ScenePlan('Silent dinner', 3, 70),
  ScenePlan('Cliffhanger: the door opens', 10, 130),
  ScenePlan('Flashback scene', 5, 90),
];

// ===== widgets.dart =====
String statusLabel(EpisodeStatus s) {
  switch (s) {
    case EpisodeStatus.published:
      return 'Published';
    case EpisodeStatus.voting:
      return 'Voting';
    case EpisodeStatus.rendering:
      return 'Generating';
    case EpisodeStatus.locked:
      return 'Locked';
  }
}

Color statusColor(EpisodeStatus s) {
  switch (s) {
    case EpisodeStatus.published:
      return kGreen;
    case EpisodeStatus.voting:
      return kGold;
    case EpisodeStatus.rendering:
      return kBlue;
    case EpisodeStatus.locked:
      return kGrey;
  }
}

class Tag extends StatelessWidget {
  const Tag(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(130)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar(this.character, {super.key, this.radius = 20});
  final Character character;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: character.color.withAlpha(60),
      child: Text(
        character.name.substring(0, 1),
        style: TextStyle(
          color: character.color,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}

class SeriesCard extends StatelessWidget {
  const SeriesCard({super.key, required this.series, required this.onTap});
  final Series series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final published = series.episodes
        .where((e) =>
            e.status == EpisodeStatus.published ||
            e.status == EpisodeStatus.voting)
        .length;
    return Card(
      color: kCard,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 170,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: series.colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tag(series.genre, Colors.white),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    series.title,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(series.setting,
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final c in series.characters)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: CharacterAvatar(c, radius: 14),
                        ),
                      const Spacer(),
                      Text('$published episodes published',
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== screens/vote_sheet.dart =====
Future<void> showVoteSheet(
  BuildContext context, {
  required String seriesTitle,
  required int nextEpisode,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) =>
        _VoteSheet(seriesTitle: seriesTitle, nextEpisode: nextEpisode),
  );
}

class _VoteSheet extends StatefulWidget {
  const _VoteSheet({required this.seriesTitle, required this.nextEpisode});
  final String seriesTitle;
  final int nextEpisode;

  @override
  State<_VoteSheet> createState() => _VoteSheetState();
}

class _VoteSheetState extends State<_VoteSheet> {
  final List<String> _options = const [
    'Defne burns the letter',
    "Defne gives the letter to Kerem",
    'Nilufer steals the letter',
  ];
  final List<int> _votes = [41, 33, 26];
  int? _picked;

  int get _total => _votes.fold<int>(0, (a, b) => a + b);

  Widget _tile(int i) {
    final pct = _total == 0 ? 0.0 : _votes[i] / _total;
    final picked = _picked == i;
    final voted = _picked != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: voted
            ? null
            : () => setState(() {
                  _picked = i;
                  _votes[i] = _votes[i] + 1;
                }),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: picked ? kGold : Colors.white24,
              width: picked ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _options[i],
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (voted)
                    Text(
                      '%${(pct * 100).round()}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                ],
              ),
              if (voted) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: Colors.white12,
                    color: picked ? kGold : Colors.white54,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${widget.seriesTitle} · Vote for episode ${widget.nextEpisode}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'The winning option goes into the next episode\'s script.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _options.length; i++) _tile(i),
          const SizedBox(height: 4),
          Text(
            _picked == null
                ? 'Each user can vote once.'
                : 'Your vote is saved. Results update live. (sample data)',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ===== screens/episode_player_screen.dart =====
class _PlayerScene {
  const _PlayerScene(this.speaker, this.caption, this.colors);
  final String speaker;
  final String caption;
  final List<Color> colors;
}

// Sample scenes. In the real app each scene is a Flux image / video clip plus audio.
const List<_PlayerScene> _scenes = [
  _PlayerScene('Defne', 'My father\'s will will be read in this room.',
      [Color(0xFF8E1B3A), Color(0xFF2A0F1E)]),
  _PlayerScene('Nilufer', 'This villa has been my home for years.',
      [Color(0xFF6A2C70), Color(0xFF1A0F22)]),
  _PlayerScene('Kerem', 'Nobody was supposed to find the letter.',
      [Color(0xFF1B5E8E), Color(0xFF0F1E2A)]),
  _PlayerScene('Defne', 'So you knew everything all along.',
      [Color(0xFF8E1B3A), Color(0xFF3A1A0A)]),
  _PlayerScene('Nilufer', 'Meet me in the garden at midnight.',
      [Color(0xFF2A4A3A), Color(0xFF0F1A14)]),
  _PlayerScene('Narrator', 'The door slowly opened...',
      [Color(0xFF111111), Color(0xFF8E1B3A)]),
];

class EpisodePlayerScreen extends StatefulWidget {
  const EpisodePlayerScreen({
    super.key,
    required this.series,
    required this.episode,
  });
  final Series series;
  final Episode episode;

  @override
  State<EpisodePlayerScreen> createState() => _EpisodePlayerScreenState();
}

class _EpisodePlayerScreenState extends State<EpisodePlayerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _paused = false;
  bool _voteShown = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(seconds: _scenes.length * 4),
    );
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_voteShown) {
        _voteShown = true;
        _openVote();
      }
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _c.stop();
    } else {
      _c.forward();
    }
  }

  Future<void> _openVote() async {
    _c.stop();
    await showVoteSheet(
      context,
      seriesTitle: widget.series.title,
      nextEpisode: widget.episode.number + 1,
    );
    if (mounted && !_paused && _c.value < 1) {
      _c.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: GestureDetector(
              onTap: _toggle,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final total = _scenes.length;
                  final t = _c.value * total;
                  final idx = t.floor().clamp(0, total - 1);
                  final local = (t - idx).clamp(0.0, 1.0);
                  final scene = _scenes[idx];
                  return ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Ken Burns: slow zoom on a still image
                        Transform.scale(
                          scale: 1.0 + 0.12 * local,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: scene.colors,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.person,
                                size: 180,
                                color: Colors.white.withAlpha(40),
                              ),
                            ),
                          ),
                        ),
                        // scene progress bars
                        Positioned(
                          top: 12,
                          left: 12,
                          right: 12,
                          child: Row(
                            children: [
                              for (var i = 0; i < total; i++)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 2),
                                    child: LinearProgressIndicator(
                                      value: i < idx
                                          ? 1.0
                                          : (i == idx ? local : 0.0),
                                      minHeight: 3,
                                      backgroundColor: Colors.white24,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 24,
                          left: 16,
                          child: Row(
                            children: [
                              const Icon(Icons.auto_awesome,
                                  size: 14, color: kGold),
                              const SizedBox(width: 4),
                              Text(
                                'AI-generated · ${widget.series.title} E${widget.episode.number}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 20,
                          right: 4,
                          child: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        // caption
                        Positioned(
                          left: 24,
                          right: 24,
                          bottom: 110,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                scene.speaker.toUpperCase(),
                                style: const TextStyle(
                                  color: kGold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                scene.caption,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  shadows: [
                                    Shadow(blurRadius: 8, color: Colors.black),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 24,
                          child: FilledButton.icon(
                            onPressed: _openVote,
                            icon: const Icon(Icons.how_to_vote),
                            label: const Text('Vote for the next episode'),
                          ),
                        ),
                        if (_paused)
                          const Center(
                            child: Icon(Icons.play_arrow,
                                size: 80, color: Colors.white70),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===== screens/generation_status_screen.dart =====
class _Step {
  const _Step(this.title, this.detail);
  final String title;
  final String detail;
}

// The 8-step pipeline from the architecture (the worker does the real work; the app only tracks status).
const List<_Step> _steps = [
  _Step('Season plan', 'Claude is writing the season arc and series bible'),
  _Step('Character lock', 'Generating reference images'),
  _Step('Episode script', 'Retrieving context, writing scenes'),
  _Step('Moderation', 'Checking content rules'),
  _Step('Budget decision', 'Which scenes become video? (knapsack)'),
  _Step('Scene media', 'Generating images, video and audio'),
  _Step('Assembly', 'Combining the 1080×1920 video with FFmpeg'),
  _Step('Publish', 'Publishing the episode, opening the vote'),
];

class GenerationStatusScreen extends StatefulWidget {
  const GenerationStatusScreen({super.key, required this.title});
  final String title;

  @override
  State<GenerationStatusScreen> createState() => _GenerationStatusScreenState();
}

class _GenerationStatusScreenState extends State<GenerationStatusScreen> {
  int _done = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 1100), (t) {
      if (!mounted) return;
      if (_done >= _steps.length) {
        t.cancel();
        return;
      }
      setState(() => _done++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Widget _icon(int i) {
    if (i < _done) {
      return const Icon(Icons.check_circle, color: kGold);
    }
    if (i == _done) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    }
    return const Icon(Icons.circle_outlined, color: kGrey);
  }

  @override
  Widget build(BuildContext context) {
    final finished = _done >= _steps.length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            finished ? 'Episode 1 ready' : 'Generating...',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _done / _steps.length,
            minHeight: 6,
            backgroundColor: Colors.white12,
            color: kGold,
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < _steps.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _icon(i),
              title: Text(
                _steps[i].title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: i <= _done ? Colors.white : Colors.white54,
                ),
              ),
              subtitle: Text(_steps[i].detail),
            ),
          const SizedBox(height: 12),
          if (finished)
            FilledButton.icon(
              onPressed: () {
                final s = kSeries.first;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => EpisodePlayerScreen(
                      series: s,
                      episode: s.episodes.first,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Watch episode'),
            ),
          const SizedBox(height: 16),
          const Text(
            'In the real app this screen listens to the jobs table through Supabase Realtime. For now it is a simulation.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ===== screens/series_detail_screen.dart =====
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

// ===== screens/create_series_screen.dart =====
class CreateSeriesScreen extends StatefulWidget {
  const CreateSeriesScreen({super.key});

  @override
  State<CreateSeriesScreen> createState() => _CreateSeriesScreenState();
}

class _CreateSeriesScreenState extends State<CreateSeriesScreen> {
  static const _genres = ['Drama', 'Romance', 'Thriller', 'Comedy'];
  static const _settings = [
    'Izmir villa',
    'Hospital',
    'Corporate holding',
    'Village mansion',
  ];
  static const _roles = ['Hero', 'Villain', 'Mysterious', 'Comic'];

  final _title = TextEditingController();
  String _genre = 'Drama';
  String _setting = 'Izmir villa';
  final List<TextEditingController> _names = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<String> _charRoles = ['Hero', 'Mysterious'];

  @override
  void dispose() {
    _title.dispose();
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  void _addCharacter() {
    setState(() {
      _names.add(TextEditingController());
      _charRoles.add('Villain');
    });
  }

  void _removeCharacter(int i) {
    setState(() {
      _names[i].dispose();
      _names.removeAt(i);
      _charRoles.removeAt(i);
    });
  }

  void _submit() {
    final named = _names.where((c) => c.text.trim().isNotEmpty).length;
    if (_title.text.trim().isEmpty || named < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A series title and at least 2 character names are required.'),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GenerationStatusScreen(title: _title.text.trim()),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New series',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Series title',
              hintText: 'e.g. Red Villa',
              border: OutlineInputBorder(),
            ),
          ),
          _label('Genre'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in _genres)
                ChoiceChip(
                  label: Text(g),
                  selected: _genre == g,
                  onSelected: (_) => setState(() => _genre = g),
                ),
            ],
          ),
          _label('Setting'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _settings)
                ChoiceChip(
                  label: Text(s),
                  selected: _setting == s,
                  onSelected: (_) => setState(() => _setting = s),
                ),
            ],
          ),
          _label('Characters (2–4)'),
          for (var i = 0; i < _names.length; i++)
            Card(
              color: kCard,
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _names[i],
                        decoration: InputDecoration(
                          labelText: 'Character ${i + 1}',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: _charRoles[i],
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final r in _roles)
                          DropdownMenuItem<String>(value: r, child: Text(r)),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _charRoles[i] = v);
                      },
                    ),
                    if (_names.length > 2)
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => _removeCharacter(i),
                      ),
                  ],
                ),
              ),
            ),
          if (_names.length < 4)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addCharacter,
                icon: const Icon(Icons.add),
                label: const Text('Add character'),
              ),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, color: kGold, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Reference images are generated for the characters and you approve them. Real people\'s faces are not used.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submit,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Create season plan'),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== screens/cost_panel_screen.dart =====
class CostPanelScreen extends StatefulWidget {
  const CostPanelScreen({super.key});

  @override
  State<CostPanelScreen> createState() => _CostPanelScreenState();
}

class _CostPanelScreenState extends State<CostPanelScreen> {
  static const int _stillCents = 5; // sample still-image cost (cents)
  double _budget = 450; // cent

  /// 0-1 knapsack: maximizes total importance without exceeding the budget.
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
        title: const Text('Cost and budget',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const Text(
            'A bigger budget turns more scenes into video. A 0-1 knapsack makes the choice: the most dramatic scenes get video first.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Text(
            'Episode video budget: ${usd(budget)}',
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
                (200, 'Low'),
                (450, 'Medium'),
                (900, 'High'),
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
              _stat('Video scenes', '$videoCount / ${kScenePlan.length}'),
              const SizedBox(width: 10),
              _stat('Importance', '$importance / $totalImportance'),
              const SizedBox(width: 10),
              _stat('Episode cost', usd(total)),
            ],
          ),
          const SizedBox(height: 20),
          Text('Scenes',
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
                          'importance ${kScenePlan[i].importance} · video ${usd(kScenePlan[i].videoCostCents)}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  pick[i] ? const Tag('VIDEO', kGold) : const Tag('STILL', kGrey),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Sample unit costs, not real prices. In the real app the numbers come from the episode_costs view.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ===== screens/home_screen.dart =====
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
        title: const Text('My series',
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
                          const Text('Voting open',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            '${vs.title} · after episode ${ve.number}',
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
                      child: const Text('Vote'),
                    ),
                  ],
                ),
              ),
            ),
          Text(
            'Your series',
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

// ===== screens/home_shell.dart =====
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  final List<Widget> _pages = const [
    HomeScreen(),
    CreateSeriesScreen(),
    CostPanelScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'My series',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Create',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings),
            label: 'Cost',
          ),
        ],
      ),
    );
  }
}

// ===== screens/login_screen.dart =====
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _consent = false;
  bool _hide = true;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _enter() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.movie_filter_rounded, size: 64, color: kGold),
                const SizedBox(height: 12),
                Text(
                  'Soap Opera Studio',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Write your own series with AI.\nLet viewers pick the next episode.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pass,
                  obscureText: _hide,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _consent,
                  onChanged: (v) => setState(() => _consent = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I have read the privacy notice and consent to the processing of my data (KVKK).',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _consent ? _enter : null,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Sign in'),
                  ),
                ),
                TextButton(
                  onPressed: _enter,
                  child: const Text('Browse as guest'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can delete your account at any time.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===== main.dart =====
void main() => runApp(const SoapOperaApp());

class SoapOperaApp extends StatelessWidget {
  const SoapOperaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Soap Opera Studio',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const LoginScreen(),
    );
  }
}
