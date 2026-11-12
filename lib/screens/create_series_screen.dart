import 'package:flutter/material.dart';
import '../theme.dart';
import 'generation_status_screen.dart';

class CreateSeriesScreen extends StatefulWidget {
  const CreateSeriesScreen({super.key});

  @override
  State<CreateSeriesScreen> createState() => _CreateSeriesScreenState();
}

class _CreateSeriesScreenState extends State<CreateSeriesScreen> {
  static const _genres = ['Dram', 'Romantik', 'Gerilim', 'Komedi'];
  static const _settings = [
    'İzmir villası',
    'Hastane',
    'Holding',
    'Köy konağı',
  ];
  static const _roles = ['Kahraman', 'Kötü', 'Gizemli', 'Komik'];

  final _title = TextEditingController();
  String _genre = 'Dram';
  String _setting = 'İzmir villası';
  final List<TextEditingController> _names = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<String> _charRoles = ['Kahraman', 'Gizemli'];

  @override
  void dispose() {
    _title.dispose();
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  void _addCharacter() {
    setState(() {
      _names.add(TextEditingController());
      _charRoles.add('Kötü');
    });
  }

  void _removeCharacter(int i) {
    setState(() {
      _names[i].dispose();
      _names.removeAt(i);
      _charRoles.removeAt(i);
    });
  }

  void _submit() {
    final named = _names.where((c) => c.text.trim().isNotEmpty).length;
    if (_title.text.trim().isEmpty || named < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dizi adı ve en az 2 karakter adı gerekli.'),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GenerationStatusScreen(title: _title.text.trim()),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni dizi',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Dizi adı',
              hintText: 'Örn. Kırmızı Villa',
              border: OutlineInputBorder(),
            ),
          ),
          _label('Tür'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in _genres)
                ChoiceChip(
                  label: Text(g),
                  selected: _genre == g,
                  onSelected: (_) => setState(() => _genre = g),
                ),
            ],
          ),
          _label('Mekân'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _settings)
                ChoiceChip(
                  label: Text(s),
                  selected: _setting == s,
                  onSelected: (_) => setState(() => _setting = s),
                ),
            ],
          ),
          _label('Karakterler (2–4)'),
          for (var i = 0; i < _names.length; i++)
            Card(
              color: kCard,
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _names[i],
                        decoration: InputDecoration(
                          labelText: 'Karakter ${i + 1}',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: _charRoles[i],
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final r in _roles)
                          DropdownMenuItem<String>(value: r, child: Text(r)),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _charRoles[i] = v);
                      },
                    ),
                    if (_names.length > 2)
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => _removeCharacter(i),
                      ),
                  ],
                ),
              ),
            ),
          if (_names.length < 4)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addCharacter,
                icon: const Icon(Icons.add),
                label: const Text('Karakter ekle'),
              ),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, color: kGold, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Karakterler için referans görseller üretilir ve sen onaylarsın. Gerçek kişi yüzü kullanılmaz.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submit,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Sezon planını oluştur'),
            ),
          ),
        ],
      ),
    );
  }
}
