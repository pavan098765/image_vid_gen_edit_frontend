import 'package:shared_preferences/shared_preferences.dart';

const kExploreFavoriteTemplateIdsKey = 'explore_favorite_template_ids';
const kFavoriteStyleIdsKey = 'favorite_style_ids';

Future<List<String>> loadExploreFavoriteTemplateIds() async {
  final prefs = await SharedPreferences.getInstance();
  return List<String>.from(
    prefs.getStringList(kExploreFavoriteTemplateIdsKey) ?? const <String>[],
  );
}

Future<void> saveExploreFavoriteTemplateIds(List<String> ids) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(kExploreFavoriteTemplateIdsKey, ids);
}

Future<Set<String>> loadFavoriteStyleIds() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getStringList(kFavoriteStyleIdsKey) ?? const <String>[])
      .toSet();
}

Future<void> saveFavoriteStyleIds(Set<String> ids) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(kFavoriteStyleIdsKey, ids.toList());
}
