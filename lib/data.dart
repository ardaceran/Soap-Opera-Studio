import 'package:flutter/material.dart';

// App data models. All data comes from Supabase (see repository.dart).

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
  final String? id; // database id
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

class JobInfo {
  const JobInfo(
      {required this.type,
      required this.status,
      this.error,
      this.episodeNumber});
  final String type; // season_plan, script, image, video, voice, assemble, moderation
  final String status; // queued, running, done, failed
  final String? error;
  final int? episodeNumber;
}

class Series {
  const Series({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.genre,
    required this.setting,
    required this.colors,
    required this.characters,
    required this.episodes,
  });
  final String id;
  final String ownerId;
  final String title;
  final String genre;
  final String setting;
  final List<Color> colors;
  final List<Character> characters;
  final List<Episode> episodes;
}
