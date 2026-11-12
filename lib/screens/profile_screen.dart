import 'package:flutter/material.dart';
import '../repository.dart';
import '../theme.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  Map<String, dynamic>? _profile;
  int _seriesCount = 0;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    if (!Repo.signedIn) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await Repo.fetchProfile();
      final c = await Repo.ownSeriesCount();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _seriesCount = c;
        _name.text = ((p?['display_name']) ?? '') as String;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errText(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveName() async {
    setState(() => _saving = true);
    try {
      await Repo.updateDisplayName(_name.text.trim());
      if (mounted) _snack('Display name saved.');
    } catch (e) {
      if (mounted) _snack(errText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _goLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _signOut() async {
    await Repo.signOut();
    if (mounted) _goLogin();
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account'),
        content: const Text(
          'Your account, series, characters and votes will be permanently deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.deleteAccount();
      if (mounted) _goLogin();
    } catch (e) {
      if (mounted) _snack(errText(e));
    }
  }

  String _consentText() {
    final raw = _profile?['consent_at'];
    if (raw == null) return 'No consent on record';
    final d = DateTime.parse(raw as String).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _card(String title, List<Widget> children) => Card(
        color: kCard,
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(label,
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (Repo.signedIn)
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (!Repo.signedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_outline, size: 48, color: kGrey),
              const SizedBox(height: 12),
              const Text(
                'You are browsing as a guest.\nSign in to create series and vote.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _goLogin, child: const Text('Sign in / Sign up')),
            ],
          ),
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load profile:\n$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final shownName = _name.text.trim().isNotEmpty
        ? _name.text.trim()
        : (Repo.email ?? '?');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: CircleAvatar(
            radius: 36,
            backgroundColor: kGold.withAlpha(50),
            child: Text(
              shownName.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                  color: kGold, fontSize: 30, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _card('Account', [
          _row('Email', Repo.email ?? '-'),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _saving ? null : _saveName,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Save'),
            ),
          ),
        ]),
        _card('My data and privacy (KVKK)', [
          _row('KVKK consent', _consentText()),
          _row('My series', '$_seriesCount'),
          const Text(
            'Only your email and display name are stored. Deleting your account also deletes your series, characters and votes.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ]),
        OutlinedButton.icon(
          onPressed: _signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade300,
            side: BorderSide(color: Colors.red.shade300),
          ),
          onPressed: _deleteAccount,
          icon: const Icon(Icons.delete_forever),
          label: const Text('Delete my account'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
