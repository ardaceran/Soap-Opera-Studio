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

// Örnek sahneler. Gerçekte her sahne bir Flux görseli / video klibi + ses olacak.
const List<_PlayerScene> _scenes = [
  _PlayerScene('Defne', 'Babamın vasiyeti bu odada okunacak.',
      [Color(0xFF8E1B3A), Color(0xFF2A0F1E)]),
  _PlayerScene('Nilüfer', 'Bu villa yıllardır benim evim.',
      [Color(0xFF6A2C70), Color(0xFF1A0F22)]),
  _PlayerScene('Kerem', 'Mektubu kimse bulmamalıydı.',
      [Color(0xFF1B5E8E), Color(0xFF0F1E2A)]),
  _PlayerScene('Defne', 'Demek her şeyi biliyordun.',
      [Color(0xFF8E1B3A), Color(0xFF3A1A0A)]),
  _PlayerScene('Nilüfer', 'Gece yarısı bahçede görüşelim.',
      [Color(0xFF2A4A3A), Color(0xFF0F1A14)]),
  _PlayerScene('Anlatıcı', 'Kapı yavaşça açıldı...',
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
    final pid = widget.episode.pollId;
    if (pid == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Bu örnek bölümün gerçek bir anketi yok. Diziler sekmesindeki anket bandından oy verebilirsin.'),
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
                        // Ken Burns: sabit görsel üzerinde yavaş yakınlaşma
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
                        // sahne ilerleme çubukları
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
                                'AI ile üretildi · ${widget.series.title} B${widget.episode.number}',
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
                        // altyazı
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
                            label: const Text('Sonraki bölüm için oy ver'),
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
