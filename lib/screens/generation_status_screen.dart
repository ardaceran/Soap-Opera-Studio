import 'dart:async';
import 'package:flutter/material.dart';
import '../data.dart';
import '../theme.dart';
import 'episode_player_screen.dart';

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
