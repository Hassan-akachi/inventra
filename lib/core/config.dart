/// Backend settings. The publishable key is safe to ship in the app:
/// Row Level Security on every table decides what each user can see.
class AppConfig {
  AppConfig._();

  static const supabaseUrl = 'https://fvsjuqcdsxdiqejvqygd.supabase.co';
  static const supabaseKey = 'sb_publishable_1k8djB0dRuUUuTE1AVzJwQ_nl0BrSLA';

  /// PowerSync instance URL. Check it in the PowerSync dashboard:
  /// your instance → "Connect" button → copy the URL, and replace this if different.
  static const powersyncUrl =
      'https://6af2284e4d7433c8099ab0e4.powersync.journeyapps.com';
}
