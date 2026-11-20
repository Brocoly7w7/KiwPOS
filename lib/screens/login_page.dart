// lib/screens/login_page.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/device_session_service.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.initialMessage, this.onLoginSuccess});

  final String? initialMessage;
  final VoidCallback? onLoginSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const Color _azul = Color(0xFF2196F3);
  static const Color _azulOscuro = Color(0xFF0D1B2A);
  static const Color _verde = Color(0xFF4CAF50);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final DeviceSessionService _deviceSessionService = DeviceSessionService();

  static const String _serverClientId =
      String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');

  static final Future<void> _googleSignInInitialization =
      kIsWeb
          ? Future<void>.value()
          : GoogleSignIn.instance.initialize(serverClientId: _serverClientId);

  bool _isLoading = false;
  bool _obscurePassword = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _errorMessage = widget.initialMessage ?? '';
  }

  @override
  void didUpdateWidget(covariant LoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.initialMessage != oldWidget.initialMessage &&
        widget.initialMessage != null &&
        widget.initialMessage!.isNotEmpty) {
      _errorMessage = widget.initialMessage!;
    }
  }

  Future<void> _login() async {
    final bool isValid = _formKey.currentState?.validate() ?? false;

    if (!isValid || _isLoading) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    bool loginSucceeded = false;
    await _deviceSessionService.beginInteractiveLogin();

    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      loginSucceeded = true;
      widget.onLoginSuccess?.call();
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        switch (e.code) {
          case 'user-not-found':
          case 'wrong-password':
          case 'invalid-credential':
            _errorMessage = 'Correo o contraseña incorrectos.';
            break;
          case 'invalid-email':
            _errorMessage = 'El formato del correo no es válido.';
            break;
          case 'user-disabled':
            _errorMessage =
                'Su cuenta ha sido inhabilitada. Por favor, contacte al administrador.';
            break;
          case 'too-many-requests':
            _errorMessage =
                'Demasiados intentos. Espera un momento e inténtalo de nuevo.';
            break;
          default:
            _errorMessage = e.message ?? 'No fue posible iniciar sesión.';
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Ocurrió un error inesperado: $e';
      });
    } finally {
      if (!loginSucceeded) {
        await _deviceSessionService.cancelInteractiveLogin();
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    bool loginSucceeded = false;
    await _deviceSessionService.beginInteractiveLogin();

    try {
      if (kIsWeb) {
        final GoogleAuthProvider provider = GoogleAuthProvider();
        await _auth.signInWithPopup(provider);
        loginSucceeded = true;
        widget.onLoginSuccess?.call();
        return;
      }

      await _googleSignInInitialization;

      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        throw StateError('Google no devolvió un ID token válido.');
      }

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );

      await _auth.signInWithCredential(credential);
      loginSucceeded = true;
      widget.onLoginSuccess?.call();
    } on GoogleSignInException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        if (e.code == GoogleSignInExceptionCode.canceled) {
          _errorMessage = 'Se canceló el inicio de sesión con Google.';
        } else {
          _errorMessage =
              e.description ?? 'No fue posible iniciar sesión con Google.';
        }
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        if (e.code == 'popup-closed-by-user' ||
            e.code == 'cancelled-popup-request') {
          _errorMessage = 'Se canceló el inicio de sesión con Google.';
        } else if (e.code == 'account-exists-with-different-credential') {
          _errorMessage =
              'Ya existe una cuenta con ese correo usando otro método.';
        } else {
          _errorMessage =
              e.message ?? 'No fue posible iniciar sesión con Google.';
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Error al iniciar sesión con Google: $e';
      });
    } finally {
      if (!loginSucceeded) {
        await _deviceSessionService.cancelInteractiveLogin();
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _abrirRegistro() async {
    FocusScope.of(context).unfocus();

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const RegisterPage(),
      ),
    );
  }

  Future<void> _mostrarRecuperarPassword() async {
    final String email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Escribe tu correo electrónico para recuperar tu contraseña.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      await _auth.setLanguageCode('es');
      await _auth.sendPasswordResetEmail(email: email);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Se envió un correo de recuperación a $email'),
          backgroundColor: _verde,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'No fue posible enviar el correo.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Widget _buildKiwLogo({double scale = 1}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 126 * scale,
          height: 80 * scale,
          child: CustomPaint(painter: const _KiwLogoPainter()),
        ),
        SizedBox(height: 1 * scale),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'kiw',
                style: TextStyle(
                  color: _azulOscuro,
                  fontSize: 39 * scale,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: -0.8 * scale,
                ),
              ),
              TextSpan(
                text: 'POS',
                style: TextStyle(
                  color: _verde,
                  fontSize: 39 * scale,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: -0.8 * scale,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    bool obscure = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    Widget? suffixIcon,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autocorrect: false,
      onFieldSubmitted: onFieldSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _azul),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _azul, width: 1.7),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.7),
        ),
      ),
      validator: validator,
    );
  }

  Widget _authButton({
    required Widget icon,
    required String text,
    required VoidCallback? onPressed,
    Color borderColor = _azul,
  }) {
    return OutlinedButton(
      onPressed: _isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        foregroundColor: _azulOscuro,
        side: BorderSide(color: borderColor),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'o continuar con',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }

  Widget _buildGoogleLogo() {
    // Ambos botones reservan exactamente el mismo espacio para su icono.
    // El dibujo de Google se reduce un poco para igualar visualmente el
    // tamaño del glifo de Apple, que tiene márgenes internos en su icono.
    return const SizedBox(
      width: 26,
      height: 26,
      child: Center(
        child: SizedBox(
          width: 21,
          height: 21,
          child: CustomPaint(painter: _GoogleLogoPainter()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.sizeOf(context).height;
    final bool compact = height < 760;

    final double logoScale = compact ? 0.72 : 0.82;
    final double topGap = compact ? 58 : 74;
    final double gapAfterLogo = compact ? 12 : 20;
    final double gapBeforeFields = compact ? 20 : 28;
    final double bottomSpacer = compact ? 8 : 16;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _LoginWavePainter()),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: topGap),
                        _buildKiwLogo(scale: logoScale),
                        SizedBox(height: gapAfterLogo),

                        const Text(
                          '¡Bienvenido de vuelta!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: _azulOscuro,
                          ),
                        ),

                        const SizedBox(height: 7),

                        Text(
                          'Inicia sesión para continuar',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.3,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        SizedBox(height: gapBeforeFields),

                        _buildTextField(
                          controller: _emailController,
                          label: 'Correo electrónico',
                          icon: Icons.person_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          validator: (String? value) {
                            final String email = value?.trim() ?? '';

                            if (email.isEmpty) {
                              return 'Por favor ingresa tu correo';
                            }

                            if (!email.contains('@') || !email.contains('.')) {
                              return 'Ingresa un correo válido';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 15),

                        _buildTextField(
                          controller: _passwordController,
                          label: 'Contraseña',
                          icon: Icons.lock_outline_rounded,
                          obscure: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _login(),
                          suffixIcon: IconButton(
                            tooltip:
                                _obscurePassword
                                    ? 'Mostrar contraseña'
                                    : 'Ocultar contraseña',
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.grey.shade600,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          validator: (String? value) {
                            if (value == null || value.isEmpty) {
                              return 'Por favor ingresa tu contraseña';
                            }

                            if (value.length < 6) {
                              return 'La contraseña debe tener al menos 6 caracteres';
                            }

                            return null;
                          },
                        ),

                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed:
                                _isLoading ? null : _mostrarRecuperarPassword,
                            child: const Text(
                              '¿Olvidaste tu contraseña?',
                              style: TextStyle(
                                color: _azul,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),

                        if (_errorMessage.isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.redAccent.withOpacity(0.25),
                              ),
                            ),
                            child: Text(
                              _errorMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        _isLoading
                            ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: CircularProgressIndicator(),
                            )
                            : Column(
                              children: [
                                ElevatedButton(
                                  onPressed: _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _azul,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(
                                      double.infinity,
                                      56,
                                    ),
                                    elevation: 4,
                                    shadowColor: _azul.withOpacity(0.35),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  ),
                                  child: const Text(
                                    'Iniciar sesión',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 20),

                                _divider(),

                                const SizedBox(height: 15),

                                _authButton(
                                  icon: _buildGoogleLogo(),
                                  text: 'Continuar con Google',
                                  onPressed: _signInWithGoogle,
                                ),

                                const SizedBox(height: 14),

                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.70),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '¿No tienes cuenta? ',
                                        style: TextStyle(
                                          color: const Color.fromRGBO(
                                            13,
                                            27,
                                            42,
                                            1,
                                          ).withOpacity(0.68),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: _abrirRegistro,
                                        child: const Text(
                                          'Regístrate aquí',
                                          style: TextStyle(
                                            color: _azul,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                        SizedBox(height: bottomSpacer),

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            'Versión 1.0.0',
                            style: TextStyle(
                              color: Color.fromRGBO(13, 27, 42, 1),
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginWavePainter extends CustomPainter {
  const _LoginWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const Color azul = Color(0xFF2196F3);
    const Color verde = Color(0xFF4CAF50);

    // Onda azul principal: más delgada y con una silueta asimétrica.
    // Se usan varios tramos cúbicos para evitar el aspecto de semicírculo.
    final Paint bluePaint =
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF1E88E5), Color(0xFF42A5F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.16));

    final Path bluePath =
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, size.height * 0.008)
          ..cubicTo(
            size.width * 0.94,
            size.height * 0.014,
            size.width * 0.88,
            size.height * 0.038,
            size.width * 0.80,
            size.height * 0.055,
          )
          ..cubicTo(
            size.width * 0.70,
            size.height * 0.078,
            size.width * 0.61,
            size.height * 0.062,
            size.width * 0.51,
            size.height * 0.096,
          )
          ..cubicTo(
            size.width * 0.39,
            size.height * 0.137,
            size.width * 0.21,
            size.height * 0.145,
            0,
            size.height * 0.115,
          )
          ..close();

    canvas.drawPath(bluePath, bluePaint);

    // Franja azul clara: fina y con una curva diferente a la principal.
    final Paint lightBluePaint = Paint()..color = azul.withOpacity(0.10);

    final Path lightBluePath =
        Path()
          // Curva superior: sigue la misma forma de la onda azul
          // y se superpone ligeramente para eliminar el espacio blanco.
          ..moveTo(0, size.height * 0.110)
          ..cubicTo(
            size.width * 0.21,
            size.height * 0.140,
            size.width * 0.39,
            size.height * 0.132,
            size.width * 0.51,
            size.height * 0.092,
          )
          ..cubicTo(
            size.width * 0.61,
            size.height * 0.058,
            size.width * 0.70,
            size.height * 0.074,
            size.width * 0.80,
            size.height * 0.051,
          )
          ..cubicTo(
            size.width * 0.88,
            size.height * 0.034,
            size.width * 0.94,
            size.height * 0.010,
            size.width,
            size.height * 0.004,
          )
          // Curva inferior de la franja azul clara.
          ..lineTo(size.width, size.height * 0.065)
          ..cubicTo(
            size.width * 0.82,
            size.height * 0.103,
            size.width * 0.67,
            size.height * 0.095,
            size.width * 0.52,
            size.height * 0.132,
          )
          ..cubicTo(
            size.width * 0.34,
            size.height * 0.177,
            size.width * 0.17,
            size.height * 0.170,
            0,
            size.height * 0.155,
          )
          ..close();

    canvas.drawPath(lightBluePath, lightBluePaint);

    // Onda verde principal: se mantiene cerca del borde inferior para que
    // no invada los botones ni el enlace de registro.
    final Paint greenPaint =
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ).createShader(
            Rect.fromLTWH(
              0,
              size.height * 0.84,
              size.width,
              size.height * 0.16,
            ),
          );

    final Path greenPath =
        Path()
          ..moveTo(0, size.height * 0.965)
          ..cubicTo(
            size.width * 0.15,
            size.height * 0.895,
            size.width * 0.34,
            size.height * 0.940,
            size.width * 0.52,
            size.height * 0.910,
          )
          ..cubicTo(
            size.width * 0.70,
            size.height * 0.875,
            size.width * 0.86,
            size.height * 0.925,
            size.width,
            size.height * 0.855,
          )
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();

    canvas.drawPath(greenPath, greenPaint);

    // Franja verde clara, reducida y separada de la onda principal.
    final Paint lightGreenPaint = Paint()..color = verde.withOpacity(0.16);

    final Path lightGreenPath =
        Path()
          ..moveTo(0, size.height * 0.905)
          ..cubicTo(
            size.width * 0.20,
            size.height * 0.855,
            size.width * 0.39,
            size.height * 0.900,
            size.width * 0.57,
            size.height * 0.875,
          )
          ..cubicTo(
            size.width * 0.76,
            size.height * 0.845,
            size.width * 0.90,
            size.height * 0.885,
            size.width,
            size.height * 0.820,
          )
          ..lineTo(size.width, size.height * 0.875)
          ..cubicTo(
            size.width * 0.82,
            size.height * 0.925,
            size.width * 0.66,
            size.height * 0.895,
            size.width * 0.49,
            size.height * 0.925,
          )
          ..cubicTo(
            size.width * 0.30,
            size.height * 0.955,
            size.width * 0.14,
            size.height * 0.925,
            0,
            size.height * 0.955,
          )
          ..close();

    canvas.drawPath(lightGreenPath, lightGreenPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _KiwLogoPainter extends CustomPainter {
  const _KiwLogoPainter();

  static const double _designWidth = 100;
  static const double _designHeight = 64;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale =
        (size.width / _designWidth < size.height / _designHeight
            ? size.width / _designWidth
            : size.height / _designHeight);

    final double offsetX = (size.width - (_designWidth * scale)) / 2;
    final double offsetY = (size.height - (_designHeight * scale)) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    canvas.scale(scale);

    final Paint bluePaint =
        Paint()
          ..isAntiAlias = true
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF2EA5F3), Color(0xFF0B68D1)],
          ).createShader(
            const Rect.fromLTWH(0, 0, _designWidth, _designHeight),
          );

    final Paint greenPaint =
        Paint()
          ..isAntiAlias = true
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF59C95C), Color(0xFF2D9D3E)],
          ).createShader(
            const Rect.fromLTWH(0, 0, _designWidth, _designHeight),
          );

    // Líneas de velocidad: mantienen el pequeño espacio del logo original.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2, 13, 22, 5),
        const Radius.circular(3),
      ),
      bluePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, 21, 16, 5),
        const Radius.circular(3),
      ),
      bluePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(12, 30, 12, 5),
        const Radius.circular(3),
      ),
      bluePaint,
    );

    // K dibujada como una figura propia. No depende de ninguna tipografía.
    final Path kPath =
        Path()
          ..moveTo(27, 2)
          ..lineTo(37, 2)
          ..lineTo(38, 23)
          ..lineTo(56, 3)
          ..quadraticBezierTo(57, 2, 59, 2)
          ..lineTo(70, 2)
          ..lineTo(48, 28)
          ..lineTo(64, 48)
          ..lineTo(50, 48)
          ..lineTo(39, 35)
          ..lineTo(38, 48)
          ..lineTo(27, 48)
          ..close();

    canvas.drawPath(kPath, bluePaint);

    // Canasta unida visualmente al brazo derecho de la K.
    final Path cartPath =
        Path()
          ..moveTo(55, 23)
          ..lineTo(96, 23)
          ..quadraticBezierTo(98, 23, 97, 26)
          ..lineTo(87, 47)
          ..quadraticBezierTo(86.5, 48, 84.5, 48)
          ..lineTo(66, 48)
          ..lineTo(49, 28)
          ..lineTo(53, 24)
          ..quadraticBezierTo(54, 23, 55, 23)
          ..close();

    canvas.drawPath(cartPath, greenPaint);

    // Ruedas con el mismo tamaño y alineación del logo de referencia.
    canvas.drawCircle(const Offset(34, 57), 6, greenPaint);
    canvas.drawCircle(const Offset(77, 57), 6, greenPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _KiwLogoPainter oldDelegate) => false;
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Logo oficial multicolor de Google, dibujado en una cuadrícula de 18 x 18.
    canvas.save();
    canvas.scale(size.width / 18, size.height / 18);

    final Paint paint = Paint()..style = PaintingStyle.fill;

    // Azul: parte derecha de la G.
    final Path bluePath =
        Path()
          ..moveTo(17.64, 9.205)
          ..cubicTo(17.64, 8.567, 17.583, 7.953, 17.476, 7.364)
          ..lineTo(9, 7.364)
          ..lineTo(9, 10.845)
          ..lineTo(13.844, 10.845)
          ..cubicTo(13.635, 11.97, 12.99, 12.923, 12.047, 13.561)
          ..lineTo(12.047, 15.821)
          ..lineTo(14.956, 15.821)
          ..cubicTo(16.658, 14.255, 17.64, 11.947, 17.64, 9.205)
          ..close();
    paint.color = const Color(0xFF4285F4);
    canvas.drawPath(bluePath, paint);

    // Verde: parte inferior derecha.
    final Path greenPath =
        Path()
          ..moveTo(9, 18)
          ..cubicTo(11.43, 18, 13.467, 17.194, 14.956, 15.82)
          ..lineTo(12.046, 13.561)
          ..cubicTo(11.241, 14.101, 10.211, 14.42, 9, 14.42)
          ..cubicTo(6.656, 14.42, 4.67, 12.835, 3.96, 10.705)
          ..lineTo(0.951, 10.705)
          ..lineTo(0.951, 13.037)
          ..cubicTo(2.429, 15.983, 5.477, 18, 9, 18)
          ..close();
    paint.color = const Color(0xFF34A853);
    canvas.drawPath(greenPath, paint);

    // Amarillo: parte inferior izquierda.
    final Path yellowPath =
        Path()
          ..moveTo(3.96, 10.705)
          ..cubicTo(3.782, 10.168, 3.682, 9.592, 3.682, 9)
          ..cubicTo(3.682, 8.408, 3.784, 7.832, 3.96, 7.295)
          ..lineTo(3.96, 4.963)
          ..lineTo(0.951, 4.963)
          ..cubicTo(0.347, 6.177, 0, 7.55, 0, 9)
          ..cubicTo(0, 10.45, 0.347, 11.823, 0.951, 13.037)
          ..lineTo(3.96, 10.705)
          ..close();
    paint.color = const Color(0xFFFBBC05);
    canvas.drawPath(yellowPath, paint);

    // Rojo: parte superior izquierda.
    final Path redPath =
        Path()
          ..moveTo(9, 3.58)
          ..cubicTo(10.321, 3.58, 11.507, 4.034, 12.44, 4.926)
          ..lineTo(15.022, 2.345)
          ..cubicTo(13.463, 0.892, 11.43, 0, 9, 0)
          ..cubicTo(5.477, 0, 2.429, 2.017, 0.951, 4.963)
          ..lineTo(3.96, 7.295)
          ..cubicTo(4.67, 5.165, 6.656, 3.58, 9, 3.58)
          ..close();
    paint.color = const Color(0xFFEA4335);
    canvas.drawPath(redPath, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
