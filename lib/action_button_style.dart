import 'package:flutter/material.dart';

const actionPrimary = Color(0xFFC6A5F5);
const actionSecondary = Color(0xFFF3A4C9);
const actionForeground = Color(0xFF251734);

ButtonStyle actionButtonStyle({bool secondary = false}) =>
    FilledButton.styleFrom(
      backgroundColor: secondary ? actionSecondary : actionPrimary,
      foregroundColor: actionForeground,
      disabledBackgroundColor: actionPrimary.withValues(alpha: .35),
      disabledForegroundColor: actionForeground.withValues(alpha: .6),
      minimumSize: const Size(48, 52),
      textStyle: const TextStyle(
        fontFamily: 'NotoSansJP',
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
