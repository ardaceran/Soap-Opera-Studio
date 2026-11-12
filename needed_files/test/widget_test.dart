// Small tests that run without Supabase.
import 'package:flutter_test/flutter_test.dart';
import 'package:soap_opera_studio/data.dart';
import 'package:soap_opera_studio/widgets.dart';

void main() {
  test('every episode status has a label', () {
    for (final s in EpisodeStatus.values) {
      expect(statusLabel(s), isNotEmpty);
    }
  });

  test('voting episodes are labelled Voting', () {
    expect(statusLabel(EpisodeStatus.voting), 'Voting');
  });
}
