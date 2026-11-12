import 'package:flutter/material.dart';
import '../data.dart';
import '../repository.dart';
import '../theme.dart';

/// The series owner writes an episode by hand: title, summary, one dialogue
/// line per scene, and an optional poll for the next episode.
/// Returns true to the caller when the episode was saved.
class AddEpisodeScreen extends StatefulWidget {
  const AddEpisodeScreen({super.key, required this.series});
  final Series series;

  @override
  State<AddEpisodeScreen> createState() => _AddEpisodeScreenState();
}

class _AddEpisodeScreenState extends State<AddEpisodeScreen> {
  final _title = TextEditingController();
  final _summary = TextEditingController();
  final _lines = TextEditingController();
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _poll = true;
  int _hours = 24;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _lines.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final lines = _lines.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final options = _poll
        ? _options
            .map((c) => c.text.trim())
            .where((t) => t.isNotEmpty)
            .toList()
        : <String>[];
    if (title.isEmpty) {
      _snack('Enter an episode title.');
      return;
    }
    if (lines.isEmpty) {
      _snack('Write at least one scene line.');
      return;
    }
    if (_poll && options.length < 2) {
      _snack('A poll needs at least 2 options (or turn the poll off).');
      return;
    }
    setState(() => _saving = true);
    try {
      await Repo.addEpisode(
        seriesId: widget.series.id,
        title: title,
        summary: _summary.text.trim(),
        lines: lines,
        pollOptions: options,
        pollHours: _hours,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _snack(errText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    final next = widget.series.episodes.length + 1;
    final names = widget.series.characters.map((c) => c.name).join(', ');
    return Scaffold(
      appBar: AppBar(title: Text('${widget.series.title} · Episode $next')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Episode title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _summary,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Summary (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          _label('Scenes'),
          Text(
            'One line per scene, as "Name: what they say".'
            '${names.isEmpty ? '' : ' Characters: $names.'}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _lines,
            minLines: 6,
            maxLines: 14,
            decoration: const InputDecoration(
              hintText: 'Defne: My father\'s will is read today.\n'
                  'Kerem: Nobody was supposed to find the letter.',
              border: OutlineInputBorder(),
            ),
          ),
          _label('Poll for the next episode'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _poll,
            onChanged: (v) => setState(() => _poll = v),
            title: const Text('Let viewers vote on what happens next'),
          ),
          if (_poll) ...[
            for (var i = 0; i < _options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _options[i],
                        decoration: InputDecoration(
                          labelText: 'Option ${i + 1}',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_options.length > 2)
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => setState(() {
                          _options[i].dispose();
                          _options.removeAt(i);
                        }),
                      ),
                  ],
                ),
              ),
            if (_options.length < 4)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _options.add(TextEditingController())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add option'),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Voting stays open for'),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: _hours,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 hour')),
                    DropdownMenuItem(value: 24, child: Text('1 day')),
                    DropdownMenuItem(value: 72, child: Text('3 days')),
                    DropdownMenuItem(value: 168, child: Text('7 days')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _hours = v);
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'The episode is published right away. Later the AI worker will write episodes for you.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Publish episode'),
            ),
          ),
        ],
      ),
    );
  }
}
