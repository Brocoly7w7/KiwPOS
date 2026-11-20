// lib/screens/verify_email_page.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({
    super.key,
    required this.email,
    required this.onCheckVerification,
    required this.onResend,
    required this.onSignOut,
  });

  final String email;
  final Future<bool> Function() onCheckVerification;
  final Future<void> Function() onResend;
  final Future<void> Function() onSignOut;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  static const Color _blue = Color(0xFF2196F3);
  static const Color _darkBlue = Color(0xFF0D1B2A);
  static const Color _green = Color(0xFF4CAF50);

  bool _checking = false;
  bool _resending = false;

  Future<void> _check() async {
    if (_checking) {
      return;
    }

    setState(() => _checking = true);

    try {
      final bool verified = await widget.onCheckVerification();

      if (!mounted || verified) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El correo todavía no aparece como verificado. Abre el enlace recibido e inténtalo nuevamente.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'No fue posible comprobar el correo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible comprobar el correo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _resend() async {
    if (_resending) {
      return;
    }

    setState(() => _resending = true);

    try {
      await widget.onResend();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Se envió un nuevo correo a ${widget.email}.'),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }

      final String message =
          error.code == 'too-many-requests'
              ? 'Espera un momento antes de solicitar otro correo.'
              : error.message ?? 'No fue posible reenviar el correo.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No fue posible reenviar el correo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _resending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE3F2FD),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mark_email_unread_outlined,
                        size: 48,
                        color: _blue,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Verifica tu correo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _darkBlue,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Enviamos un enlace de verificación a:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.email,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _darkBlue,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Abre el enlace recibido. Después regresa a la aplicación y pulsa el botón para comprobarlo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 26),
                    FilledButton.icon(
                      onPressed: _checking ? null : _check,
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      icon:
                          _checking
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.verified_outlined),
                      label: Text(
                        _checking ? 'Comprobando...' : 'Ya verifiqué mi correo',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _resending ? null : _resend,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        foregroundColor: _darkBlue,
                        side: const BorderSide(color: _blue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      icon:
                          _resending
                              ? const SizedBox(
                                width: 19,
                                height: 19,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                              : const Icon(Icons.refresh_rounded),
                      label: Text(
                        _resending ? 'Enviando...' : 'Reenviar correo',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: widget.onSignOut,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text(
                        'Cerrar sesión',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
