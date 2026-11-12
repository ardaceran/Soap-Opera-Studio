import 'package:flutter/material.dart';
import '../data.dart';
import '../repository.dart';
import '../widgets.dart';
import 'login_screen.dart';
import 'series_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  late Future<List<Series>> _future = Repo.fetchSeries();

  /// Dışarıdan (ör. dizi oluşturulunca) listeyi yeniler.
  void reload() {
    setState(() {
      _future = Repo.fetchSeries();
    });
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
        title: const Text('Diziler',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh),
            onPressed: reload,
          ),
          if (Repo.signedIn)
            IconButton(
              tooltip: 'Çıkış yap',
              icon: const Icon(Icons.logout),
              onPressed: _signOut,
            )
          else
            IconButton(
              tooltip: 'Giriş yap',
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
                      'Diziler yüklenemedi:\n${errText(snap.error!)}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: reload, child: const Text('Tekrar dene')),
                  ],
                ),
              ),
            );
          }
          final list = snap.data ?? const <Series>[];
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Henüz dizi yok.\nOluştur sekmesinden ilk dizini yarat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
