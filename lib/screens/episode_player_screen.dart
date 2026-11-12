import 'package:flutter/material.dart';
import '../data.dart';
import '../repository.dart';
import '../theme.dart';
import 'vote_sheet.dart';

class _PlayerScene {
  const _PlayerScene(this.speaker, this.caption, this.colors);
  final String speaker;
  final String caption;
  final List<Color> colors;
}

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
  bool _loading = true;
  String? _error;
  List<_PlayerScene> _list = const [];

  static const List<List<Color>> _palette = [
    [Color(0xFF8E1B3A), Color(0xFF2A0F1E)],
    [Color(0xFF6A2C70), Color(0xFF1A0F22)],
    [Color(0xFF1B5E8E), Color(0xFF0F1E2A)],
    [Color(0xFF2A4A3A), Color(0xFF0F1A14)],
  ];

  /// "Defne: Hello" -> speaker "Defne", caption "Hello".
  _PlayerScene _fromRow(int i, String dialogue) {
    final k = dialogue.indexOf(':');
    final hasSpeaker = k > 0 && k < 24;
    return _PlayerScene(
      hasSpeaker ? dialogue.substring(0, k).trim() : 'Narrator',
      hasSpeaker ? dialogue.substring(k + 1).trim() : dialogue,
      _palette[i % _palette.length],
    );
  }

  Future<void> _loadScenes(String id) async {
    try {
      final rows = await Repo.fetchScenes(id);
      _list = [
        for (var i = 0; i < rows.length; i++) _fromRow(i, rows[i].dialogue),
      ];
    } catch (e) {
      _error = errText(e);
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (_list.isNotEmpty) {
      _c.duration = Duration(seconds: _list.length * 4);
      _c.forward();
    }
  }

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          !_voteShown &&
          widget.episode.pollId != null) {
        _voteShown = true;
        _openVote();
      }
    });
    final id = widget.episode.id;
    if (id != null) {
      _loadScenes(id);
    } else {
      _loading = false;
    }
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
    final pid = widget.episode.pollId;
    if (pid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'This episode has no poll.'),
      ));
    } else {
      try {
        final poll = await Repo.fetchPollById(pid);
        if (!mounted) return;
        await showVoteSheet(context, poll);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(errText(e))));
        }
      }
    }
    if (mounted && !_paused && _c.value < 1) {
      _c.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_list.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text('${widget.series.title} · E${widget.episode.number}'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error != null
                  ? 'Could not load scenes:\n$_error'
                  : 'This episode has no scenes yet. They appear here once the episode is generated.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }
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
                  final total = _list.length;
                  final t = _c.value * total;
                  final idx = t.floor().clamp(0, total - 1);
                  final local = (t - idx).clamp(0.0, 1.0);
                  final scene = _list[idx];
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
                        if (widget.episode.pollId != null)
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
