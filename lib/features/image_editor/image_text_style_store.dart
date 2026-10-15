import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ImageTextStyleStore {
  static const _kFamily = 'kala_img_text_family';
  static const _kSize = 'kala_img_text_size';
  static const _kColor = 'kala_img_text_color';
  static const _kBg = 'kala_img_text_bg';

  static Future<void> save({
    required String family,
    required double size,
    required Color color,
    required Color background,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kFamily, family);
    await p.setDouble(_kSize, size);
    await p.setInt(_kColor, color.toARGB32());
    await p.setInt(_kBg, background.toARGB32());
  }

  static Future<({String family, double size, Color color, Color background})>
      load() async {
    final p = await SharedPreferences.getInstance();
    return (
      family: p.getString(_kFamily) ?? 'Inter',
      size: p.getDouble(_kSize) ?? 24,
      color: Color(p.getInt(_kColor) ?? 0xFFFFFFFF),
      background: Color(p.getInt(_kBg) ?? 0x00000000),
    );
  }
}
