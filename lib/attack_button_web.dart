import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'browser_insets.dart';

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

  void _update() {
    final button = _button;
    if (button == null) return;
    final enabled = widget.onPressed != null;
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
        'background:${enabled ? '#eec47c' : '#263341'} url("$image") '
        'center / ${enabled ? 56 : 48}px ${enabled ? 56 : 48}px no-repeat;'
        'touch-action:manipulation;-webkit-user-select:none;user-select:none;'
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
    // This button sits above Flutter's transparent text hit targets and owns
    // its events. No touch defaults are canceled and no clicks synthesized.
    for (final type in [
      'pointerdown',
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
      ((web.Event event) {
        event.stopPropagation();
        if (mounted && _routeCurrent && _portraitAllowed) {
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
