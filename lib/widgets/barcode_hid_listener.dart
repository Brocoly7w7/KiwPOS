// lib/widgets/barcode_hid_listener.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Captura un lector Bluetooth HID desde el árbol de foco de Flutter.
///
/// El lector HID se comporta como un teclado físico. Este widget utiliza
/// [Focus.onKeyEvent] para decidir si una tecla pertenece al escáner antes de
/// que Android la entregue a un campo de texto.
///
/// Debe existir una sola instancia alrededor de la pantalla principal.
class BarcodeHidListener extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Future<void> Function(String barcode) onBarcode;

  /// Nodo principal que recibe el lector cuando ningún campo editable debe
  /// conservar el foco.
  final FocusNode? focusNode;

  /// Permite formar un código aunque exista un EditableText con foco.
  final bool captureWhenEditableFocused;

  /// Si el foco pertenece a un campo distinto del permitido, lo libera al
  /// recibir el primer carácter del escáner.
  final bool unfocusEditableOnCapture;

  /// Campo editable que sí puede conservar el foco, por ejemplo el buscador
  /// visible de Artículos.
  final FocusNode? permittedEditableFocusNode;

  const BarcodeHidListener({
    super.key,
    required this.child,
    required this.onBarcode,
    this.enabled = true,
    this.focusNode,
    this.captureWhenEditableFocused = false,
    this.unfocusEditableOnCapture = false,
    this.permittedEditableFocusNode,
  });

  @override
  State<BarcodeHidListener> createState() => _BarcodeHidListenerState();
}

class _BarcodeHidListenerState extends State<BarcodeHidListener> {
  final StringBuffer _buffer = StringBuffer();

  late FocusNode _scannerFocusNode;
  late bool _ownsFocusNode;

  Timer? _clearTimer;
  Future<void> _scanQueue = Future<void>.value();
  DateTime? _firstCharacterAt;
  DateTime? _lastCharacterAt;
  bool _active = true;

  static const Duration _maximumCharacterGap =
      Duration(milliseconds: 190);
  static const Duration _bufferTimeout =
      Duration(milliseconds: 750);

