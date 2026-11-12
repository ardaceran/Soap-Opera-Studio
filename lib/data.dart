import 'package:flutter/material.dart';

// Örnek (mock) veri. Gerçek uygulamada bu veriler Supabase'den gelecek.

class Character {
  const Character(this.name, this.role, this.color);
  final String name;
  final String role;
  final Color color;
}

enum EpisodeStatus { published, voting, rendering, locked }

class Episode {
  const Episode(this.number, this.title, this.summary, this.status,
      {this.pollId});
  final String? pollId; // bölümün sonundaki anket (varsa)
  final int number;
  final String title;
  final String summary;
  final EpisodeStatus status;
}

class PollOption {
  const PollOption(this.id, this.label);
  final String id;
  final String label;
}

class PollInfo {
  const PollInfo({
    required this.id,
    required this.seriesTitle,
    required this.episodeNumber,
    required this.closesAt,
    required this.options,
  });
  final String id;
  final String seriesTitle;
  final int episodeNumber; // anketin açıldığı bölüm; oy sonraki bölüm için
  final DateTime closesAt;
  final List<PollOption> options;
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

/// Maliyet ekranındaki knapsack örneği için sahne planı.
class ScenePlan {
  const ScenePlan(this.title, this.importance, this.videoCostCents);
  final String title;
  final int importance; // 1-10 dramatik önem
  final int videoCostCents; // örnek video maliyeti (cent)
}

const List<Series> kSeries = [
  Series(
    id: 's1',
    title: 'Kırmızı Villa',
    genre: 'Dram · Entrika',
    setting: 'İzmir, deniz kenarı villası',
    colors: [Color(0xFF8E1B3A), Color(0xFF2A0F1E)],
    characters: [
      Character('Defne', 'Villanın varisi', Color(0xFFE6B450)),
      Character('Kerem', 'Gizemli avukat', Color(0xFF5AA9E6)),
      Character('Nilüfer', 'Üvey anne', Color(0xFFB06AB3)),
    ],
    episodes: [
      Episode(1, 'Vasiyet', 'Defne babasının vasiyeti için villaya döner.',
          EpisodeStatus.published),
      Episode(2, 'Kapalı Oda', 'Kilitli odada eski bir mektup bulunur.',
          EpisodeStatus.voting),
      Episode(3, 'Sır', 'Mektubun sahibi ortaya çıkar.',
          EpisodeStatus.rendering),
      Episode(4, 'Yüzleşme', 'Aile akşam yemeğinde hesaplaşır.',
          EpisodeStatus.locked),
      Episode(5, 'Final', 'Sezonun büyük sırrı açığa çıkar.',
          EpisodeStatus.locked),
    ],
  ),
  Series(
    id: 's2',
    title: 'Son Vapur',
    genre: 'Romantik · Dram',
    setting: 'Karşıyaka iskelesi',
    colors: [Color(0xFF1B5E8E), Color(0xFF0F1E2A)],
    characters: [
      Character('Ece', 'Gemi kaptanının kızı', Color(0xFFE6B450)),
      Character('Barış', 'Genç gazeteci', Color(0xFF4CAF7A)),
    ],
    episodes: [
      Episode(1, 'İlk Sefer', 'Ece ve Barış vapurda tanışır.',
          EpisodeStatus.published),
      Episode(2, 'Sis', 'Sisli bir akşam planlar değişir.',
          EpisodeStatus.locked),
      Episode(3, 'Mektup', 'Eski bir sır iskeleye ulaşır.',
          EpisodeStatus.locked),
    ],
  ),
];

const List<ScenePlan> kScenePlan = [
  ScenePlan('Villa kapısında sürpriz misafir', 6, 90),
  ScenePlan('Kahvaltı sofrasında gergin bakışlar', 3, 70),
  ScenePlan('Mektubun bulunması', 8, 110),
  ScenePlan('Merdivende yüzleşme', 9, 120),
  ScenePlan('Telefon konuşması', 2, 60),
  ScenePlan('Bahçede gizli buluşma', 7, 100),
  ScenePlan('Vasiyetin okunması', 8, 110),
  ScenePlan('Sessiz akşam yemeği', 3, 70),
  ScenePlan('Cliffhanger: kapı açılır', 10, 130),
  ScenePlan('Geçmişe dönüş sahnesi', 5, 90),
];
