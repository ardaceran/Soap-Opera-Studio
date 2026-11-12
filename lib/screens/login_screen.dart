import 'package:flutter/material.dart';
import '../repository.dart';
import '../theme.dart';
import 'home_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _signup = false;
  bool _consent = false;
  bool _hide = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _enter() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeShell()),
    );
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final pass = _pass.text;
    if (email.isEmpty || pass.length < 6) {
      _snack('E-posta gir ve en az 6 karakterli bir şifre yaz.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_signup) {
        final hasSession = await Repo.signUp(email, pass);
        if (!hasSession) {
          if (mounted) {
            setState(() => _signup = false);
            _snack('Kayıt oluştu. E-postandaki onay linkine tıkla, sonra giriş yap.');
          }
          return;
        }
        await Repo.saveConsent();
      } else {
        await Repo.signIn(email, pass);
      }
      if (mounted) _enter();
    } catch (e) {
      if (mounted) _snack(errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_busy && (!_signup || _consent);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.movie_filter_rounded, size: 64, color: kGold),
                const SizedBox(height: 12),
                Text(
                  'Soap Opera Studio',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Yapay zekâ ile kendi dizini yaz.\nİzleyiciler bir sonraki bölümü seçsin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    prefixIcon: Icon(Icons.mail_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pass,
                  obscureText: _hide,
                  decoration: InputDecoration(
                    labelText: 'Şifre (en az 6 karakter)',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                ),
                if (_signup)
                  CheckboxListTile(
                    value: _consent,
                    onChanged: (v) => setState(() => _consent = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Gizlilik bildirimini okudum, verilerimin işlenmesini onaylıyorum (KVKK).',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: canSubmit ? _submit : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Text(_signup ? 'Kayıt ol' : 'Giriş yap'),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _signup = !_signup),
                  child: Text(_signup
                      ? 'Zaten hesabın var mı? Giriş yap'
                      : 'Hesabın yok mu? Kayıt ol'),
                ),
                TextButton(
                  onPressed: _busy ? null : _enter,
                  child: const Text('Misafir olarak izle'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hesabını istediğin zaman silebilirsin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
