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

  // --------------------------------------------------------------- profile

  static String? get email => _db.auth.currentUser?.email;

  static Future<Map<String, dynamic>?> fetchProfile() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    return await _db.from('profiles').select().eq('id', user.id).maybeSingle();
  }

  static Future<void> updateDisplayName(String name) async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    await _db.from('profiles').update({'display_name': name}).eq('id', user.id);
  }

  static Future<int> ownSeriesCount() async {
    final user = _db.auth.currentUser;
    if (user == null) return 0;
    final rows = await _db.from('series').select('id').eq('owner_id', user.id);
    return rows.length;
  }

  /// Hesabı ve tüm verilerini kalıcı siler (supabase/002_delete_account.sql gerekir).
  static Future<void> deleteAccount() async {
    await _db.rpc('delete_my_account');
    try {
      await _db.auth.signOut();
    } catch (_) {
      // Kullanıcı zaten silindi; yerel oturumu temizlemek yeterli.
    }
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

  static Episode _episodeFrom(Map<String, dynamic> e) {
    // Bölümün anketi: tekil nesne ya da liste olarak gelebilir.
    Map<String, dynamic>? poll;
    final raw = e['polls'];
    if (raw is Map) {
      poll = Map<String, dynamic>.from(raw);
    } else if (raw is List && raw.isNotEmpty) {
      poll = Map<String, dynamic>.from(raw.first as Map);
    }
    var status = _status((e['status'] ?? 'draft') as String);
    if (status == EpisodeStatus.published && poll != null) {
      final closes = DateTime.parse(poll['closes_at'] as String);
      if (closes.isAfter(DateTime.now())) status = EpisodeStatus.voting;
    }
    return Episode(
      e['number'] as int,
      (e['title'] ?? 'Bölüm ${e['number']}') as String,
      (e['summary'] ?? '') as String,
      status,
      pollId: poll?['id'] as String?,
    );
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
      episodes: [for (final e in eps) _episodeFrom(e)],
    );
  }

  /// Görünür tüm diziler: kullanıcının kendileri + yayınlanmış bölümü olanlar (RLS belirler).
  static Future<List<Series>> fetchSeries() async {
    final rows = await _db
        .from('series')
        .select('*, characters(*), episodes(*, polls(id, closes_at))')
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

  // ----------------------------------------------------------------- polls

  static const String _pollSelect =
      'id, closes_at, poll_options(id, label), episodes(number, series(title))';

  static PollInfo _pollFrom(Map<String, dynamic> r) {
    final ep = Map<String, dynamic>.from(r['episodes'] as Map);
    final sr = Map<String, dynamic>.from(ep['series'] as Map);
    final opts = (r['poll_options'] as List)
        .map((o) => PollOption(o['id'] as String, o['label'] as String))
        .toList();
    return PollInfo(
      id: r['id'] as String,
      seriesTitle: (sr['title'] ?? '') as String,
      episodeNumber: ep['number'] as int,
      closesAt: DateTime.parse(r['closes_at'] as String),
      options: opts,
    );
  }

  /// Şu an açık olan anketler.
  static Future<List<PollInfo>> fetchOpenPolls() async {
    final rows = await _db
        .from('polls')
        .select(_pollSelect)
        .gt('closes_at', DateTime.now().toUtc().toIso8601String())
        .order('closes_at');
    return rows.map<PollInfo>((r) => _pollFrom(r)).toList();
  }

  static Future<PollInfo> fetchPollById(String id) async {
    final r = await _db.from('polls').select(_pollSelect).eq('id', id).single();
    return _pollFrom(r);
  }

  /// seçenek id -> oy sayısı
  static Future<Map<String, int>> fetchPollResults(String pollId) async {
    final rows = await _db
        .from('poll_results')
        .select('option_id, votes')
        .eq('poll_id', pollId);
    return {
      for (final r in rows)
        r['option_id'] as String: (r['votes'] as num).toInt(),
    };
  }

  /// Kullanıcının bu ankette verdiği seçenek (yoksa null).
  static Future<String?> myVote(String pollId) async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    final r = await _db
        .from('votes')
        .select('option_id')
        .eq('poll_id', pollId)
        .eq('user_id', user.id)
        .maybeSingle();
    return r?['option_id'] as String?;
  }

  static Future<void> castVote(String pollId, String optionId) async {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Oy vermek için giriş yapmalısın.');
    try {
      await _db.from('votes').insert({
        'poll_id': pollId,
        'user_id': user.id,
        'option_id': optionId,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('Bu ankette zaten oy kullandın.');
      }
      rethrow;
    }
  }
}
