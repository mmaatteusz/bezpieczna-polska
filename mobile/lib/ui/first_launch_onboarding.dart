import 'package:flutter/material.dart';

import 'brand.dart';

class FirstLaunchPermissionOnboarding extends StatefulWidget {
  final Future<void> Function() onRequestLocation;
  final Future<void> Function() onRequestNotifications;
  final Future<void> Function() onComplete;
  final bool notificationsAvailable;

  const FirstLaunchPermissionOnboarding({
    super.key,
    required this.onRequestLocation,
    required this.onRequestNotifications,
    required this.onComplete,
    this.notificationsAvailable = true,
  });

  @override
  State<FirstLaunchPermissionOnboarding> createState() =>
      _FirstLaunchPermissionOnboardingState();
}

class _FirstLaunchPermissionOnboardingState
    extends State<FirstLaunchPermissionOnboarding> {
  final PageController _controller = PageController();
  int _step = 0;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _requestLocation() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.onRequestLocation();
    if (!mounted) return;
    await _controller.animateToPage(
      1,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    setState(() {
      _step = 1;
      _busy = false;
    });
  }

  Future<void> _requestNotifications() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.onRequestNotifications();
    if (!mounted) return;
    await widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Row(
                children: [
                  const BrandMark(size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bezpieczna Polska',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${_step + 1} z 2',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: List.generate(
                  2,
                  (index) => Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 4,
                      margin: EdgeInsets.only(right: index == 0 ? 6 : 0),
                      decoration: BoxDecoration(
                        color: index <= _step
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (value) {
                  if (mounted && _step != value) {
                    setState(() => _step = value);
                  }
                },
                children: [
                  _PermissionPage(
                    icon: Icons.location_on_rounded,
                    title: 'Lokalizacja dla Twojego bezpieczeństwa',
                    description:
                        'Potrzebujemy dostępu do lokalizacji, aby pokazywać ostrzeżenia i zagrożenia dla Twojej okolicy oraz najbliższe miejsca schronienia.',
                    privacy:
                        'Lokalizacja służy funkcjom aplikacji. Nie zapisujemy historii Twojego przemieszczania.',
                    buttonLabel: 'Zezwól na lokalizację',
                    buttonIcon: Icons.my_location_rounded,
                    busy: _busy && _step == 0,
                    onPressed: _requestLocation,
                  ),
                  _PermissionPage(
                    icon: Icons.notifications_active_rounded,
                    title: 'Nie przegap ważnego alertu',
                    description: widget.notificationsAvailable
                        ? 'Włącz powiadomienia, aby otrzymywać ważne ostrzeżenia także wtedy, gdy aplikacja nie jest otwarta.'
                        : 'Powiadomienia nie są dostępne w tym buildzie aplikacji. Możesz dokończyć konfigurację i wrócić do nich później.',
                    privacy: widget.notificationsAvailable
                        ? 'Rodzaje powiadomień możesz później zmienić w Ustawieniach.'
                        : 'Pozostałe funkcje aplikacji będą działać normalnie.',
                    buttonLabel: widget.notificationsAvailable
                        ? 'Włącz powiadomienia'
                        : 'Przejdź do aplikacji',
                    buttonIcon: widget.notificationsAvailable
                        ? Icons.notifications_rounded
                        : Icons.arrow_forward_rounded,
                    busy: _busy && _step == 1,
                    onPressed: _requestNotifications,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String privacy;
  final String buttonLabel;
  final IconData buttonIcon;
  final bool busy;
  final VoidCallback onPressed;

  const _PermissionPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.privacy,
    required this.buttonLabel,
    required this.buttonIcon,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
          child: IntrinsicHeight(
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 122,
                  height: 122,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 62,
                    color: theme.colorScheme.onPrimaryContainer,
                    semanticLabel: title,
                  ),
                ),
                const SizedBox(height: 34),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.12,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.privacy_tip_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        privacy,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onPressed,
                    icon: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Icon(buttonIcon),
                    label: Text(busy ? 'Chwileczkę…' : buttonLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
