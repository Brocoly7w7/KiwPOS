// lib/screens/articles_page.dart
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database_helper.dart';
import '../services/catalog_backup_service.dart';
import '../services/catalog_intent_service.dart';
import '../widgets/articles_header.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/barcode_hid_listener.dart';
import '../utils/product_category.dart';
import 'add_article_page.dart';
import 'article_detail_modal.dart';
import 'caja_page.dart';
import 'historial_page.dart';

class ArticlesPage extends StatefulWidget {
  final bool isSelectorMode;
  final String planName;
  final DateTime? subscriptionEnd;
  final bool isOfflineAccess;

  const ArticlesPage({
    super.key,
    this.isSelectorMode = false,
    this.planName = 'Plan activo',
    this.subscriptionEnd,
    this.isOfflineAccess = false,
  });

  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late int _currentIndex;
  int _ticketCounter = 1;
  bool _isSigningOut = false;
  bool _catalogTransferBusy = false;
  bool _incomingCatalogBusy = false;

  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> filteredProducts = [];
  List<Map<String, dynamic>> cajasClientes = [];
  int cajaActivaIndex = 0;
  List<Map<String, dynamic>> historyTickets = [];
  String nombreNegocio = 'Nombre del negocio';
  String direccionNegocio = 'Dirección del negocio';

  List<Map<String, dynamic>> get checkoutCart {
    if (cajasClientes.isEmpty || cajaActivaIndex >= cajasClientes.length) {
      return [];
    }

    final items = cajasClientes[cajaActivaIndex]['items'];
    if (items is List) {
      return List<Map<String, dynamic>>.from(items);
    }

    return [];
  }

  String get cajaActivaId {
    if (cajasClientes.isEmpty || cajaActivaIndex >= cajasClientes.length) {
      return DatabaseHelper.cajaDefaultId;
    }

    return cajasClientes[cajaActivaIndex]['id'].toString();
  }

  final TextEditingController _historialSearchController =
      TextEditingController();
  final TextEditingController _articulosSearchController =
      TextEditingController();
  final FocusNode _historialSearchFocusNode = FocusNode(
    debugLabel: 'historialSearch',
  );
  final FocusNode _articulosSearchFocusNode = FocusNode(
    debugLabel: 'articulosSearch',
  );
  final FocusNode _scannerFocusNode = FocusNode(
    debugLabel: 'globalBarcodeScanner',
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _currentIndex = 3;

    _cargarArticulos();
    _cargarHistorialVentas();
    _cargarCajasClientes();
    _cargarConfigFactura();

    _articulosSearchController.addListener(_filtrarArticulos);
    CatalogIntentService.pendingCatalogPath.addListener(
      _manejarCatalogoPendiente,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reactivarCapturaHid();
      unawaited(_refrescarCatalogoPendiente());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CatalogIntentService.pendingCatalogPath.removeListener(
      _manejarCatalogoPendiente,
    );
    _articulosSearchController.removeListener(_filtrarArticulos);
    _historialSearchController.dispose();
    _articulosSearchController.dispose();
    _historialSearchFocusNode.dispose();
    _articulosSearchFocusNode.dispose();
    _scannerFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reactivarCapturaHid();
      unawaited(_refrescarCatalogoPendiente());
    }
  }

  Future<void> _refrescarCatalogoPendiente() async {
    await CatalogIntentService.refreshPendingCatalog();

    if (mounted) {
      _manejarCatalogoPendiente();
    }
  }

  Future<void> _cargarConfigFactura() async {
    final config = await DatabaseHelper().getFacturaConfig();

    if (!mounted) {
      return;
    }

    setState(() {
      nombreNegocio = config['nombreNegocio'] ?? nombreNegocio;
      direccionNegocio = config['direccionNegocio'] ?? direccionNegocio;
    });
  }

  Future<void> _cargarArticulos() async {
    final data = await DatabaseHelper().getArticulos();

    if (!mounted) {
      return;
    }

    final query = _articulosSearchController.text.toLowerCase().trim();

    setState(() {
      products = data;

      if (query.isEmpty) {
        filteredProducts = List<Map<String, dynamic>>.from(products);
      } else {
        filteredProducts =
            products.where((product) {
              final nombreProducto =
                  (product['nombre'] ?? '').toString().toLowerCase();
              final codigoBarras =
                  (product['codigoBarras'] ?? '').toString().toLowerCase();

              return nombreProducto.contains(query) ||
                  codigoBarras.contains(query);
            }).toList();
      }
    });
  }

  void _filtrarArticulos() {
    final query = _articulosSearchController.text.toLowerCase().trim();

    setState(() {
      if (query.isEmpty) {
        filteredProducts = List<Map<String, dynamic>>.from(products);
      } else {
        filteredProducts =
            products.where((product) {
              final nombreProducto =
                  (product['nombre'] ?? '').toString().toLowerCase();
              final codigoBarras =
                  (product['codigoBarras'] ?? '').toString().toLowerCase();

              return nombreProducto.contains(query) ||
                  codigoBarras.contains(query);
            }).toList();
      }
    });
  }

  Future<void> _cargarHistorialVentas() async {
    final tickets = await DatabaseHelper().getTickets();
    final siguienteCliente = await DatabaseHelper().getSiguienteNumeroCliente();

    if (!mounted) {
      return;
    }

    setState(() {
      historyTickets = tickets;
      _ticketCounter = siguienteCliente;
    });
  }

  bool _esNombreAutomaticoCliente(String nombre) {
    final limpio = nombre.trim();
    if (limpio.isEmpty) {
      return true;
    }

    return RegExp(r'^Cliente\s+#?\d+$', caseSensitive: false).hasMatch(limpio);
  }

  Future<void> _sincronizarNombresAutomaticos() async {
    if (cajasClientes.isEmpty) {
      return;
    }

    final int siguienteCliente =
        await DatabaseHelper().getSiguienteNumeroCliente();

    int offset = 0;
    final List<Map<String, dynamic>> cajasActualizadas = [];

    for (final caja in cajasClientes) {
      final String idCaja = (caja['id'] ?? '').toString();
      final String nombreActual = (caja['nombre'] ?? '').toString();

      if (_esNombreAutomaticoCliente(nombreActual)) {
        final String nuevoNombre = 'Cliente #${siguienteCliente + offset}';
        offset++;

        cajasActualizadas.add({...caja, 'nombre': nuevoNombre});

        if (idCaja.isNotEmpty && nuevoNombre != nombreActual) {
          await DatabaseHelper().actualizarNombreCaja(idCaja, nuevoNombre);
        }
      } else {
        cajasActualizadas.add(caja);
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      cajasClientes = cajasActualizadas;
      if (cajaActivaIndex >= cajasClientes.length) {
        cajaActivaIndex = cajasClientes.length - 1;
      }
      if (cajaActivaIndex < 0) {
        cajaActivaIndex = 0;
      }
    });
  }

