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

// Mimarideki 8 adımlı üretim hattı (gerçekte worker yapar, uygulama sadece durumu izler).
const List<_Step> _steps = [
  _Step('Sezon planı', 'Claude sezon arkını ve dizi bible\'ını yazıyor'),
  _Step('Karakter kilidi', 'Referans görseller üretiliyor'),
  _Step('Bölüm senaryosu', 'Bağlam çekiliyor, sahneler yazılıyor'),
  _Step('Moderasyon', 'İçerik kuralları kontrol ediliyor'),
  _Step('Bütçe kararı', 'Hangi sahneler video olacak? (knapsack)'),
  _Step('Sahne medyası', 'Görsel, video ve ses üretiliyor'),
  _Step('Montaj', 'FFmpeg ile 1080×1920 video birleştiriliyor'),
  _Step('Yayın', 'Bölüm yayınlanıyor, oylama açılıyor'),
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
            finished ? 'Bölüm 1 hazır' : 'Üretim sürüyor...',
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
              label: const Text('Bölümü izle'),
            ),
          const SizedBox(height: 16),
          const Text(
            'Gerçek uygulamada bu ekran, Supabase Realtime ile jobs tablosunun durumunu dinler. Şimdilik simülasyon.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
