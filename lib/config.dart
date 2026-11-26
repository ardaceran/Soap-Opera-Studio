// Supabase client settings.
// The publishable (anon) key is designed to ship inside the app; it is not secret.
// Security is enforced by RLS policies. NEVER put the service_role / secret key here.
//
// A build can point at another Supabase project (e.g. a demo project) with
//   flutter build web --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
const String kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://iifzkjjwmagjcfcdfmof.supabase.co',
);
const String kSupabaseKey = String.fromEnvironment(
  'SUPABASE_KEY',
  defaultValue: 'sb_publishable_TFi8I26ME63imHzRvDxmKw_e1X8lyC_',
);
