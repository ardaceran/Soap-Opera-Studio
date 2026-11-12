import 'package:flutter/material.dart';
import 'data.dart';
import 'theme.dart';

String statusLabel(EpisodeStatus s) {
  switch (s) {
    case EpisodeStatus.published:
      return 'Yayında';
    case EpisodeStatus.voting:
      return 'Oylamada';
    case EpisodeStatus.rendering:
      return 'Üretiliyor';
    case EpisodeStatus.locked:
      return 'Kilitli';
  }
}

Color statusColor(EpisodeStatus s) {
  switch (s) {
    case EpisodeStatus.published:
      return kGreen;
    case EpisodeStatus.voting:
      return kGold;
    case EpisodeStatus.rendering:
      return kBlue;
    case EpisodeStatus.locked:
      return kGrey;
  }
}

class Tag extends StatelessWidget {
  const Tag(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(130)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar(this.character, {super.key, this.radius = 20});
  final Character character;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: character.color.withAlpha(60),
      child: Text(
        character.name.substring(0, 1),
        style: TextStyle(
          color: character.color,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}

class SeriesCard extends StatelessWidget {
  const SeriesCard({super.key, required this.series, required this.onTap});
  final Series series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final published = series.episodes
        .where((e) =>
            e.status == EpisodeStatus.published ||
            e.status == EpisodeStatus.voting)
        .length;
    return Card(
      color: kCard,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 170,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: series.colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tag(series.genre, Colors.white),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    series.title,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(series.setting,
                      style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final c in series.characters)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: CharacterAvatar(c, radius: 14),
                        ),
                      const Spacer(),
                      Text('$published bölüm yayında',
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
