import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pmr_music_room/objects/login_information.dart';
import 'package:pmr_music_room/services/google_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/session_storage.dart';

import '../config/constants.dart';
import '../network/account.dart';
import '../network/web_socket.dart';
import 'home.dart';

enum AuthMode { login, signup }

class LoginScreen extends StatefulWidget {
  static const routeName = '/login';

  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  AuthMode _mode = AuthMode.login;
  bool _isSubmitting = false;
  bool _showForgotPassword = false;

  @override
  void dispose() {
    _emailController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateDisplayName(String? value) {
    final displayName = value?.trim() ?? '';
    if (displayName.isEmpty) {
      return 'Display name is required';
    }
    if (displayName.length < 5) {
      return 'Display name must be at least 5 characters';
    }
    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(displayName)) {
      return 'Use only letters, numbers, and underscores';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Email is required';
    }

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      return 'Enter a valid email address';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) {
      return 'Password is required';
    }

    if (_mode == AuthMode.signup) {
      if (password.length < 8) {
        return 'Use at least 8 characters';
      }
      if (!RegExp(r'[A-Z]').hasMatch(password)) {
        return 'Add at least one uppercase letter';
      }
      if (!RegExp(r'[a-z]').hasMatch(password)) {
        return 'Add at least one lowercase letter';
      }
      if (!RegExp(r'[0-9]').hasMatch(password)) {
        return 'Add at least one number';
      }
      if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
        return 'Add at least one special character';
      }
      if (password.length < 6) {
        return 'Password must be at least 6 characters';
      }
    }

    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final confirmPassword = value ?? '';
    if (confirmPassword.isEmpty) {
      return 'Please confirm your password';
    }

    if (confirmPassword != _passwordController.text) {
      return 'Passwords do not match';
    }

    return null;
  }

  void _toggleMode(AuthMode mode) {
    if (_mode == mode) {
      return;
    }

    setState(() {
      _mode = mode;
      _displayNameController.clear();
      _confirmPasswordController.clear();
      _showForgotPassword = false;
    });
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid || _isSubmitting) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (_mode == AuthMode.login) {
      final result = await AccountService.login(email, password);
      if (!mounted) {
        return;
      }

      if (result.success && result.loginInformation != null) {
        await saveLoginInformation(result.loginInformation!);

        if (!mounted) {
          return;
        }

        context.go(HomeScreen.routeName);
      } else {
        final message = result.isEmailNotVerified
            ? 'Your email is not validated yet. Please check your inbox and click the validation link before logging in.'
            : result.message;

        setState(() {
          _showForgotPassword = true;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } else {
      final result = await AccountService.signup(
        email,
        _displayNameController.text.trim(),
        password,
        _confirmPasswordController.text,
      );

      if (!mounted) {
        return;
      }

      final message = result.success || result.isEmailNotVerified
          ? 'Account created. A confirmation email has been sent to $email. Please click the validation link before logging in.'
          : result.message;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      if (result.success || result.isEmailNotVerified) {
        setState(() {
          _mode = AuthMode.login;
          _displayNameController.clear();
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSignup = _mode == AuthMode.signup;

    return Scaffold(
      appBar: AppBar(title: const Text('Music Room Auth')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<AuthMode>(
                      key: const Key('login_mode_segmented_button'),
                      segments: const [
                        ButtonSegment<AuthMode>(
                          value: AuthMode.login,
                          label: Text('Login'),
                        ),
                        ButtonSegment<AuthMode>(
                          value: AuthMode.signup,
                          label: Text('Sign up'),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (selection) {
                        _toggleMode(selection.first);
                      },
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      key: const Key('login_email_field'),
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateEmail,
                    ),
                    if (isSignup) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('login_display_name_field'),
                        controller: _displayNameController,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateDisplayName,
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('login_password_field'),
                      controller: _passwordController,
                      obscureText: true,
                      autovalidateMode: isSignup
                          ? AutovalidateMode.onUserInteraction
                          : AutovalidateMode.disabled,
                      textInputAction: isSignup
                          ? TextInputAction.next
                          : TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validatePassword,
                      onChanged: (_) {
                        if (isSignup) {
                          setState(() {});
                        }
                      },
                      onFieldSubmitted: (_) {
                        if (!isSignup) {
                          _submit();
                        }
                      },
                    ),
                    if (!isSignup && _showForgotPassword) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isSubmitting
                              ? null
                              : _showForgotPasswordDialog,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    ],
                    if (isSignup) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('login_confirm_password_field'),
                        controller: _confirmPasswordController,
                        obscureText: true,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateConfirmPassword,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('login_submit_button'),
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(isSignup ? 'Create account' : 'Login'),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: loginWithGoogle,
                      icon: const Icon(Icons.g_mobiledata),
                      label: const Text('Login with Google'),
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

  Future<void> _showForgotPasswordDialog() async {
    final dialogFormKey = GlobalKey<FormState>();
    final emailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              final isValid = dialogFormKey.currentState?.validate() ?? false;
              if (!isValid || isSubmitting) {
                return;
              }

              setDialogState(() {
                isSubmitting = true;
              });

              final result = await AccountService.forgotPassword(
                emailController.text.trim(),
              );

              if (!dialogContext.mounted) {
                return;
              }

              Navigator.of(dialogContext).pop();

              if (!mounted) {
                return;
              }

              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(result.message)));
            }

            return AlertDialog(
              title: const Text('Reset your password'),
              content: Form(
                key: dialogFormKey,
                child: TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateEmail,
                  onFieldSubmitted: (_) => submit(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSubmitting ? null : submit,
                  child: isSubmitting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send reset link'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void loginWithGoogle() async {
    final result = await GoogleAuthService(GoogleService()).signInWithGoogle();
    if (!mounted) {
      return;
    }
    if (result == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Google Sign-In failed')));
      return;
    }
    await saveLoginInformation(result);
    if (!mounted) {
      return;
    }
    context.go(HomeScreen.routeName);
  }

  Future<void> saveLoginInformation(LoginInformation loginInformation) async {
    final prefs = await SharedPreferences.getInstance();
    await SessionStorage.write(
      accessToken: loginInformation.token,
      refreshToken: loginInformation.refreshToken,
    );
    await prefs.setString(
      SharedPreferencesKeys.accountEmail,
      loginInformation.email,
    );
    await prefs.setInt(
      SharedPreferencesKeys.accountId,
      loginInformation.accountId,
    );
    await prefs.setString(
      SharedPreferencesKeys.displayName,
      loginInformation.displayName,
    );
    await GraphQLConnection().initialize(loginInformation.token);
    await AccountService.registerCurrentDevice();
  }
}
