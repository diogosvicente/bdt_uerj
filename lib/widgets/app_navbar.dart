import 'package:flutter/material.dart';

class AppNavbar extends StatelessWidget implements PreferredSizeWidget {
  const AppNavbar({
    super.key,
    required this.title,
    required this.subtitle,
    this.onRefresh,
    this.onLogout,
    this.showBackButton = true,
  });

  final String title;      // BDT e-Prefeitura
  final String subtitle;   // Hoje
  final VoidCallback? onRefresh;
  final VoidCallback? onLogout;
  final bool showBackButton;

  @override
  Size get preferredSize => const Size.fromHeight(112);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return AppBar(
      backgroundColor: const Color(0xFF0D47A1),
      elevation: 2,
      toolbarHeight: 112,
      centerTitle: true,
      automaticallyImplyLeading: false,

      leading: (showBackButton && canPop)
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,

      title: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 🔹 LOGO (linha 1)
          Image.asset(
            'assets/images/LOGO_PREFEITURA.png',
            height: 36,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 6),

          // 🔹 TEXTO (linha 2)
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          /*Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),*/
        ],
      ),

      actions: [
        if (onRefresh != null)
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: onRefresh,
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (v) {
            if (v == 'logout' && onLogout != null) onLogout!();
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'logout',
              child: Text('Sair'),
            ),
          ],
        ),
      ],
    );
  }
}
