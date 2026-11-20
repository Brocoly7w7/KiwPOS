// lib/widgets/articles_header.dart
import 'package:flutter/material.dart';

class ArticlesHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String hintText;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;

  // Se conserva para evitar errores en las llamadas existentes.
  final bool showScannerIcons;

  // Permite mostrar u ocultar la barra de búsqueda.
  final bool showSearchBar;

  final VoidCallback? onMenuPressed;
  final ValueChanged<String>? onSearchSubmitted;

  const ArticlesHeader({
    super.key,
    this.title = 'Artículos',
    this.hintText = 'Quiero vender...',
    this.searchController,
    this.searchFocusNode,
    this.showScannerIcons = true,
    this.showSearchBar = true,
    this.onMenuPressed,
    this.onSearchSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      automaticallyImplyLeading: false,

      // Botón para abrir el menú lateral.
      leading: IconButton(
        tooltip: 'Abrir menú',
        icon: const Icon(Icons.menu, color: Colors.black87),
        onPressed: onMenuPressed,
      ),

      title: Text(
        title,
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),

      // La barra de búsqueda aparece solamente cuando showSearchBar es true.
      bottom:
          showSearchBar
              ? PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: AnimatedBuilder(
                    animation:
                        searchController ??
                        const AlwaysStoppedAnimation<int>(0),
                    builder: (context, child) {
                      final bool tieneTexto =
                          searchController != null &&
                          searchController!.text.isNotEmpty;

                      return _SelectAllOnFirstTapTextField(
                        controller: searchController,
                        focusNode: searchFocusNode,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.search,
                        onTapOutside: (_) {
                          searchFocusNode?.unfocus();
                        },
                        onSubmitted: (value) {
                          searchFocusNode?.unfocus();
                          onSearchSubmitted?.call(value);
                        },
                        decoration: InputDecoration(
                          hintText: hintText,
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.blue,
                          ),
                          suffixIcon:
                              tieneTexto
                                  ? IconButton(
                                    tooltip: 'Limpiar búsqueda',
                                    icon: const Icon(
                                      Icons.clear,
                                      color: Colors.grey,
                                    ),
                                    onPressed: searchController!.clear,
                                  )
                                  : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Colors.grey),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Colors.blue,
                              width: 1.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      );
                    },
                  ),
                ),
              )
              : null,
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(showSearchBar ? 116 : kToolbarHeight);
}

class _SelectAllOnFirstTapTextField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextInputAction? textInputAction;
  final TapRegionCallback? onTapOutside;
  final ValueChanged<String>? onSubmitted;
  final InputDecoration? decoration;

  const _SelectAllOnFirstTapTextField({
    required this.controller,
    required this.focusNode,
    required this.autocorrect,
    required this.enableSuggestions,
    required this.textInputAction,
    required this.onTapOutside,
    required this.onSubmitted,
    required this.decoration,
  });

  @override
  State<_SelectAllOnFirstTapTextField> createState() =>
      _SelectAllOnFirstTapTextFieldState();
}

class _SelectAllOnFirstTapTextFieldState
    extends State<_SelectAllOnFirstTapTextField> {
  bool _selectAllOnNextTap = true;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _SelectAllOnFirstTapTextField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChanged);
      widget.focusNode?.addListener(_handleFocusChanged);
      _selectAllOnNextTap = true;
    }
  }

  void _handleFocusChanged() {
    if (widget.focusNode?.hasFocus != true) {
      _selectAllOnNextTap = true;
    }
  }

  void _handleTap() {
    if (!_selectAllOnNextTap) {
      // Segundo toque y siguientes: TextField conserva la posición exacta
      // elegida por el usuario para mover el cursor o editar un solo carácter.
      return;
    }

    _selectAllOnNextTap = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.focusNode?.hasFocus != true) {
        return;
      }

      final controller = widget.controller;
      if (controller == null) {
        return;
      }

      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_handleFocusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      keyboardType: TextInputType.name,
      textCapitalization: TextCapitalization.none,
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.enableSuggestions,
      textInputAction: widget.textInputAction,
      onTap: _handleTap,
      onTapOutside: widget.onTapOutside,
      onSubmitted: widget.onSubmitted,
      decoration: widget.decoration,
    );
  }
}
