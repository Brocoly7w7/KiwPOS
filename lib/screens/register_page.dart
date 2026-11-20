// lib/screens/register_page.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/device_session_service.dart';
import '../services/user_access_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  static const Color _blue = Color(0xFF2196F3);
  static const Color _darkBlue = Color(0xFF0D1B2A);
  static const Color _green = Color(0xFF4CAF50);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserAccessService _accessService = UserAccessService();
  final DeviceSessionService _deviceSessionService = DeviceSessionService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String _errorMessage = '';

  String? _validateInputs() {
    final String name = _nameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;
    final String confirmPassword = _confirmPasswordController.text;

    if (name.isEmpty) {
      return 'Ingresa tu nombre completo.';
    }

    if (name.length < 3) {
      return 'El nombre es demasiado corto.';
    }

    if (email.isEmpty) {
      return 'Ingresa tu correo electrónico.';
    }

    if (!email.contains('@') || !email.contains('.')) {
      return 'Ingresa un correo electrónico válido.';
    }

    if (password.isEmpty) {
      return 'Ingresa una contraseña.';
    }

    if (password.length < 6) {
      return 'La contraseña debe tener al menos 6 caracteres.';
    }

    if (confirmPassword.isEmpty) {
      return 'Confirma tu contraseña.';
    }

    if (password != confirmPassword) {
      return 'Las contraseñas no coinciden.';
    }

    return null;
  }

  void _clearError() {
    if (_errorMessage.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _errorMessage = '';
    });
  }

  Future<void> _register() async {
    if (_isLoading) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String? validationError = _validateInputs();
    if (validationError != null) {
      setState(() {
        _errorMessage = validationError;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    bool accountCreated = false;
    await _deviceSessionService.beginInteractiveLogin();

    try {
      final UserCredential credential = await _auth
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );

      accountCreated = true;

      final User? user = credential.user;
      if (user == null) {
        throw StateError('Firebase no devolvió el usuario creado.');
      }

      final String name = _nameController.text.trim();
      await user.updateDisplayName(name);
      await user.reload();

      final User refreshedUser = FirebaseAuth.instance.currentUser ?? user;

      try {
        await _accessService.createPendingEmailProfile(
          user: refreshedUser,
          name: name,
        );
      } catch (_) {
        // AccessGate podrá completar el perfil si hubo una interrupción.
      }

      await _auth.setLanguageCode('es');
      try {
        await refreshedUser.sendEmailVerification();
      } on FirebaseAuthException {
        // La pantalla de verificación permite reenviar el correo.
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        switch (error.code) {
          case 'email-already-in-use':
            _errorMessage =
                'Este correo ya está registrado. Inicia sesión o utiliza Google.';
            break;
          case 'invalid-email':
            _errorMessage = 'El formato del correo no es válido.';
            break;
          case 'weak-password':
            _errorMessage = 'La contraseña es demasiado débil.';
            break;
          case 'operation-not-allowed':
            _errorMessage =
                'El registro por correo no está habilitado en Firebase.';
            break;
          case 'network-request-failed':
            _errorMessage =
                'No fue posible conectarse. Revisa tu conexión a internet.';
            break;
          case 'too-many-requests':
            _errorMessage =
                'Se realizaron demasiados intentos. Espera un momento.';
            break;
          default:
            _errorMessage = error.message ?? 'No fue posible crear la cuenta.';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Ocurrió un error inesperado: $error';
      });
    } finally {
      if (!accountCreated) {
        await _deviceSessionService.cancelInteractiveLogin();
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    required bool compact,
    Widget? suffixIcon,
  }) {
    final BorderRadius borderRadius = BorderRadius.circular(15);

    return InputDecoration(
      hintText: label,
      hintStyle: TextStyle(
        color: Colors.grey.shade600,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(icon, color: _blue, size: compact ? 21 : 23),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      isDense: compact,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: compact ? 11 : 15,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: const BorderSide(color: _blue, width: 1.7),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool compact,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool obscureText = false,
    Iterable<String>? autofillHints,
    Widget? suffixIcon,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: !obscureText,
      autofillHints: autofillHints,
      onChanged: (_) => _clearError(),
      onSubmitted: onFieldSubmitted,
      decoration: _decoration(
        label: label,
        icon: icon,
        compact: compact,
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _buildHeader({required bool compact, required bool keyboardVisible}) {
    if (keyboardVisible) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 48 : 56,
          height: compact ? 48 : 56,
          decoration: BoxDecoration(
            color: _blue.withOpacity(0.11),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.person_add_alt_1_rounded,
            color: _blue,
            size: compact ? 27 : 31,
          ),
        ),
        SizedBox(height: compact ? 8 : 10),
        Text(
          'Regístrate con tu correo',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _darkBlue,
            fontSize: compact ? 21 : 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: compact ? 4 : 6),
        Text(
          'Crea tus datos de acceso para comenzar.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: compact ? 13 : 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage({required bool compact}) {
    if (_errorMessage.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 8 : 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage,
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar({required bool compact}) {
    return SizedBox(
      height: compact ? 44 : 50,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver al inicio de sesión',
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: Colors.white,
            disabledColor: Colors.white54,
          ),
          const SizedBox(width: 2),
          Text(
            'Crear cuenta',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 19 : 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final bool keyboardVisible = media.viewInsets.bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RegisterWavePainter(showBottomWave: !keyboardVisible),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool compact =
                    keyboardVisible ||
                    constraints.maxHeight < 720 ||
                    _errorMessage.isNotEmpty;
                final bool veryCompact = constraints.maxHeight < 540;

                final double horizontalPadding = compact ? 26 : 32;
                final double fieldGap = veryCompact ? 6 : (compact ? 8 : 11);
                final double headerGap = compact ? 10 : 16;
                final double topWaveGap =
                    keyboardVisible ? 2 : (compact ? 28 : 48);

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Column(
                        children: [
                          _buildTopBar(compact: compact),
                          SizedBox(height: topWaveGap),
                          _buildHeader(
                            compact: compact,
                            keyboardVisible: keyboardVisible,
                          ),
                          SizedBox(
                            height:
                                keyboardVisible
                                    ? 4
                                    : (compact ? headerGap : headerGap + 3),
                          ),
                          Expanded(
                            child: AutofillGroup(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  _buildField(
                                    controller: _nameController,
                                    label: 'Nombre completo',
                                    icon: Icons.badge_outlined,
                                    compact: compact,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const <String>[
                                      AutofillHints.name,
                                    ],
                                  ),
                                  SizedBox(height: fieldGap),
                                  _buildField(
                                    controller: _emailController,
                                    label: 'Correo electrónico',
                                    icon: Icons.mail_outline_rounded,
                                    compact: compact,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const <String>[
                                      AutofillHints.email,
                                    ],
                                  ),
                                  SizedBox(height: fieldGap),
                                  _buildField(
                                    controller: _passwordController,
                                    label: 'Contraseña',
                                    icon: Icons.lock_outline_rounded,
                                    compact: compact,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const <String>[
                                      AutofillHints.newPassword,
                                    ],
                                    suffixIcon: IconButton(
                                      tooltip:
                                          _obscurePassword
                                              ? 'Mostrar contraseña'
                                              : 'Ocultar contraseña',
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: Colors.grey.shade600,
                                        size: compact ? 21 : 23,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: fieldGap),
                                  _buildField(
                                    controller: _confirmPasswordController,
                                    label: 'Confirmar contraseña',
                                    icon: Icons.lock_reset_rounded,
                                    compact: compact,
                                    obscureText: _obscureConfirmPassword,
                                    textInputAction: TextInputAction.done,
                                    autofillHints: const <String>[
                                      AutofillHints.newPassword,
                                    ],
                                    onFieldSubmitted: (_) => _register(),
                                    suffixIcon: IconButton(
                                      tooltip:
                                          _obscureConfirmPassword
                                              ? 'Mostrar contraseña'
                                              : 'Ocultar contraseña',
                                      onPressed: () {
                                        setState(() {
                                          _obscureConfirmPassword =
                                              !_obscureConfirmPassword;
                                        });
                                      },
                                      icon: Icon(
                                        _obscureConfirmPassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: Colors.grey.shade600,
                                        size: compact ? 21 : 23,
                                      ),
                                    ),
                                  ),
                                  if (_errorMessage.isNotEmpty) ...[
                                    SizedBox(height: fieldGap),
                                    _buildErrorMessage(compact: compact),
                                  ],
                                  SizedBox(height: compact ? 12 : 17),
                                  ElevatedButton(
                                    onPressed: _isLoading ? null : _register,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _blue,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: _blue
                                          .withOpacity(0.55),
                                      minimumSize: Size(
                                        double.infinity,
                                        compact ? 49 : 55,
                                      ),
                                      elevation: 4,
                                      shadowColor: _blue.withOpacity(0.32),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                    ),
                                    child:
                                        _isLoading
                                            ? SizedBox(
                                              width: compact ? 21 : 23,
                                              height: compact ? 21 : 23,
                                              child:
                                                  const CircularProgressIndicator(
                                                    strokeWidth: 2.5,
                                                    color: Colors.white,
                                                  ),
                                            )
                                            : Text(
                                              'Crear mi cuenta',
                                              style: TextStyle(
                                                fontSize: compact ? 15 : 17,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                  ),
                                  if (!keyboardVisible) ...[
                                    SizedBox(height: compact ? 7 : 10),
                                    TextButton(
                                      onPressed:
                                          _isLoading
                                              ? null
                                              : () =>
                                                  Navigator.of(context).pop(),
                                      child: const Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: '¿Ya tienes cuenta? ',
                                              style: TextStyle(
                                                color: Color(0xFF66717E),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            TextSpan(
                                              text: 'Inicia sesión',
                                              style: TextStyle(
                                                color: _blue,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: compact ? 2 : 5),
                                    Container(
                                      width: double.infinity,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: compact ? 11 : 13,
                                        vertical: compact ? 5 : 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.78),
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.verified_user_outlined,
                                            color: _green,
                                            size: compact ? 16 : 18,
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              'Verifica tu correo y espera la autorización',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: _darkBlue.withOpacity(
                                                  0.72,
                                                ),
                                                fontSize: compact ? 10.5 : 11.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterWavePainter extends CustomPainter {
  const _RegisterWavePainter({required this.showBottomWave});

  final bool showBottomWave;

  @override
  void paint(Canvas canvas, Size size) {
    const Color blue = Color(0xFF2196F3);
    const Color green = Color(0xFF4CAF50);

    final Paint bluePaint =
        Paint()
          ..shader = const LinearGradient(
            colors: <Color>[Color(0xFF1E88E5), Color(0xFF42A5F5)],
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

    final Paint lightBluePaint = Paint()..color = blue.withOpacity(0.10);

    final Path lightBluePath =
        Path()
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

    if (!showBottomWave) {
      return;
    }

    final Paint greenPaint =
        Paint()
          ..shader = const LinearGradient(
            colors: <Color>[Color(0xFF66BB6A), Color(0xFF2E7D32)],
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

    final Paint lightGreenPaint = Paint()..color = green.withOpacity(0.16);

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
  bool shouldRepaint(covariant _RegisterWavePainter oldDelegate) {
    return oldDelegate.showBottomWave != showBottomWave;
  }
}
