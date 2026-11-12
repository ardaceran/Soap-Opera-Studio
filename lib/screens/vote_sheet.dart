import 'dart:async';
import 'package:flutter/material.dart';
import '../data.dart';
import '../repository.dart';
import '../theme.dart';

/// Gerçek anket penceresi: oylar Supabase'e yazılır, sonuçlar 3 saniyede bir yenilenir.
Future<void> showVoteSheet(BuildContext context, PollInfo poll) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: kCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _VoteSheet(poll: poll),
  );
}

class _VoteSheet extends StatefulWidget {
  const _VoteSheet({required this.poll});
  final PollInfo poll;

  @override
  State<_VoteSheet> createState() => _VoteSheetState();
}

class _VoteSheetState extends State<_VoteSheet> {
  Map<String, int> _counts = {};
  String? _picked;
  bool _busy = false;
  String? _msg;
  Timer? _timer;

  bool get _closed => !widget.poll.closesAt.isAfter(DateTime.now());
  int get _total => _counts.values.fold<int>(0, (a, b) => a + b);

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final c = await Repo.fetchPollResults(widget.poll.id);
      final mine = Repo.signedIn ? await Repo.myVote(widget.poll.id) : null;
      if (!mounted) return;
      setState(() {
        _counts = c;
        _picked = mine;
      });
    } catch (_) {
      // Geçici ağ hatası: bir sonraki yenilemede tekrar denenir.
    }
  }

  Future<void> _vote(String optionId) async {
    if (_picked != null || _busy || _closed) return;
    if (!Repo.signedIn) {
      setState(() => _msg = 'Oy vermek için giriş yapmalısın.');
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await Repo.castVote(widget.poll.id, optionId);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _msg = errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _closesText() {
    final d = widget.poll.closesAt.difference(DateTime.now());
    if (d.isNegative) return 'Oylama kapandı';
    if (d.inDays >= 1) return 'Oylama ${d.inDays} gün ${d.inHours % 24} saat sonra kapanır';
    if (d.inHours >= 1) return 'Oylama ${d.inHours} saat ${d.inMinutes % 60} dk sonra kapanır';
    return 'Oylama ${d.inMinutes + 1} dk içinde kapanır';
  }

  Widget _tile(PollOption o) {
    final votes = _counts[o.id] ?? 0;
    final pct = _total == 0 ? 0.0 : votes / _total;
    final picked = _picked == o.id;
    final showResults = _picked != null || _closed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: (_picked != null || _busy || _closed) ? null : () => _vote(o.id),
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
                    child: Text(o.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (showResults)
                    Text('$votes oy · %${(pct * 100).round()}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              if (showResults) ...[
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
    final poll = widget.poll;
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
            '${poll.seriesTitle} · Bölüm ${poll.episodeNumber + 1} için oy ver',
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
          for (final o in poll.options) _tile(o),
          const SizedBox(height: 4),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_msg!,
                  style: TextStyle(color: Colors.red.shade300, fontSize: 13)),
            ),
          Text(
            _picked != null
                ? 'Oyun kaydedildi. Toplam $_total oy · sonuçlar canlı güncellenir. ${_closesText()}.'
                : '${_closesText()}. Her kullanıcı bir oy kullanabilir.',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
