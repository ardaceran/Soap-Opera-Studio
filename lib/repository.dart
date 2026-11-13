import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data.dart';

/// Turns an error object into a short message for the user.
String errText(Object e) {
  if (e is AuthException) return e.message;
  if (e is PostgrestException) return e.message;
  return e.toString().replaceFirst('Exception: ', '');
}

/// All Supabase access lives here; screens never touch Supabase directly.
class Repo {
  static SupabaseClient get _db => Supabase.instance.client;

  static bool get signedIn => _db.auth.currentUser != null;

  // ------------------------------------------------------------------ auth

  /// true: signed in; false: waiting for email confirmation.
  /// The KVKK consent travels as metadata; the database trigger stores its time.
  static Future<bool> signUp(String email, String password) async {
    final res = await _db.auth.signUp(
      email: email,
      password: password,
      data: {'kvkk_consent': true},
    );
    return res.session != null;
  }

  static Future<void> signIn(String email, String password) async {
    await _db.auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() => _db.auth.signOut();

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

  /// Permanently deletes the account and all its data (needs supabase/002_delete_account.sql).
  static Future<void> deleteAccount() async {
    await _db.rpc('delete_my_account');
    try {
      await _db.auth.signOut();
    } catch (_) {
      // The user is already deleted; clearing the local session is enough.
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
      case 'Romance':
      case 'Romantik':
        return const [Color(0xFF1B5E8E), Color(0xFF0F1E2A)];
      case 'Thriller':
      case 'Gerilim':
        return const [Color(0xFF2A4A3A), Color(0xFF0F1A14)];
      case 'Comedy':
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
    // The episode's poll: may arrive as a single object or a list.
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
      (e['title'] ?? 'Episode ${e['number']}') as String,
      (e['summary'] ?? '') as String,
      status,
      pollId: poll?['id'] as String?,
      id: e['id'] as String?,
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
      ownerId: r['owner_id'] as String,
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

  /// All visible series: the user's own plus those with published episodes (decided by RLS).
  static String? get userId => _db.auth.currentUser?.id;

  static Future<Series> fetchSeriesById(String id) async {
    final r = await _db
        .from('series')
        .select('*, characters(*), episodes(*, polls(id, closes_at))')
        .eq('id', id)
        .single();
    return _fromRow(r);
  }

  /// Owner adds a published episode with its scenes and an optional poll
  /// (supabase function add_episode). Returns the episode id.
  static Future<String> addEpisode({
    required String seriesId,
    required String title,
    required String summary,
    required List<String> lines,
    required List<String> pollOptions,
    required int pollHours,
  }) async {
    final id = await _db.rpc('add_episode', params: {
      'p_series_id': seriesId,
      'p_title': title,
      'p_summary': summary,
      'p_lines': lines,
      'p_poll_options': pollOptions,
      'p_poll_hours': pollHours,
    });
    return id as String;
  }

  static Future<List<Series>> fetchSeries() async {
    final rows = await _db
        .from('series')
        .select('*, characters(*), episodes(*, polls(id, closes_at))')
        .order('created_at', ascending: false);
    return rows.map<Series>((r) => _fromRow(r)).toList();
  }

  /// Saves the series, its characters and the first generation job in one
  /// transaction (supabase function create_series). Returns the series id.
  static Future<String> createSeries({
    required String title,
    required String genre,
    required String setting,
    required List<String> names,
    required List<String> roles,
  }) async {
    if (_db.auth.currentUser == null) {
      throw Exception('You need to sign in first.');
    }
    final id = await _db.rpc('create_series', params: {
      'p_title': title,
      'p_genre': genre,
      'p_setting': setting,
      'p_characters': [
        for (var i = 0; i < names.length; i++)
          {'name': names[i], 'role': roles[i]},
      ],
    });
    return id as String;
  }

  /// Generation jobs of a series, oldest first (only the owner can see them).
  static Future<List<JobInfo>> fetchSeriesJobs(String seriesId) async {
    final rows = await _db
        .from('jobs')
        .select('type, status, error, episodes(number)')
        .eq('series_id', seriesId)
        .order('created_at');
    return [
      for (final r in rows)
        JobInfo(
          type: r['type'] as String,
          status: r['status'] as String,
          error: r['error'] as String?,
          episodeNumber: (r['episodes'] as Map?)?['number'] as int?,
        ),
    ];
  }

  // ----------------------------------------------------------------- polls

  static const String _pollSelect =
      // polls <-> poll_options has two links (options of a poll, and the poll's
      // winner); the !hint picks "options of this poll".
      'id, closes_at, poll_options!poll_options_poll_id_fkey(id, label), '
      'episodes(number, series(title))';

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

  /// Polls that are open right now.
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

  /// option id -> vote count
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

  /// The option the user picked in this poll (null if none).
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
    if (user == null) throw Exception('You need to sign in to vote.');
    try {
      await _db.from('votes').insert({
        'poll_id': pollId,
        'user_id': user.id,
        'option_id': optionId,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('You already voted in this poll.');
      }
      rethrow;
    }
  }

  // ----------------------------------------------------- scenes and costs

  /// Scenes of an episode in order: (dialogue, visual prompt).
  static Future<List<({String dialogue, String visual})>> fetchScenes(
      String episodeId) async {
    final rows = await _db
        .from('scenes')
        .select('idx, dialogue, visual_prompt')
        .eq('episode_id', episodeId)
        .order('idx');
    return [
      for (final r in rows)
        (
          dialogue: (r['dialogue'] ?? '') as String,
          visual: (r['visual_prompt'] ?? '') as String,
        ),
    ];
  }

  /// Real cost per episode (USD) from the episode_costs view; only your own series.
  static Future<List<EpisodeCost>> fetchEpisodeCosts() async {
    final rows = await _db
        .from('episode_costs')
        .select('number, cost_usd, series(title)')
        .order('number');
    return [
      for (final r in rows)
        EpisodeCost(
          seriesTitle: ((r['series'] as Map?)?['title'] ?? '') as String,
          number: r['number'] as int,
          usd: (r['cost_usd'] as num).toDouble(),
        ),
    ];
  }
}
