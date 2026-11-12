import 'package:flutter/material.dart';
import '../data.dart';
import '../repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'login_screen.dart';
import 'series_detail_screen.dart';
import 'vote_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  late Future<List<Series>> _future = Repo.fetchSeries();
  late Future<List<PollInfo>> _polls = Repo.fetchOpenPolls();

  /// Refreshes the list from outside (e.g. after a series is created).
  void reload() {
    setState(() {
      _future = Repo.fetchSeries();
      _polls = Repo.fetchOpenPolls();
    });
  }

  Widget _pollBanner() {
    return FutureBuilder<List<PollInfo>>(
      future: _polls,
      builder: (context, snap) {
        final polls = snap.data ?? const <PollInfo>[];
        if (polls.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            for (final p in polls)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: kGold.withAlpha(30),
                child: ListTile(
                  leading: const Icon(Icons.how_to_vote, color: kGold),
                  title: Text(
                    '${p.seriesTitle}: voting is open for episode ${p.episodeNumber + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('You decide the next episode'),
                  trailing: FilledButton(
                    onPressed: () => showVoteSheet(context, p),
                    child: const Text('Vote'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _signOut() async {
    await Repo.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  void _goLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Series',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: reload,
          ),
          if (Repo.signedIn)
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: _signOut,
            )
          else
            IconButton(
              tooltip: 'Sign in',
              icon: const Icon(Icons.login),
              onPressed: _goLogin,
            ),
        ],
      ),
      body: FutureBuilder<List<Series>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load series:\n${errText(snap.error!)}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: reload, child: const Text('Try again')),
                  ],
                ),
              ),
            );
          }
          final list = snap.data ?? const <Series>[];
          if (list.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _pollBanner(),
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Text(
                    'No series yet.\nCreate your first one from the Create tab.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _pollBanner(),
              for (final s in list)
                SeriesCard(
                  series: s,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SeriesDetailScreen(series: s),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