  @override
  void initState() {
    super.initState();
    _configureFocusNode(widget.focusNode);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestScannerFocusIfNeeded();
    });
  }

  void _configureFocusNode(FocusNode? externalNode) {
    _ownsFocusNode = externalNode == null;
    _scannerFocusNode =
        externalNode ??
        FocusNode(
          debugLabel: 'barcodeHidRoot',
          skipTraversal: true,
        );
  }

  @override
  void didUpdateWidget(covariant BarcodeHidListener oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      if (_ownsFocusNode) {
        _scannerFocusNode.dispose();
      }

      _configureFocusNode(widget.focusNode);
    }

    if (oldWidget.enabled && !widget.enabled) {
      _clearBuffer();

      if (_scannerFocusNode.hasFocus) {
        _scannerFocusNode.unfocus();
      }
    } else if (!oldWidget.enabled && widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _requestScannerFocusIfNeeded();
      });
    }
  }

  @override
  void activate() {
    super.activate();
    _active = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestScannerFocusIfNeeded();
    });
  }

  @override
  void deactivate() {
    _active = false;
    _clearBuffer();
    super.deactivate();
  }

  bool _routeIsCurrent() {
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  FocusNode? get _primaryFocus => FocusManager.instance.primaryFocus;

  bool _editableTextHasFocus() {
    final focusContext = _primaryFocus?.context;

    if (focusContext == null) {
      return false;
    }

    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _permittedEditableHasFocus() {
    final permitted = widget.permittedEditableFocusNode;
    final primary = _primaryFocus;

    return permitted != null &&
        permitted.hasFocus &&
        (identical(primary, permitted) ||
            primary?.ancestors.contains(permitted) == true);
  }

  void _debugLog(String message) {
    if (!kDebugMode) return;
    debugPrint('[KiwPOS HID] $message');
  }

  void _requestScannerFocusIfNeeded() {
    if (!mounted ||
        !_active ||
        !widget.enabled ||
        !_routeIsCurrent() ||
        _permittedEditableHasFocus()) {
      return;
    }

    _scannerFocusNode.requestFocus();
  }

  void _takeScannerFocusFromResidualField() {
    final primary = _primaryFocus;

    if (primary != null && !identical(primary, _scannerFocusNode)) {
      primary.unfocus(disposition: UnfocusDisposition.scope);
    }

    _scannerFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _clearBuffer() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _buffer.clear();
    _firstCharacterAt = null;
    _lastCharacterAt = null;
  }

  void _restartClearTimer() {
    _clearTimer?.cancel();
    _clearTimer = Timer(_bufferTimeout, _clearBuffer);
  }

  void _appendCharacter(String character) {
    final now = DateTime.now();
    final previous = _lastCharacterAt;

    if (previous != null &&
        now.difference(previous) > _maximumCharacterGap) {
      _buffer.clear();
      _firstCharacterAt = null;
    }

    _firstCharacterAt ??= now;
    _lastCharacterAt = now;
    _buffer.write(character);
    _restartClearTimer();
  }

  bool _looksLikeScannerSequence(String barcode) {
    if (barcode.length < 3) {
      return false;
    }

    final first = _firstCharacterAt;
    final last = _lastCharacterAt;

    if (first == null || last == null) {
      return false;
    }

    final elapsed = last.difference(first);
    final maximumAllowed = Duration(
      milliseconds: 250 + (barcode.length * 190),
    );

    return elapsed <= maximumAllowed;
  }

  void _submitBuffer() {
    _clearTimer?.cancel();
    _clearTimer = null;

    final barcode = _buffer.toString().trim();
    final validScannerSequence = _looksLikeScannerSequence(barcode);

    _buffer.clear();
    _firstCharacterAt = null;
    _lastCharacterAt = null;

    if (!validScannerSequence ||
        !_active ||
        !mounted ||
        !widget.enabled ||
        !_routeIsCurrent()) {
      return;
    }

    _debugLog('Código completado: $barcode');

    _scanQueue = _scanQueue.then((_) async {
      if (!_active ||
          !mounted ||
          !widget.enabled ||
          !_routeIsCurrent()) {
        return;
      }

      try {
        await widget.onBarcode(barcode);
      } catch (error, stackTrace) {
        debugPrint('Error procesando código HID: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    });
  }

  bool _isSubmitKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab;
  }

  bool _isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.capsLock;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_active ||
        !mounted ||
        !widget.enabled ||
        !_routeIsCurrent() ||
        event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final logicalKey = event.logicalKey;
    final editableFocused = _editableTextHasFocus();
    final permittedFocused = _permittedEditableHasFocus();

    if (_isModifierKey(logicalKey)) {
      return KeyEventResult.ignored;
    }

    if (logicalKey == LogicalKeyboardKey.backspace ||
        logicalKey == LogicalKeyboardKey.delete) {
      _clearBuffer();
      return permittedFocused
          ? KeyEventResult.ignored
          : KeyEventResult.handled;
    }

    if (_isSubmitKey(logicalKey)) {
      final hadCandidate = _buffer.length >= 3;
      _submitBuffer();

      if (hadCandidate) {
        return KeyEventResult.handled;
      }

      return permittedFocused
          ? KeyEventResult.ignored
          : KeyEventResult.handled;
    }

    final keyLabel = logicalKey.keyLabel;
    final character =
        event.character ?? (keyLabel.length == 1 ? keyLabel : null);

    if (character == null || character.isEmpty) {
      return KeyEventResult.ignored;
    }

    final runes = character.runes.toList(growable: false);
    if (runes.length != 1) {
      return KeyEventResult.ignored;
    }

    final codeUnit = runes.first;
    final printable = codeUnit >= 32 && codeUnit != 127;

    if (!printable) {
      return KeyEventResult.ignored;
    }

    if (editableFocused &&
        !permittedFocused &&
        !widget.captureWhenEditableFocused) {
      _clearBuffer();
      return KeyEventResult.ignored;
    }

    if (editableFocused &&
        !permittedFocused &&
        widget.captureWhenEditableFocused &&
        widget.unfocusEditableOnCapture) {
      _debugLog('Liberando un campo residual y tomando el foco del lector.');
      _takeScannerFocusFromResidualField();
    }

    _appendCharacter(character);

    // El buscador visible recibe los caracteres para que el usuario vea el
    // código. En Caja o en un campo residual los consumimos antes de que
    // Android los escriba y abra el teclado.
    return permittedFocused
        ? KeyEventResult.ignored
        : KeyEventResult.handled;
  }

  @override
  void dispose() {
    _active = false;
    _clearTimer?.cancel();

    if (_ownsFocusNode) {
      _scannerFocusNode.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _scannerFocusNode,
      autofocus: widget.enabled,
      canRequestFocus: widget.enabled,
      skipTraversal: true,
      descendantsAreFocusable: true,
      onKeyEvent: _handleKeyEvent,
      child: widget.child,
    );
  }
}
