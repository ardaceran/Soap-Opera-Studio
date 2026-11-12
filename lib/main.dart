import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseKey);
  runApp(const SoapOperaApp());
}

class SoapOperaApp extends StatelessWidget {
  const SoapOperaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    return MaterialApp(
      title: 'Soap Opera Studio',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: loggedIn ? const HomeShell() : const LoginScreen(),
    );
  }
}
