import 'package:flutter/material.dart';

// Sample (mock) data. In the real app this comes from Supabase.

class Character {
  const Character(this.name, this.role, this.color);
  final String name;
  final String role;
  final Color color;
}

enum EpisodeStatus { published, voting, rendering, locked }

class Episode {
  const Episode(this.number, this.title, this.summary, this.status,
      {this.pollId, this.id});
  final String? id; // database id (null for mock episodes)
  final String? pollId; // poll at the end of the episode (if any)
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
  final int episodeNumber; // episode the poll opened on; the vote decides the next episode
  final DateTime closesAt;
  final List<PollOption> options;
}

class EpisodeCost {
  const EpisodeCost(
      {required this.seriesTitle, required this.number, required this.usd});
  final String seriesTitle;
  final int number;
  final double usd;
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
      Character('Kerem', 'Mysterious lawyer', Color(0xFF5AA9E6)),
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
