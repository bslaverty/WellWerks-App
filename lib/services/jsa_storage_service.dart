import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/jsa_draft.dart';

class JsaStorageService {
  static const _draftKey = 'wellwerks_jsa_latest_draft';

  Future<void> saveDraft(JsaDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftKey, jsonEncode(draft.toJson()));
  }

  Future<JsaDraft?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.isEmpty) return null;
    return JsaDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }
}
