import 'package:flutter/material.dart';

const actionPrimary = Color(0xFFDDE1E6);
const actionForeground = Color(0xFF202631);

ButtonStyle actionButtonStyle() => FilledButton.styleFrom(
  backgroundColor: actionPrimary,
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