  Future<void> _cargarCajasClientes() async {
    final cajas = await DatabaseHelper().getCajasConCarrito();

    if (!mounted) {
      return;
    }

    setState(() {
      cajasClientes = cajas;

      if (cajasClientes.isEmpty) {
        cajaActivaIndex = 0;
      } else if (cajaActivaIndex >= cajasClientes.length) {
        cajaActivaIndex = cajasClientes.length - 1;
      }
    });

    await _sincronizarNombresAutomaticos();
  }

  Future<void> _actualizarCarritoActivo(
    List<Map<String, dynamic>> nuevoCarrito,
  ) async {
    if (cajasClientes.isEmpty) {
      await _cargarCajasClientes();
    }

    if (!mounted || cajasClientes.isEmpty) {
      return;
    }

    final String idCaja = cajaActivaId;

    setState(() {
      cajasClientes[cajaActivaIndex] = {
        ...cajasClientes[cajaActivaIndex],
        'items': nuevoCarrito,
      };
    });

    await DatabaseHelper().guardarCarritoDeCaja(idCaja, nuevoCarrito);
  }

  Future<void> _crearNuevaCaja() async {
    final int siguienteCliente =
        await DatabaseHelper().getSiguienteNumeroCliente();

    final int cajasAutomaticasAbiertas =
        cajasClientes.where((caja) {
          final nombre = (caja['nombre'] ?? '').toString();
          return _esNombreAutomaticoCliente(nombre);
        }).length;

    final String nombre =
        'Cliente #${siguienteCliente + cajasAutomaticasAbiertas}';

    final String id = await DatabaseHelper().crearCaja(nombre: nombre);

    if (!mounted) {
      return;
    }

    _liberarFocoDeEntrada();

    setState(() {
      cajasClientes.add({
        'id': id,
        'nombre': nombre,
        'items': <Map<String, dynamic>>[],
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      cajaActivaIndex = cajasClientes.length - 1;
      _currentIndex = 2;
    });
  }

  Future<void> _seleccionarCaja(int index) async {
    if (index < 0 || index >= cajasClientes.length) {
      return;
    }

    setState(() {
      cajaActivaIndex = index;
    });
  }

  Future<void> _eliminarCaja(int index) async {
    if (index < 0 || index >= cajasClientes.length) {
      return;
    }

    if (cajasClientes.length <= 1) {
      return;
    }

    final String idCaja = (cajasClientes[index]['id'] ?? '').toString();

    setState(() {
      cajasClientes.removeAt(index);

      if (cajaActivaIndex >= cajasClientes.length) {
        cajaActivaIndex = cajasClientes.length - 1;
      } else if (index < cajaActivaIndex) {
        cajaActivaIndex -= 1;
      }

      if (cajaActivaIndex < 0) {
        cajaActivaIndex = 0;
      }
    });

    if (idCaja.isNotEmpty) {
      await DatabaseHelper().eliminarCaja(idCaja);
    }

    // Si quedaron cajas con nombre automático, se reacomodan al índice real
    // del historial para evitar duplicados como Cliente #8 y Cliente #8.
    await _sincronizarNombresAutomaticos();
  }

  Future<void> _renombrarCajaActiva(String nuevoNombre) async {
    if (cajasClientes.isEmpty) {
      return;
    }

    final String nombreLimpio =
        nuevoNombre.trim().isEmpty
            ? 'Cliente #$_ticketCounter'
            : nuevoNombre.trim();

    final String idCaja = cajaActivaId;

    setState(() {
      cajasClientes[cajaActivaIndex] = {
        ...cajasClientes[cajaActivaIndex],
        'nombre': nombreLimpio,
      };
    });

    await DatabaseHelper().actualizarNombreCaja(idCaja, nombreLimpio);
  }

  bool get _lectorDebeEstarActivo =>
      widget.isSelectorMode || _currentIndex == 2 || _currentIndex == 3;

  void _liberarFocoDeEntrada() {
    _historialSearchFocusNode.unfocus(disposition: UnfocusDisposition.scope);
    _articulosSearchFocusNode.unfocus(disposition: UnfocusDisposition.scope);
    FocusManager.instance.primaryFocus?.unfocus(
      disposition: UnfocusDisposition.scope,
    );
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _tomarFocoDelLectorAhora() {
    if (!mounted || !_lectorDebeEstarActivo) {
      return;
    }

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      return;
    }

    // Si el usuario ya tocó alguno de los buscadores, respetamos su foco.
    // Así los intentos retrasados de reactivar el lector no vuelven a cerrar
    // el teclado inmediatamente después de que el usuario empieza a escribir.
    if (_articulosSearchFocusNode.hasFocus ||
        _historialSearchFocusNode.hasFocus) {
      return;
    }

    final primaryFocus = FocusManager.instance.primaryFocus;

    if (primaryFocus != null && !identical(primaryFocus, _scannerFocusNode)) {
      primaryFocus.unfocus(disposition: UnfocusDisposition.scope);
    }

    if (!_scannerFocusNode.hasFocus) {
      _scannerFocusNode.requestFocus();
    }

    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _reactivarCapturaHid() {
    if (!mounted || !_lectorDebeEstarActivo) {
      return;
    }

    // Android puede restaurar el foco del último TextField durante varios
    // frames después de cerrar una ruta. Reclamamos el foco en varios puntos
    // cortos, siempre validando que esta ruta continúe visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tomarFocoDelLectorAhora();
    });

    for (final delay in <Duration>[
      const Duration(milliseconds: 80),
      const Duration(milliseconds: 220),
      const Duration(milliseconds: 450),
    ]) {
      Future<void>.delayed(delay, () {
        _tomarFocoDelLectorAhora();
      });
    }
  }

  Future<void> _agregarArticuloEscaneadoEnCaja(
    Map<String, dynamic> articulo,
  ) async {
    final int? articuloId =
        articulo['id'] is int ? articulo['id'] as int : null;
    final String codigoBarras =
        (articulo['codigoBarras'] ?? '').toString().trim();
    final String nombre = (articulo['nombre'] ?? 'Artículo').toString();
    final String categoria = ProductCategory.normalize(
      articulo['categoria'],
      barcode: codigoBarras,
    );
    final double precio =
        articulo['precio'] is num
            ? (articulo['precio'] as num).toDouble()
            : double.tryParse(articulo['precio']?.toString() ?? '') ?? 0.0;

    final nuevoCarrito = List<Map<String, dynamic>>.from(checkoutCart);

    // Abarrotes: aumenta piezas. Productos frescos: nueva pesada independiente.
    final existingIndex =
        ProductCategory.isGrocery(categoria)
            ? nuevoCarrito.indexWhere((item) {
              final itemCategory = ProductCategory.normalize(
                item['categoria'],
                barcode: item['codigoBarras'],
              );

              if (!ProductCategory.isGrocery(itemCategory)) {
                return false;
              }

              final itemId = item['articuloId'];
              final itemBarcode =
                  (item['codigoBarras'] ?? '').toString().trim();

              if (articuloId != null && itemId == articuloId) {
                return true;
              }

              return codigoBarras.isNotEmpty && itemBarcode == codigoBarras;
            })
            : -1;

    double nuevaCantidad = 1.0;

    if (existingIndex >= 0) {
      final existing = nuevoCarrito[existingIndex];
      final currentQuantity =
          existing['kg'] is num
              ? (existing['kg'] as num).toDouble()
              : double.tryParse(existing['kg']?.toString() ?? '') ?? 0.0;
      final double existingPrice =
          existing['precio'] is num
              ? (existing['precio'] as num).toDouble()
              : double.tryParse(existing['precio']?.toString() ?? '') ?? precio;
      final String existingCategory = ProductCategory.normalize(
        existing['categoria'] ?? categoria,
        barcode: existing['codigoBarras'] ?? codigoBarras,
      );

      nuevaCantidad = ProductCategory.normalizeQuantity(
        currentQuantity + 1.0,
        existingCategory,
      );

      nuevoCarrito[existingIndex] = {
        ...existing,
        'precio': existingPrice,
        'kg': nuevaCantidad,
        'total': existingPrice * nuevaCantidad,
        'articuloId': articuloId ?? existing['articuloId'],
        'codigoBarras':
            codigoBarras.isNotEmpty
                ? codigoBarras
                : (existing['codigoBarras'] ?? '').toString(),
        'categoria': existingCategory,
      };
    } else {
      nuevoCarrito.add({
        'nombre': nombre,
        'precio': precio,
        'image': (articulo['image'] ?? '').toString(),
        'kg': 1.0,
        'total': precio,
        'articuloId': articuloId,
        'codigoBarras': codigoBarras,
        'categoria': categoria,
      });
    }

    await _actualizarCarritoActivo(nuevoCarrito);

    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            existingIndex >= 0
                ? '$nombre actualizado a '
                    '${ProductCategory.formatQuantityForCart(nuevaCantidad, categoria)}.'
                : '$nombre agregado a la caja.',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  Future<void> _procesarCodigoEnCaja(String codigo) async {
    final barcode = codigo.trim();
    if (barcode.isEmpty) return;

    final helper = DatabaseHelper();
    var articulo = await helper.getArticuloPorCodigoBarras(barcode);

    if (articulo == null) {
      if (!mounted) return;

      final crear =
          await showDialog<bool>(
            context: context,
            builder:
                (dialogContext) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  icon: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.orange,
                    size: 42,
                  ),
                  title: const Text(
                    'Producto no registrado',
                    textAlign: TextAlign.center,
                  ),
                  content: Text(
                    'No existe un artículo con el código:\n\n'
                    '$barcode\n\n'
                    '¿Deseas registrarlo ahora?',
                    textAlign: TextAlign.center,
                  ),
                  actionsAlignment: MainAxisAlignment.spaceBetween,
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Crear artículo'),
                    ),
                  ],
                ),
          ) ??
          false;

