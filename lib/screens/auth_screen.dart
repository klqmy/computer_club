import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/record.dart';
import '../state/auth_state.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  bool register = false, busy = false, obscure = true;
  String? error, notice;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final auth = context.read<AuthState>();
      if (register) {
        final signed = await auth.register(
          name.text,
          email.text,
          password.text,
        );
        if (!signed && mounted) {
          setState(
            () => notice =
                'Письмо подтверждения отправлено. Подтвердите email, затем войдите.',
          );
        }
      } else {
        await auth.login(email.text, password.text);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        return Row(
          children: [
            if (wide)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(64),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xff193029), Color(0xff10202f)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.bolt,
                        size: 80,
                        color: Color(0xffc5f36b),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Твой следующий\nуровень.',
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Выбери компьютер, забронируй время\nи приходи играть в ПУЛЬС.',
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.6,
                          color: Color(0xffa8b7b8),
                        ),
                      ),
                      const SizedBox(height: 48),
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          for (final t in [
                            'МОЩНЫЕ ПК',
                            'VIP-ЗОНА',
                            'КЛУБНЫЕ СКИДКИ',
                          ])
                            Chip(label: Text(t)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(wide ? 48 : 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'ПУЛЬС',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              color: Color(0xffc5f36b),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            register ? 'Новый игрок' : 'Добро пожаловать',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            register
                                ? 'Создайте личный кабинет клиента'
                                : 'Войдите, чтобы продолжить',
                            style: const TextStyle(color: Color(0xff99a3b3)),
                          ),
                          const SizedBox(height: 32),
                          if (register) ...[
                            TextFormField(
                              controller: name,
                              decoration: const InputDecoration(
                                labelText: 'ФИО',
                              ),
                              validator: (v) => const FieldSpec(
                                'name',
                                'ФИО',
                                maxLength: 100,
                              ).validate(v),
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.alternate_email),
                            ),
                            validator: (v) => const FieldSpec(
                              'email',
                              'Email',
                              kind: FieldKind.email,
                              maxLength: 120,
                            ).validate(v),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: password,
                            obscureText: obscure,
                            decoration: InputDecoration(
                              labelText: 'Пароль',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: obscure
                                    ? 'Показать пароль'
                                    : 'Скрыть пароль',
                                onPressed: () =>
                                    setState(() => obscure = !obscure),
                                icon: Icon(
                                  obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (v) {
                              if ((v ?? '').isEmpty) return 'Введите пароль';
                              if (register &&
                                  (v!.length < 8 || v.length > 72)) {
                                return 'От 8 до 72 символов';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => busy ? null : submit(),
                          ),
                          if (error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          if (context.watch<AuthState>().error != null) ...[
                            const SizedBox(height: 16),
                            Text(context.read<AuthState>().error!),
                          ],
                          if (notice != null) ...[
                            const SizedBox(height: 16),
                            Text(notice!),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: busy ? null : submit,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      register ? 'Создать аккаунт' : 'Войти',
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    register = !register;
                                    error = null;
                                    notice = null;
                                    form.currentState?.reset();
                                  }),
                            child: Text(
                              register
                                  ? 'Уже есть аккаунт? Войти'
                                  : 'Нет аккаунта? Зарегистрироваться',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
