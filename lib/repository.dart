import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data.dart';

/// Hata nesnesini kullanıcıya gösterilecek kısa metne çevirir.
String errText(Object e) {
  if (e is AuthException) return e.message;
  if (e is PostgrestException) return e.message;
  return e.toString().replaceFirst('Exception: ', '');
}

/// Tüm Supabase erişimi burada toplanır; ekranlar doğrudan Supabase'e dokunmaz.
class Repo {
  static SupabaseClient get _db => Supabase.instance.client;

  static bool get signedIn => _db.auth.currentUser != null;

  // ------------------------------------------------------------------ auth

  /// true dönerse oturum açıldı; false ise e-posta onayı bekleniyor.
  static Future<bool> signUp(String email, String password) async {
    final res = await _db.auth.signUp(email: email, password: password);
    return res.session != null;
  }

  static Future<void> signIn(String email, String password) async {
    await _db.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() => _db.auth.signOut();

  /// KVKK onay zamanını profile yazar.
  static Future<void> saveConsent() async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    await _db
        .from('profiles')
        .update({'consent_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', user.id);
  }

  // ---------------------------------------------------------------- series

  static const List<Color> _charColors = [
    Color(0xFFE6B450),
    Color(0xFF5AA9E6),
    Color(0xFFB06AB3),
    Color(0xFF4CAF7A),
  ];

  static List<Color> _seriesColors(String genre) {
    switch (genre) {
      case 'Romantik':
        return const [Color(0xFF1B5E8E), Color(0xFF0F1E2A)];
      case 'Gerilim':
        return const [Color(0xFF2A4A3A), Color(0xFF0F1A14)];
      case 'Komedi':
        return const [Color(0xFFB5651D), Color(0xFF2A1A0A)];
      default:
        return const [Color(0xFF8E1B3A), Color(0xFF2A0F1E)];
    }
  }

  static EpisodeStatus _status(String s) {
    switch (s) {
      case 'published':
        return EpisodeStatus.published;
      case 'generating':
        return EpisodeStatus.rendering;
      default:
        return EpisodeStatus.locked;
    }
  }

  static Series _fromRow(Map<String, dynamic> r) {
    final genre = (r['genre'] ?? '') as String;
    final chars = ((r['characters'] ?? []) as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();
    final eps = ((r['episodes'] ?? []) as List)
        .map((e) => e as Map<String, dynamic>)
        .toList();
    eps.sort((a, b) => (a['number'] as int).compareTo(b['number'] as int));

    return Series(
      id: r['id'] as String,
      title: (r['title'] ?? '') as String,
      genre: genre,
      setting: (r['setting'] ?? '') as String,
      colors: _seriesColors(genre),
      characters: [
        for (var i = 0; i < chars.length; i++)
          Character(
            (chars[i]['name'] ?? '') as String,
            (chars[i]['role'] ?? '') as String,
            _charColors[i % _charColors.length],
          ),
      ],
      episodes: [
        for (final e in eps)
          Episode(
            e['number'] as int,
            (e['title'] ?? 'Bölüm ${e['number']}') as String,
            (e['summary'] ?? '') as String,
            _status((e['status'] ?? 'draft') as String),
          ),
      ],
    );
  }

  /// Görünür tüm diziler: kullanıcının kendileri + yayınlanmış bölümü olanlar (RLS belirler).
  static Future<List<Series>> fetchSeries() async {
    final rows = await _db
        .from('series')
        .select('*, characters(*), episodes(*)')
        .order('created_at', ascending: false);
    return rows.map<Series>((r) => _fromRow(r)).toList();
  }

  static Future<void> createSeries({
    required String title,
    required String genre,
    required String setting,
    required List<String> names,
    required List<String> roles,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Önce giriş yapmalısın.');

    final s = await _db
        .from('series')
        .insert({
          'owner_id': user.id,
          'title': title,
          'genre': genre,
          'setting': setting,
        })
        .select()
        .single();

    await _db.from('characters').insert([
      for (var i = 0; i < names.length; i++)
        {'series_id': s['id'], 'name': names[i], 'role': roles[i]},
    ]);
  }
}
