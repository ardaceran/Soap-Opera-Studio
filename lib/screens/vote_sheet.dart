import 'package:flutter/material.dart';
import '../theme.dart';

Future<void> showVoteSheet(
  BuildContext context, {
  required String seriesTitle,
  required int nextEpisode,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) =>
        _VoteSheet(seriesTitle: seriesTitle, nextEpisode: nextEpisode),
  );
}

class _VoteSheet extends StatefulWidget {
  const _VoteSheet({required this.seriesTitle, required this.nextEpisode});
  final String seriesTitle;
  final int nextEpisode;

  @override
  State<_VoteSheet> createState() => _VoteSheetState();
}

class _VoteSheetState extends State<_VoteSheet> {
  final List<String> _options = const [
    'Defne mektubu yakar',
    "Defne mektubu Kerem'e verir",
    'Nilüfer mektubu çalar',
  ];
  final List<int> _votes = [41, 33, 26];
  int? _picked;

  int get _total => _votes.fold<int>(0, (a, b) => a + b);

  Widget _tile(int i) {
    final pct = _total == 0 ? 0.0 : _votes[i] / _total;
    final picked = _picked == i;
    final voted = _picked != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: voted
            ? null
            : () => setState(() {
                  _picked = i;
                  _votes[i] = _votes[i] + 1;
                }),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: picked ? kGold : Colors.white24,
              width: picked ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _options[i],
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (voted)
                    Text(
                      '%${(pct * 100).round()}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                ],
              ),
              if (voted) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: Colors.white12,
                    color: picked ? kGold : Colors.white54,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${widget.seriesTitle} · Bölüm ${widget.nextEpisode} için oy ver',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Kazanan seçenek bir sonraki bölümün senaryosuna girer.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _options.length; i++) _tile(i),
          const SizedBox(height: 4),
          Text(
            _picked == null
                ? 'Her kullanıcı bir oy kullanabilir.'
                : 'Oyun kaydedildi. Sonuçlar canlı güncellenir. (örnek veri)',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