      if (!crear || !mounted) return;

      final saved = await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => AddArticlePage(
                codigoBarrasInicial: barcode,
                categoriaInicial: ProductCategory.groceries,
              ),
        ),
      );

      if (saved != true || !mounted) return;

      await _cargarArticulos();
      articulo = await helper.getArticuloPorCodigoBarras(barcode);

      if (articulo == null || !mounted) {
        return;
      }
    }

    await _agregarArticuloEscaneadoEnCaja(articulo);
  }

  Future<void> _procesarCodigoGlobal(String codigo) async {
    try {
      if (widget.isSelectorMode || _currentIndex == 3) {
        await _procesarCodigoEnArticulos(codigo);
      } else if (_currentIndex == 2) {
        await _procesarCodigoEnCaja(codigo);
      }
    } finally {
      _reactivarCapturaHid();
    }
  }

  void cambiarPestana(int index) {
    if (widget.isSelectorMode) {
      return;
    }

    // IndexedStack conserva vivas las otras pestañas. Por eso debemos quitar
    // explícitamente el foco del buscador antes de entrar a Caja.
    _liberarFocoDeEntrada();

    setState(() {
      _currentIndex = index;
    });

    _reactivarCapturaHid();

    _cargarArticulos();
    _cargarHistorialVentas();
    _cargarConfigFactura();
  }

  void _abrirMenu() {
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _confirmarCerrarSesion() async {
    if (_isSigningOut) {
      return;
    }

    final bool confirmar =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              icon: const Icon(
                Icons.logout_rounded,
                color: Colors.redAccent,
                size: 36,
              ),
              title: const Text('Cerrar sesión'),
              content: const Text(
                '¿Estás seguro de que deseas cerrar tu sesión?',
                textAlign: TextAlign.center,
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Cerrar sesión'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmar || !mounted) {
      return;
    }

    setState(() {
      _isSigningOut = true;
    });

    try {
      await FirebaseAuth.instance.signOut();

      // No se elimina ningún artículo, ticket ni producto del carrito.
      // main.dart escucha authStateChanges() y mostrará LoginPage.
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message ?? 'No fue posible cerrar la sesión. Intenta de nuevo.',
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No fue posible cerrar la sesión: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  int? get _diasRestantes {
    final DateTime? end = widget.subscriptionEnd;
    if (end == null) {
      return null;
    }

    final Duration difference = end.toLocal().difference(DateTime.now());
    if (difference <= Duration.zero) {
      return 0;
    }

    return (difference.inMinutes / Duration.minutesPerDay).ceil();
  }

  String get _textoDiasRestantes {
    final int? days = _diasRestantes;

    if (days == null) {
      return widget.isOfflineAccess
          ? 'Información no disponible sin conexión'
          : 'Sin fecha de vencimiento';
    }

    if (days == 0) {
      return 'Vence hoy';
    }

    if (days == 1) {
      return '1 día restante';
    }

    return '$days días restantes';
  }

  String get _fechaVencimientoFormateada {
    final DateTime? end = widget.subscriptionEnd;
    if (end == null) {
      return '';
    }

    final DateTime local = end.toLocal();
    const List<String> months = <String>[
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];

    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  Widget _buildDrawer() {
    final User? usuario = FirebaseAuth.instance.currentUser;
    final String? displayName = usuario?.displayName?.trim();

    final String nombre =
        displayName != null && displayName.isNotEmpty ? displayName : 'Usuario';

    final String correo = usuario?.email ?? 'Sin correo registrado';
    final String inicial =
        nombre.trim().isNotEmpty
            ? nombre.trim().substring(0, 1).toUpperCase()
            : 'U';

    final double drawerWidth =
        (MediaQuery.sizeOf(context).width * 0.86)
            .clamp(280.0, 340.0)
            .toDouble();

    return Drawer(
      width: drawerWidth,
      backgroundColor: const Color(0xFFF5F7FB),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              decoration: BoxDecoration(
                // Mismo azul que la tarjeta seleccionada de Artículos.
                color: const Color(0xFF1565C0),

                // Redondeado arriba y abajo del lado derecho.
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),

                // Misma sombra que la opción seleccionada.
                boxShadow: [
                  BoxShadow(
                    color: const Color.fromARGB(
                      255,
                      0,
                      73,
                      156,
                    ).withOpacity(0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.16),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          inicial,
                          style: const TextStyle(
                            color: Color(0xFF1565C0),
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              correo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.76),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.11),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.16)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.workspace_premium_rounded,
                                color: Color(0xFF90CAF9),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'PLAN ACTUAL',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.62),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.planName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.isOfflineAccess)
                              const Icon(
                                Icons.cloud_off_rounded,
                                color: Color(0xFFFFCC80),
                                size: 19,
                              ),
                          ],
                        ),
                        const SizedBox(height: 11),
                        Container(
                          height: 1,
                          color: Colors.white.withOpacity(0.11),
                        ),
                        const SizedBox(height: 11),
                        Row(
                          children: [
                            Icon(
                              _diasRestantes == null
                                  ? Icons.verified_user_rounded
                                  : Icons.schedule_rounded,
                              color:
                                  _diasRestantes == 0
                                      ? const Color(0xFFFF8A80)
                                      : const Color(0xFF81C784),
                              size: 19,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _textoDiasRestantes,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_fechaVencimientoFormateada.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 27),
                              child: Text(
                                'Vence: $_fechaVencimientoFormateada',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.64),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 10),
                    child: Text(
                      'MENÚ PRINCIPAL',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.25,
                      ),
                    ),
                  ),
                  _buildDrawerOption(
                    icon: Icons.history_rounded,
                    title: 'Historial',
                    subtitle: 'Consulta tus ventas',
                    index: 1,
                  ),
                  const SizedBox(height: 8),
                  _buildDrawerOption(
                    icon: Icons.point_of_sale_rounded,
                    title: 'Caja',
                    subtitle: 'Gestiona tus cobros',
                    index: 2,
                  ),
                  const SizedBox(height: 8),
                  _buildDrawerOption(
                    icon: Icons.inventory_2_outlined,
                    title: 'Artículos',
                    subtitle: 'Administra tu catálogo',
                    index: 3,
                  ),
                  const SizedBox(height: 28),
                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 10),
                    child: Text(
                      'CATÁLOGO Y RESPALDO',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.25,
                      ),
                    ),
                  ),
                  _buildDrawerActionOption(
                    icon: Icons.file_download_outlined,
                    title: 'Importar catálogo',
                    subtitle: 'Carga productos desde otro dispositivo',
                    onTap: _importarCatalogo,
                  ),
                  const SizedBox(height: 10),
                  _buildDrawerActionOption(
                    icon: Icons.ios_share_rounded,
                    title: 'Exportar catálogo',
                    subtitle: 'Comparte productos e imágenes',
                    onTap: _exportarCatalogo,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(17),
                  onTap:
                      _isSigningOut
                          ? null
                          : () async {
                            _scaffoldKey.currentState?.closeDrawer();

                            await Future<void>.delayed(
                              const Duration(milliseconds: 180),
                            );

                            if (mounted) {
                              await _confirmarCerrarSesion();
                            }
                          },
                  child: Ink(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE4E6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child:
                              _isSigningOut
                                  ? const SizedBox(
                                    width: 19,
                                    height: 19,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Color(0xFFE11D48),
                                    ),
                                  )
                                  : const Icon(
                                    Icons.logout_rounded,
                                    color: Color(0xFFE11D48),
                                    size: 21,
                                  ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _isSigningOut
                                ? 'Cerrando sesión...'
                                : 'Cerrar sesión',
                            style: const TextStyle(
                              color: Color(0xFFBE123C),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!_isSigningOut)
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFFFB7185),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required int index,
  }) {
    final bool selected = _currentIndex == index;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          _scaffoldKey.currentState?.closeDrawer();
          cambiarPestana(index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1565C0) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color:
                  selected ? const Color(0xFF1565C0) : const Color(0xFFE6EBF2),
            ),
            boxShadow: [
              BoxShadow(
                color:
                    selected
                        ? const Color(0xFF1565C0).withOpacity(0.22)
                        : const Color(0xFF0F172A).withOpacity(0.045),
                blurRadius: selected ? 18 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color:
                      selected
                          ? Colors.white.withOpacity(0.16)
                          : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  color: selected ? Colors.white : const Color(0xFF1565C0),
                  size: 22,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color:
                            selected ? Colors.white : const Color(0xFF172033),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color:
                            selected
                                ? Colors.white.withOpacity(0.72)
                                : const Color(0xFF7A8799),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color:
                    selected
                        ? Colors.white.withOpacity(0.84)
                        : const Color(0xFFB4BFCD),
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _ejecutarAccionDesdeDrawer(
    Future<void> Function() action,
  ) async {
    _scaffoldKey.currentState?.closeDrawer();

    // Espera a que termine la animación del Drawer antes de abrir
    // el selector de archivos o mostrar cuadros de diálogo.
    await Future<void>.delayed(const Duration(milliseconds: 230));

    if (!mounted) {
      return;
    }

    await action();
  }

  Widget _buildDrawerActionOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Future<void> Function() onTap,
  }) {
    final bool disabled = _catalogTransferBusy;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: disabled ? null : () => _ejecutarAccionDesdeDrawer(onTap),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: disabled ? 0.58 : 1,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFDDE8E2)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF102A2A).withOpacity(0.045),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F4EE),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child:
                      disabled
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Color(0xFF1F8A62),
                            ),
                          )
                          : Icon(
                            icon,
                            color: const Color(0xFF1F8A62),
                            size: 22,
                          ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF22312D),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF73817C),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFAAB6B1),
                  size: 21,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _procesarCodigoEnArticulos(String codigo) async {
    final barcode = codigo.trim();
    if (barcode.isEmpty) return;

    final helper = DatabaseHelper();
    final articulo = await helper.getArticuloPorCodigoBarras(barcode);

    if (articulo != null) {
      FocusManager.instance.primaryFocus?.unfocus();
      _articulosSearchController
        ..text = barcode
        ..selection = TextSelection.collapsed(offset: barcode.length);
      return;
    }

    if (!mounted) return;

    final crear =
        await showDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                icon: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.orange,
                  size: 42,
                ),
                title: const Text(
                  'Producto no registrado',
                  textAlign: TextAlign.center,
                ),
                content: Text(
                  'No existe un artículo con el código:\n\n'
                  '$barcode\n\n'
                  '¿Deseas registrarlo ahora?',
                  textAlign: TextAlign.center,
                ),
                actionsAlignment: MainAxisAlignment.spaceBetween,
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Crear artículo'),
                  ),
                ],
              ),
        ) ??
        false;

    if (!crear || !mounted) return;

    final saved = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => AddArticlePage(
              codigoBarrasInicial: barcode,
              categoriaInicial: ProductCategory.groceries,
            ),
      ),
    );

    _reactivarCapturaHid();

    if (saved == true && mounted) {
      await _cargarArticulos();
      _articulosSearchController
        ..text = barcode
        ..selection = TextSelection.collapsed(offset: barcode.length);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Artículo guardado correctamente'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _procesarBusquedaComoCodigo(String value) {
    final candidate = value.trim();

    // Los códigos del lector de abarrotes son numéricos. Evitamos abrir el
    // aviso de producto nuevo cuando el usuario simplemente busca por nombre.
    if (!RegExp(r'^\d{4,}$').hasMatch(candidate)) {
      return;
    }

    _procesarCodigoEnArticulos(candidate);
  }

  PreferredSizeWidget _buildSelectorAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.blue),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'SELECCIONAR ARTÍCULO',
        style: TextStyle(
          color: Colors.blue,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(66),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: TextField(
            controller: _articulosSearchController,
            focusNode: _articulosSearchFocusNode,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            onSubmitted: _procesarBusquedaComoCodigo,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o código...',
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.blue),
              suffixIcon:
                  _articulosSearchController.text.isEmpty
                      ? null
                      : IconButton(
                        onPressed: _articulosSearchController.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PreferredSizeWidget appBaToUse;

    if (widget.isSelectorMode) {
      appBaToUse = _buildSelectorAppBar();
    } else if (_currentIndex == 1) {
      appBaToUse = ArticlesHeader(
        title: 'Historial',
        hintText: 'Buscar por folio, cliente, fecha o total...',
        searchController: _historialSearchController,
        searchFocusNode: _historialSearchFocusNode,
        showScannerIcons: false,
        onMenuPressed: _abrirMenu,
      );
    } else if (_currentIndex == 2) {
      appBaToUse = ArticlesHeader(
        title: 'Caja',
        onMenuPressed: _abrirMenu,
        showSearchBar: false,
      );
    } else {
      appBaToUse = ArticlesHeader(
        title: 'Artículos',
        hintText: 'Buscar por nombre o código...',
        searchController: _articulosSearchController,
        searchFocusNode: _articulosSearchFocusNode,
        showScannerIcons: true,
        onMenuPressed: _abrirMenu,
        onSearchSubmitted: _procesarBusquedaComoCodigo,
      );
    }

    final bool scannerEnabled =
        widget.isSelectorMode || _currentIndex == 2 || _currentIndex == 3;

    return BarcodeHidListener(
      enabled: scannerEnabled,
      focusNode: _scannerFocusNode,
      captureWhenEditableFocused: true,
      unfocusEditableOnCapture: true,
      permittedEditableFocusNode:
          widget.isSelectorMode || _currentIndex == 3
              ? _articulosSearchFocusNode
              : null,
      onBarcode: _procesarCodigoGlobal,
      child: Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: false,
        drawer: widget.isSelectorMode ? null : _buildDrawer(),
        appBar: appBaToUse,
        body:
            widget.isSelectorMode
                ? _buildCatalogoGrid()
                : IndexedStack(
                  index: _currentIndex,
                  children: [
                    const Center(
                      child: Text('Pantalla de Informes (PROXIMAMENTE)'),
                    ),
                    HistorialPage(
                      ventasHistorial: historyTickets,
                      nombreNegocio: nombreNegocio,
                      direccionNegocio: direccionNegocio,
                      onConfigUpdate: (nombre, direccion) {
                        setState(() {
                          nombreNegocio = nombre;
                          direccionNegocio = direccion;
                        });
                      },
                      onTicketDeleted: _cargarHistorialVentas,
                      searchController: _historialSearchController,
                    ),
                    CajaPage(
                      cartItems: checkoutCart,
                      cajasClientes: cajasClientes,
                      cajaActivaIndex: cajaActivaIndex,
                      siguienteNumeroCliente: _ticketCounter,
                      onIrAlCatalogo: () => cambiarPestana(3),
                      onActualizarCarrito: _actualizarCarritoActivo,
                      onNuevaCaja: _crearNuevaCaja,
                      onSeleccionarCaja: _seleccionarCaja,
                      onEliminarCaja: _eliminarCaja,
                      onRenombrarCajaActiva: _renombrarCajaActiva,
                      scannerEnabled: _currentIndex == 2,
                      onVentaExitosa: (ticketFinalizado) async {
                        final String idCajaCobrada = cajaActivaId;

                        if (cajasClientes.length > 1) {
                          final int indexCerrado = cajaActivaIndex;

                          setState(() {
                            cajasClientes.removeAt(indexCerrado);

                            if (cajaActivaIndex >= cajasClientes.length) {
                              cajaActivaIndex = cajasClientes.length - 1;
                            }

                            if (cajaActivaIndex < 0) {
                              cajaActivaIndex = 0;
                            }
                          });

                          await DatabaseHelper().eliminarCaja(idCajaCobrada);
                          await _sincronizarNombresAutomaticos();
                        } else {
                          await DatabaseHelper().limpiarCarritoDeCaja(
                            idCajaCobrada,
                          );

                          final int siguienteCliente =
                              await DatabaseHelper()
                                  .getSiguienteNumeroCliente();

                          final String nuevoNombre =
                              'Cliente #$siguienteCliente';

                          await DatabaseHelper().actualizarNombreCaja(
                            idCajaCobrada,
                            nuevoNombre,
                          );

                          if (mounted && cajasClientes.isNotEmpty) {
                            setState(() {
                              cajasClientes[cajaActivaIndex] = {
                                ...cajasClientes[cajaActivaIndex],
                                'nombre': nuevoNombre,
                                'items': <Map<String, dynamic>>[],
                              };
                            });
                          }
                        }

                        await _cargarHistorialVentas();
                        await _sincronizarNombresAutomaticos();
                      },
                    ),
                    _buildCatalogoGrid(),
                    const Center(child: Text('Pantalla de Más (PROXIMAMENTE)')),
                  ],
                ),
        bottomNavigationBar:
            widget.isSelectorMode
                ? null
                : BottomNav(currentIndex: _currentIndex, onTap: cambiarPestana),
      ),
    );
  }

  Future<void> _exportarCatalogo() async {
    if (_catalogTransferBusy) {
      return;
    }

    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Todavía no hay artículos para exportar.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _catalogTransferBusy = true;
    });

    try {
      final result = await CatalogBackupService.exportCatalog();

      if (!mounted) {
        return;
      }

      final imageWarning =
          result.missingImageCount > 0
              ? '\n${result.missingImageCount} imagen(es) no pudieron incluirse.'
              : '';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Catálogo exportado: ${result.productCount} productos y '
            '${result.imageCount} imágenes.\nGuardado en: ${result.savedPath}'
            '$imageWarning',
          ),
          backgroundColor: const Color(0xFF1F8A62),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo exportar el catálogo: $error'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _catalogTransferBusy = false;
        });
      }
    }
  }

  void _manejarCatalogoPendiente() {
    final filePath = CatalogIntentService.pendingCatalogPath.value;

    if (filePath == null ||
        filePath.trim().isEmpty ||
        _incomingCatalogBusy ||
        !mounted) {
      return;
    }

    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _manejarCatalogoPendiente();
        }
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _abrirCatalogoRecibido(filePath);
      }
    });
  }

  Future<void> _abrirCatalogoRecibido(String filePath) async {
    if (_incomingCatalogBusy || !mounted) {
      return;
    }

    _incomingCatalogBusy = true;

    _scaffoldKey.currentState?.closeDrawer();
    _liberarFocoDeEntrada();

    setState(() {
      _currentIndex = 3;
      _catalogTransferBusy = true;
    });

    CatalogImportPreview? preview;
    bool catalogoProcesado = false;

    try {
      preview = await CatalogBackupService.previewFromFilePath(filePath);
      catalogoProcesado = true;
    } on FormatException catch (error) {
      catalogoProcesado = true;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message.toString()),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      catalogoProcesado = true;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir el catálogo: $error'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (catalogoProcesado) {
        await CatalogIntentService.consume(filePath);
      }

      if (mounted) {
        setState(() {
          _catalogTransferBusy = false;
        });
      }
    }

    if (mounted && preview != null) {
      // Dejamos terminar el frame en el que Artículos pasa al frente para
      // evitar que el bottom sheet intente abrirse antes de que exista ruta.
      await Future<void>.delayed(const Duration(milliseconds: 120));

      if (mounted) {
        await _procesarPreviewImportacion(preview);
      }
    }

    _incomingCatalogBusy = false;
    await _refrescarCatalogoPendiente();
  }

  Future<void> _importarCatalogo() async {
    if (_catalogTransferBusy) {
      return;
    }

    setState(() {
      _catalogTransferBusy = true;
    });

    CatalogImportPreview? preview;

    try {
      preview = await CatalogBackupService.pickCatalog();
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message.toString()),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir el catálogo: $error'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _catalogTransferBusy = false;
        });
      }
    }

    if (!mounted || preview == null) {
      return;
    }

    await _procesarPreviewImportacion(preview);
  }

  Future<void> _procesarPreviewImportacion(
    CatalogImportPreview selectedPreview,
  ) async {
    if (!mounted) {
      return;
    }

    final mode = await _mostrarOpcionesImportacion(selectedPreview);

    if (!mounted || mode == null) {
      return;
    }

    if (mode == CatalogImportMode.replace) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(child: Text('Reemplazar catálogo')),
                ],
              ),
              content: Text(
                'Se eliminarán los ${products.length} artículos actuales '
                'y se cargarán ${selectedPreview.productCount} artículos del archivo. '
                'Las ventas y tickets guardados no se modificarán.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('CANCELAR'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1F8A62),
                  ),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('REEMPLAZAR'),
                ),
              ],
            ),
      );

      if (confirmed != true) {
        return;
      }
    }

    setState(() {
      _catalogTransferBusy = true;
    });

    try {
      final result = await CatalogBackupService.importCatalog(
        preview: selectedPreview,
        mode: mode,
      );

      await _cargarArticulos();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Catálogo importado. '
            'Nuevos: ${result.inserted}, '
            'actualizados: ${result.updated}, '
            'omitidos: ${result.skipped}.',
          ),
          backgroundColor: const Color(0xFF1F8A62),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo importar el catálogo: $error'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _catalogTransferBusy = false;
        });
      }
    }
  }

  Future<CatalogImportMode?> _mostrarOpcionesImportacion(
    CatalogImportPreview preview,
  ) {
    return showModalBottomSheet<CatalogImportMode>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (bottomSheetContext) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                14,
                18,
                18 + MediaQuery.paddingOf(bottomSheetContext).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7DEDA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Color(0xFFE6F4ED),
                        child: Icon(
                          Icons.inventory_2_outlined,
                          color: Color(0xFF1F8A62),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Importar catálogo',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF22312D),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F7F5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFDDE8E2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          preview.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${preview.productCount} productos · '
                          '${preview.imageCount} imágenes',
                          style: const TextStyle(color: Color(0xFF6F7D78)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildImportOption(
                    context: bottomSheetContext,
                    icon: Icons.sync_alt_rounded,
                    title: 'Reemplazar catálogo actual',
                    subtitle:
                        'Deja este teléfono exactamente igual al catálogo exportado.',
                    badge: 'RECOMENDADO',
                    onTap:
                        () => Navigator.pop(
                          bottomSheetContext,
                          CatalogImportMode.replace,
                        ),
                  ),
                  const SizedBox(height: 10),
                  _buildImportOption(
                    context: bottomSheetContext,
                    icon: Icons.playlist_add_rounded,
                    title: 'Agregar solo productos nuevos',
                    subtitle:
                        'Conserva los existentes y omite nombres repetidos.',
                    onTap:
                        () => Navigator.pop(
                          bottomSheetContext,
                          CatalogImportMode.addOnly,
                        ),
                  ),
                  const SizedBox(height: 10),
                  _buildImportOption(
                    context: bottomSheetContext,
                    icon: Icons.update_rounded,
                    title: 'Actualizar y agregar',
                    subtitle:
                        'Actualiza productos con el mismo nombre y agrega los faltantes.',
                    onTap:
                        () => Navigator.pop(
                          bottomSheetContext,
                          CatalogImportMode.updateAndAdd,
                        ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildImportOption({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: const Color(0xFFDDE5E1)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F4ED),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: const Color(0xFF1F8A62)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF22312D),
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F8A62),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              badge,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF71807A),
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF8A9892)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirNuevoArticulo({String codigoBarras = ''}) async {
    _liberarFocoDeEntrada();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => AddArticlePage(
              codigoBarrasInicial: codigoBarras.isEmpty ? null : codigoBarras,
              categoriaInicial:
                  codigoBarras.isEmpty ? null : ProductCategory.groceries,
            ),
      ),
    );

    _reactivarCapturaHid();

    if (result == true && mounted) {
      await _cargarArticulos();
      _reactivarCapturaHid();

      if (codigoBarras.isNotEmpty) {
        _articulosSearchController
          ..text = codigoBarras
          ..selection = TextSelection.collapsed(offset: codigoBarras.length);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Artículo guardado correctamente'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  double _toDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool _esMismoProducto(
    Map<String, dynamic> existente,
    Map<String, dynamic> nuevo,
  ) {
    final existingId = existente['articuloId'];
    final newId = nuevo['articuloId'];

    if (existingId != null && newId != null && existingId == newId) {
      return true;
    }

    final existingBarcode = (existente['codigoBarras'] ?? '').toString().trim();
    final newBarcode = (nuevo['codigoBarras'] ?? '').toString().trim();

    if (existingBarcode.isNotEmpty &&
        newBarcode.isNotEmpty &&
        existingBarcode == newBarcode) {
      return true;
    }

    final existingName =
        (existente['nombre'] ?? '').toString().trim().toLowerCase();
    final newName = (nuevo['nombre'] ?? '').toString().trim().toLowerCase();

    return existingName.isNotEmpty &&
        newName.isNotEmpty &&
        existingName == newName &&
        (existingId == null || newId == null) &&
        (existingBarcode.isEmpty || newBarcode.isEmpty);
  }

  List<Map<String, dynamic>> _agregarAlCarritoConPrecioActual(
    Map<String, dynamic> selectedItem,
  ) {
    final nuevoCarrito = List<Map<String, dynamic>>.from(checkoutCart);
    final selectedCategory = ProductCategory.normalize(
      selectedItem['categoria'],
      barcode: selectedItem['codigoBarras'],
    );

    // Cada pesada de un producto fresco pertenece a una compra independiente.
    // Aunque sea el mismo artículo, nunca se combina con una línea anterior.
    if (!ProductCategory.isGrocery(selectedCategory)) {
      nuevoCarrito.add({
        ...Map<String, dynamic>.from(selectedItem),
        'categoria': selectedCategory,
      });
      return nuevoCarrito;
    }

    // Los abarrotes sí se agrupan y aumentan sus piezas.
    final existingIndex = nuevoCarrito.indexWhere((item) {
      final itemCategory = ProductCategory.normalize(
        item['categoria'],
        barcode: item['codigoBarras'],
      );

      return ProductCategory.isGrocery(itemCategory) &&
          _esMismoProducto(item, selectedItem);
    });

    if (existingIndex < 0) {
      nuevoCarrito.add({
        ...Map<String, dynamic>.from(selectedItem),
        'categoria': selectedCategory,
      });
      return nuevoCarrito;
    }

    final existing = nuevoCarrito[existingIndex];
    final existingCategory = ProductCategory.normalize(
      existing['categoria'] ?? selectedItem['categoria'],
      barcode: existing['codigoBarras'] ?? selectedItem['codigoBarras'],
    );
    final existingPrice = _toDouble(
      existing['precio'],
      fallback: _toDouble(selectedItem['precio']),
    );
    final existingQuantity = _toDouble(existing['kg']);
    final addedQuantity = ProductCategory.normalizeQuantity(
      selectedItem['kg'],
      existingCategory,
      fallback: 1.0,
    );
    final newQuantity = ProductCategory.normalizeQuantity(
      existingQuantity + addedQuantity,
      existingCategory,
    );

    final existingTotal =
        ProductCategory.isGrocery(existingCategory)
            ? existingPrice * existingQuantity
            : _toDouble(
              existing['total'],
              fallback: existingPrice * existingQuantity,
            );

    final newTotal =
        ProductCategory.isGrocery(existingCategory)
            ? existingPrice * newQuantity
            : existingTotal + (existingPrice * addedQuantity);

    nuevoCarrito[existingIndex] = {
      ...existing,
      'precio': existingPrice,
      'kg': newQuantity,
      'total': newTotal,
      'articuloId': existing['articuloId'] ?? selectedItem['articuloId'],
      'codigoBarras':
          (existing['codigoBarras'] ?? '').toString().trim().isNotEmpty
              ? existing['codigoBarras']
              : selectedItem['codigoBarras'],
      'categoria': existingCategory,
    };

    return nuevoCarrito;
  }

  Future<void> _abrirProducto(
    Map<String, dynamic> product,
    int productIndex,
  ) async {
    _liberarFocoDeEntrada();

    final nombre = (product['nombre'] ?? '').toString();
    final imagePath = (product['image'] ?? '').toString();
    final precio =
        product['precio'] is num
            ? (product['precio'] as num).toDouble()
            : double.tryParse(product['precio']?.toString() ?? '') ?? 0.0;
    final codigoBarras = (product['codigoBarras'] ?? '').toString();
    final categoria = ProductCategory.normalize(
      product['categoria'],
      barcode: codigoBarras,
    );

    final result = await showArticleDetailModal(
      context,
      nombre,
      precio,
      imagePath.isNotEmpty ? File(imagePath) : null,
      productIndex,
      articuloId: product['id'] as int?,
      codigoBarras: codigoBarras,
      categoria: categoria,
    );

    _reactivarCapturaHid();

    if (result == null) return;

    if (result['wasDeletedDirectly'] == true) {
      final id = product['id'];
      if (id is int) {
        await DatabaseHelper().deleteArticulo(id);
        await _cargarArticulos();
        _reactivarCapturaHid();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$nombre" eliminado correctamente'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final updatedData = result['updatedArticle'];
    if (updatedData is! Map) return;

    final updated = Map<String, dynamic>.from(updatedData);
    final updatedImage =
        updated['image'] is File
            ? (updated['image'] as File).path
            : (updated['image'] ?? '').toString();
    final updatedPrice =
        updated['precio'] is num
            ? (updated['precio'] as num).toDouble()
            : double.tryParse(updated['precio']?.toString() ?? '') ?? 0.0;
    final updatedCategory = ProductCategory.normalize(
      updated['categoria'] ?? categoria,
      barcode: updated['codigoBarras'] ?? codigoBarras,
    );
    final quantity = ProductCategory.normalizeQuantity(
      updated['kg'],
      updatedCategory,
    );

    if (result['wasEditedDirectly'] == true) {
      final id = product['id'];
      if (id is int) {
        await DatabaseHelper().updateArticulo({
          'id': id,
          'nombre': updated['nombre'],
          'precio': updatedPrice,
          'image': updatedImage,
          'codigoBarras': (updated['codigoBarras'] ?? codigoBarras).toString(),
          'categoria': updatedCategory,
        });
        await _cargarArticulos();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Artículo actualizado correctamente'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final updatedTotal =
        updated['total'] is num
            ? (updated['total'] as num).toDouble()
            : updatedPrice * quantity;

    final selectedItem = <String, dynamic>{
      'nombre': updated['nombre'],
      'precio': updatedPrice,
      'image': updatedImage,
      'kg': quantity,
      'total': updatedTotal,
      'articuloId': updated['id'] ?? product['id'],
      'codigoBarras': (updated['codigoBarras'] ?? codigoBarras).toString(),
      'categoria': updatedCategory,
    };

    if (widget.isSelectorMode) {
      Navigator.pop(context, selectedItem);
      return;
    }

    final bool yaExistia =
        ProductCategory.isGrocery(updatedCategory) &&
        checkoutCart.any((item) {
          final itemCategory = ProductCategory.normalize(
            item['categoria'],
            barcode: item['codigoBarras'],
          );

          return ProductCategory.isGrocery(itemCategory) &&
              _esMismoProducto(item, selectedItem);
        });
    final nuevoCarrito = _agregarAlCarritoConPrecioActual(selectedItem);

    await _actualizarCarritoActivo(nuevoCarrito);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            yaExistia
                ? 'Cantidad actualizada conservando el precio de la caja.'
                : 'Producto agregado correctamente',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildNewArticleCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _abrirNuevoArticulo(),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Color(0xFFE8F3FF),
                child: Icon(Icons.add_rounded, color: Colors.blue),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nuevo artículo',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Crear un producto para el catálogo',
                      style: TextStyle(color: Colors.black54, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.blue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryHeader(String category, int count) {
    final isGrocery = ProductCategory.isGrocery(category);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color:
                  isGrocery ? const Color(0xFFFFF2DF) : const Color(0xFFE7F6ED),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(
              isGrocery ? Icons.inventory_2_outlined : Icons.eco_outlined,
              color:
                  isGrocery ? const Color(0xFFE78413) : const Color(0xFF1F8A62),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ProductCategory.label(category),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product, int index) {
    final name = (product['nombre'] ?? '').toString();
    final imagePath = (product['image'] ?? '').toString();
    final price =
        product['precio'] is num
            ? (product['precio'] as num).toDouble()
            : double.tryParse(product['precio']?.toString() ?? '') ?? 0.0;
    final category = ProductCategory.normalize(
      product['categoria'],
      barcode: product['codigoBarras'],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirProducto(product, index),
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(8),
                color: const Color(0xFFF7F8FA),
                child:
                    imagePath.isNotEmpty
                        ? Image.file(
                          File(imagePath),
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          filterQuality: FilterQuality.medium,
                          errorBuilder:
                              (_, __, ___) => const Center(
                                child: Icon(
                                  Icons.insert_photo_outlined,
                                  size: 46,
                                  color: Colors.grey,
                                ),
                              ),
                        )
                        : const Center(
                          child: Icon(
                            Icons.insert_photo_outlined,
                            size: 46,
                            color: Colors.grey,
                          ),
                        ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 7, 6, 2),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '\$${price.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                ProductCategory.isGrocery(category)
                    ? 'Por pieza'
                    : 'Por kilogramo',
                style: const TextStyle(color: Colors.black45, fontSize: 10.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid(List<Map<String, dynamic>> categoryProducts) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 5 : 3;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: categoryProducts.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.70,
          ),
          itemBuilder: (context, index) {
            final product = categoryProducts[index];
            final originalIndex = products.indexWhere(
              (item) => item['id'] == product['id'],
            );
            return _buildProductCard(
              product,
              originalIndex >= 0 ? originalIndex : index,
            );
          },
        );
      },
    );
  }

  Widget _buildCatalogoGrid() {
    final groceries =
        filteredProducts
            .where(
              (product) => ProductCategory.isGrocery(
                ProductCategory.normalize(
                  product['categoria'],
                  barcode: product['codigoBarras'],
                ),
              ),
            )
            .toList()
          ..sort(
            (a, b) => (a['nombre'] ?? '').toString().toLowerCase().compareTo(
              (b['nombre'] ?? '').toString().toLowerCase(),
            ),
          );

    final fresh =
        filteredProducts
            .where(
              (product) =>
                  !ProductCategory.isGrocery(
                    ProductCategory.normalize(
                      product['categoria'],
                      barcode: product['codigoBarras'],
                    ),
                  ),
            )
            .toList()
          ..sort(
            (a, b) => (a['nombre'] ?? '').toString().toLowerCase().compareTo(
              (b['nombre'] ?? '').toString().toLowerCase(),
            ),
          );

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          sliver: SliverToBoxAdapter(child: _buildNewArticleCard()),
        ),
        if (groceries.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            sliver: SliverToBoxAdapter(
              child: _buildCategoryHeader(
                ProductCategory.groceries,
                groceries.length,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            sliver: SliverToBoxAdapter(child: _buildCategoryGrid(groceries)),
          ),
        ],
        if (fresh.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            sliver: SliverToBoxAdapter(
              child: _buildCategoryHeader(ProductCategory.fresh, fresh.length),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            sliver: SliverToBoxAdapter(child: _buildCategoryGrid(fresh)),
          ),
        ],
        if (groceries.isEmpty && fresh.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _articulosSearchController.text.trim().isEmpty
                      ? 'Todavía no hay artículos registrados.'
                      : 'No hay productos que coincidan con la búsqueda.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 15),
                ),
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
