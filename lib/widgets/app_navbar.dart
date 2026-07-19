import 'package:flutter/material.dart';

class AppNavbar extends StatefulWidget implements PreferredSizeWidget {
  const AppNavbar({
    super.key,
    required this.title,
    required this.subtitle,
    this.onRefresh,
    this.onLogout,
    this.showBackButton = true,
  });

  final String title; // BDT e-Prefeitura
  final String subtitle; // Hoje
  // Retorna Future<void> pra permitir mostrar spinner enquanto executa.
  // Se o caller passar uma VoidCallback (fire-and-forget), o wrapper abaixo
  // ainda funciona.
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLogout;
  final bool showBackButton;

  @override
  Size get preferredSize => const Size.fromHeight(112);

  @override
  State<AppNavbar> createState() => _AppNavbarState();
}

class _AppNavbarState extends State<AppNavbar> {
  bool _refreshing = false;

  Future<void> _handleRefresh() async {
    if (widget.onRefresh == null || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh!();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return AppBar(
      backgroundColor: const Color(0xFF0D47A1),
      elevation: 2,
      toolbarHeight: 112,
      centerTitle: true,
      automaticallyImplyLeading: false,

      leading: (widget.showBackButton && canPop)
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
            widget.title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),

      actions: [
        if (widget.onRefresh != null)
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _refreshing ? null : _handleRefresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.white),
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (v) {
            if (v == 'logout' && widget.onLogout != null) widget.onLogout!();
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
