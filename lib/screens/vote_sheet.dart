import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import '../data.dart';
import '../repository.dart';
import '../theme.dart';

/// Real poll sheet: votes are written to Supabase and results refresh every 3 seconds.
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
  Timer? _tick; // redraws the countdown every second
  late DateTime _closesAt = widget.poll.closesAt;

  bool get _closed => !_closesAt.isAfter(DateTime.now());
  int get _total => _counts.values.fold<int>(0, (a, b) => a + b);

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final c = await Repo.fetchPollResults(widget.poll.id);
      final mine = Repo.signedIn ? await Repo.myVote(widget.poll.id) : null;
      final closes = await Repo.fetchPollClosesAt(widget.poll.id);
      if (!mounted) return;
      setState(() {
        _counts = c;
        _picked = mine;
        _closesAt = closes;
      });
    } catch (_) {
      // Temporary network error: retried on the next refresh.
    }
  }

  Future<void> _vote(String optionId) async {
    if (_picked != null || _busy || _closed) return;
    if (!Repo.signedIn) {
      // Live audience: vote without an account (anonymous guest session).
      final ok = await _askGuestConsent();
      if (!ok || !mounted) return;
      setState(() {
        _busy = true;
        _msg = null;
      });
      try {
        await Repo.joinAsGuest();
      } catch (e) {
        if (mounted) {
          setState(() {
            _busy = false;
            _msg = 'Guest voting is not available right now. Please sign in to vote.';
          });
        }
        return;
      }
      if (mounted) setState(() => _busy = false);
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

  /// Asks a viewer without an account to vote as a guest, with the KVKK consent.
  Future<bool> _askGuestConsent() async {
    var consent = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Vote as a guest'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No account needed. We create an anonymous guest session so '
                'each viewer has one vote. No email or name is stored.',
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: consent,
                onChanged: (v) => setLocal(() => consent = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'I have read the privacy notice and consent to the processing '
                  'of my data (KVKK).',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: consent ? () => Navigator.of(ctx).pop(true) : null,
              child: const Text('Vote'),
            ),
          ],
        ),
      ),
    );
    return ok ?? false;
  }

  /// "1 d 4 h", "2:05:09" or "04:37" until the vote closes.
  String _left() {
    final d = _closesAt.difference(DateTime.now());
    String two(int n) => n.toString().padLeft(2, '0');
    if (d.inDays >= 1) return '${d.inDays} d ${d.inHours % 24} h';
    if (d.inHours >= 1) {
      return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    }
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  Widget _countdown() {
    final closed = _closed;
    final urgent = !closed && _closesAt.difference(DateTime.now()).inSeconds < 60;
    final color = closed ? kGrey : (urgent ? Colors.red.shade300 : kGold);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Row(
        children: [
          Icon(closed ? Icons.lock_clock : Icons.timer_outlined, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              closed
                  ? 'Voting closed · the winning option writes the next episode'
                  : 'Voting closes in',
              style: TextStyle(color: closed ? Colors.white70 : Colors.white),
            ),
          ),
          if (!closed)
            Text(
              _left(),
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
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
                    Text('$votes votes · ${(pct * 100).round()}%',
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
            '${poll.seriesTitle} · Vote for episode ${poll.episodeNumber + 1}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'The winning option goes into the next episode\'s script.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          _countdown(),
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
                ? 'Your vote is saved. $_total votes in total · results update live.'
                : 'Each user can vote once.',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
