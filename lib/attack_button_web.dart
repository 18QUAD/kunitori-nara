import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'browser_insets.dart';
import 'action_button_style.dart';
import 'attack_contacts.dart';
import 'diagnostics.dart';

Widget protectAttackTap({required Widget child, VoidCallback? onPressed}) =>
    _NativeAttackButton(onPressed: onPressed);

class _NativeAttackButton extends StatefulWidget {
  const _NativeAttackButton({this.onPressed});
  final VoidCallback? onPressed;

  @override
  State<_NativeAttackButton> createState() => _NativeAttackButtonState();
}

class _NativeAttackButtonState extends State<_NativeAttackButton>
    with WidgetsBindingObserver {
  web.HTMLButtonElement? _button;
  bool _routeCurrent = true;
  bool _portraitAllowed = true;
  Rect? _rect;
  bool _placementPending = false;
  final _contacts = AttackContacts();
  late final JSFunction _releaseContact;
  late final JSFunction _startSequence;
  late final JSFunction _resetContacts;

  void _update() {
    final button = _button;
    if (button == null) return;
    final enabled = widget.onPressed != null;
    final background = (enabled
            ? actionPrimary
            : actionPrimary.withValues(alpha: .35))
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0');
    button.disabled = !enabled;
    button.setAttribute('aria-label', enabled ? 'タップで進軍 · 1人' : '隣接する自領が必要です');
    final image =
        enabled
            ? Uri.parse(
              web.document.baseURI,
            ).resolve('assets/assets/icons/tap.png')
            : Uri.dataFromString(
              '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
              '<path fill="#708090" d="M18 8h-1V6a5 5 0 0 0-10 0v2H6'
              'a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V10'
              'a2 2 0 0 0-2-2ZM9 6a3 3 0 0 1 6 0v2H9Z"/></svg>',
              mimeType: 'image/svg+xml',
            );
    // No DOM text or image element for iOS to select or open an image menu on.
    button.style.cssText =
        'display:block;position:absolute;z-index:20;margin:0;padding:0;border:0;'
        'left:${_rect?.left ?? 0}px;top:${_rect?.top ?? 0}px;'
        'width:${_rect?.width ?? 0}px;height:${_rect?.height ?? 0}px;'
        'pointer-events:auto;'
        'visibility:${_routeCurrent && _portraitAllowed && _rect != null ? 'visible' : 'hidden'};'
        'border-radius:999px;box-sizing:border-box;cursor:pointer;appearance:none;'
        '-webkit-appearance:none;'
        'background:#${background.substring(2)}${background.substring(0, 2)} url("$image") '
        'center / ${enabled ? 56 : 48}px ${enabled ? 56 : 48}px no-repeat;'
        'touch-action:none;-webkit-user-select:none;user-select:none;'
        '-webkit-touch-callout:none;';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _readPortrait();
    _update();
    _schedulePlacement();
  }

  @override
  void didUpdateWidget(covariant _NativeAttackButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
    _schedulePlacement();
  }

  void _schedulePlacement() {
    if (!mounted || _placementPending) return;
    _placementPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _placementPending = false;
      if (!mounted) return;
      _readPortrait();
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        _rect = box.localToGlobal(Offset.zero) & box.size;
        _update();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _readPortrait() {
    final view = View.of(context);
    _portraitAllowed =
        view.physicalSize.width <= view.physicalSize.height ||
        MediaQuery.viewInsetsOf(context).bottom > 0;
  }

  @override
  void didChangeMetrics() => _schedulePlacement();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    browserInsets.removeListener(_schedulePlacement);
    for (final type in ['pointerup', 'pointercancel']) {
      web.document.removeEventListener(type, _releaseContact, true.toJS);
    }
    web.document.removeEventListener('pointerdown', _startSequence, true.toJS);
    web.window.removeEventListener('blur', _resetContacts);
    web.document.removeEventListener('visibilitychange', _resetContacts);
    _contacts.clear();
    _button?.remove();
    _button = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _schedulePlacement();
      return const SizedBox.expand(key: Key('attack'));
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    browserInsets.addListener(_schedulePlacement);
    final button = web.HTMLButtonElement();
    _button = button;
    button.type = 'button';
    button.className = 'attack-tap-native';
    // One contact group counts once, on its first press. Every finger in the
    // group must be released/canceled before a new group can count. Capture the
    // document's releases so dragging outside the button cannot leave it stuck.
    // Primary contacts can begin anywhere in this document, not just on the
    // button. Clear stale contacts before a later secondary finger enters it.
    _startSequence =
        ((web.PointerEvent event) {
          if (!event.isPrimary) return;
          final before = _contacts.length;
          _contacts.startSequence(event.pointerType);
          if (_contacts.length != before) {
            recordDiagnostic('trace_button', {
              'phase': 'reset_primary_sequence',
              'operation': event.pointerId,
              'count': _contacts.length,
              'resource': event.pointerType,
            });
          }
        }).toJS;
    web.document.addEventListener('pointerdown', _startSequence, true.toJS);
    _releaseContact =
        ((web.PointerEvent event) {
          if (!_contacts.end(event.pointerId)) return;
          recordDiagnostic('trace_button', {
            'phase': event.type,
            'operation': event.pointerId,
            'count': _contacts.length,
            'resource': event.pointerType,
          });
        }).toJS;
    for (final type in ['pointerup', 'pointercancel']) {
      web.document.addEventListener(type, _releaseContact, true.toJS);
    }
    _resetContacts =
        ((web.Event event) {
          if (event.type == 'blur' || web.document.hidden) {
            _contacts.clear();
            recordDiagnostic('trace_button', {
              'phase': 'reset_${event.type}',
              'count': 0,
            });
          }
        }).toJS;
    web.window.addEventListener('blur', _resetContacts);
    web.document.addEventListener('visibilitychange', _resetContacts);
    button.addEventListener(
      'pointerdown',
      ((web.PointerEvent event) {
        event.stopPropagation();
        final rejected =
            event.button != 0
                ? 'secondary_button'
                : !mounted
                ? 'unmounted'
                : !_routeCurrent
                ? 'route_inactive'
                : !_portraitAllowed
                ? 'landscape'
                : button.disabled || widget.onPressed == null
                ? 'disabled'
                : null;
        if (rejected != null) {
          recordDiagnostic('trace_button', {
            'phase': rejected,
            'operation': event.pointerId,
            'count': _contacts.length,
            'resource': event.pointerType,
          });
          return;
        }
        final previousContacts = _contacts.length;
        final accepted = _contacts.begin(
          event.pointerId,
          event.pointerType,
          primary: event.isPrimary,
        );
        recordDiagnostic('trace_button', {
          'phase':
              accepted
                  ? (previousContacts > 0 ? 'accepted_recovered' : 'accepted')
                  : 'overlapping_contact',
          'operation': event.pointerId,
          'count': _contacts.length,
          'resource':
              '${event.pointerType}:${event.isPrimary ? 'primary' : 'secondary'}',
        });
        if (accepted) widget.onPressed?.call();
      }).toJS,
    );
    for (final type in [
      'pointerup',
      'pointermove',
      'pointercancel',
      'keydown',
      'keyup',
    ]) {
      button.addEventListener(
        type,
        ((web.Event event) {
          event.stopPropagation();
        }).toJS,
      );
    }
    button.addEventListener(
      'click',
      ((web.MouseEvent event) {
        event.stopPropagation();
        // Physical contacts were already counted on pointerdown. Keyboard,
        // assistive activation and element.click() have no physical pointer.
        final physicalPointer =
            event.isA<web.PointerEvent>() &&
            (event as web.PointerEvent).pointerType.isNotEmpty;
        if (event.detail == 0 &&
            !physicalPointer &&
            mounted &&
            _routeCurrent &&
            _portraitAllowed &&
            !button.disabled) {
          widget.onPressed?.call();
        }
      }).toJS,
    );
    button.addEventListener(
      'contextmenu',
      ((web.Event event) {
        event.preventDefault();
      }).toJS,
    );
    _update();
    web.document.getElementById('app-host')!.append(button);
  }
}
