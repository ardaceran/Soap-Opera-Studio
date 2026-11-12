import 'dart:async';
import 'package:flutter/material.dart';
import '../data.dart';
import '../repository.dart';
import '../theme.dart';

/// Shows the real generation jobs of a series from the `jobs` table.
/// Refreshes every 3 seconds while the screen is open.
class GenerationStatusScreen extends StatefulWidget {
  const GenerationStatusScreen(
      {super.key, required this.seriesId, required this.title});
  final String seriesId;
  final String title;

  @override
  State<GenerationStatusScreen> createState() => _GenerationStatusScreenState();
}

class _GenerationStatusScreenState extends State<GenerationStatusScreen> {
  List<JobInfo>? _jobs;
  String? _error;
  Timer? _timer;

  static const Map<String, String> _names = {
    'season_plan': 'Season plan',
    'script': 'Episode script',
    'moderation': 'Moderation',
    'image': 'Scene images',
    'video': 'Key-moment video',
    'voice': 'Voice',
    'assemble': 'Assembly (FFmpeg)',
  };

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final jobs = await Repo.fetchSeriesJobs(widget.seriesId);
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e));
    }
  }

  Widget _icon(String status) {
    switch (status) {
      case 'done':
        return const Icon(Icons.check_circle, color: kGreen);
      case 'running':
        return const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        );
      case 'failed':
        return Icon(Icons.error, color: Colors.red.shade300);
      default:
        return const Icon(Icons.schedule, color: kGrey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = _jobs;
    final waiting =
        jobs != null && jobs.isNotEmpty && jobs.every((j) => j.status == 'queued');
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Series saved',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Generation jobs for this series, live from the database.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 20),
          if (_error != null)
            Text('Could not load jobs: $_error',
                style: TextStyle(color: Colors.red.shade300))
          else if (jobs == null)
            const Center(child: CircularProgressIndicator())
          else if (jobs.isEmpty)
            const Text('No generation jobs yet.',
                style: TextStyle(color: Colors.white54))
          else
            for (final j in jobs)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _icon(j.status),
                title: Text(
                  '${_names[j.type] ?? j.type}'
                  '${j.episodeNumber != null ? ' · episode ${j.episodeNumber}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(j.error ?? j.status),
              ),
          if (waiting) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Waiting for the generation worker. Jobs stay queued until the worker is running.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
