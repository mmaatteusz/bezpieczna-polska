import 'package:flutter/material.dart';

class SafetyAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int page;
  final VoidCallback onSettings;

  const SafetyAppBar({super.key, required this.page, required this.onSettings});

  static const _toolbarHeight = 60.0;

  @override
  Size get preferredSize => const Size.fromHeight(_toolbarHeight + 1);

  @override
  Widget build(BuildContext context) => AppBar(
    toolbarHeight: _toolbarHeight,
    title: page == 0
        ? const Row(
            children: [
              _Shield(),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Bezpieczna Polska',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          )
        : Text(const ['Bezpieczna Polska', 'Mapa', 'Alerty', 'Więcej'][page]),
    actions: [
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: IconButton(
          tooltip: 'Ustawienia',
          onPressed: onSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
      ),
    ],
    bottom: const PreferredSize(
      preferredSize: Size.fromHeight(1),
      child: Divider(),
    ),
  );
}

class SafetyTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const SafetyTabBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Start',
        ),
        NavigationDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map_rounded),
          label: 'Mapa',
        ),
        NavigationDestination(
          icon: Icon(Icons.notifications_none_rounded),
          selectedIcon: Icon(Icons.notifications_rounded),
          label: 'Alerty',
        ),
        NavigationDestination(
          icon: Icon(Icons.more_horiz_rounded),
          label: 'Więcej',
        ),
      ],
    ),
  );
}

class _Shield extends StatelessWidget {
  const _Shield();

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(29),
    painter: _ShieldPainter(Theme.of(context).colorScheme.outline),
  );
}

class _ShieldPainter extends CustomPainter {
  final Color outline;

  const _ShieldPainter(this.outline);

  @override
  void paint(Canvas canvas, Size size) {
    final shield = Path()
      ..moveTo(14.5, 2)
      ..lineTo(25.5, 6.5)
      ..lineTo(25.5, 14)
      ..quadraticBezierTo(25.5, 22.5, 14.5, 27)
      ..quadraticBezierTo(3.5, 22.5, 3.5, 14)
      ..lineTo(3.5, 6.5)
      ..close();
    canvas.save();
    canvas.clipPath(shield);
    canvas.drawColor(const Color(0xFFFFFDF9), BlendMode.srcOver);
    canvas.drawRect(
      Rect.fromLTRB(0, 13.5, size.width, size.height),
      Paint()..color = const Color(0xFFC62642),
    );
    canvas.restore();
    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 1.25
        ..color = outline,
    );
  }

  @override
  bool shouldRepaint(_ShieldPainter oldDelegate) =>
      outline != oldDelegate.outline;
}
