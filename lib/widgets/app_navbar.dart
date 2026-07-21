import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/usuario_foto_service.dart';
import '../theme/app_theme.dart';

/// Barra superior do app.
///
/// Layout: logo circular da UERJ à esquerda, título + subtítulo à direita,
/// fundo com gradient azul institucional e sombra sutil. Actions ficam
/// na ordem: refresh (opcional) → menu (com "Sair" quando `onLogout != null`).
///
/// Mantém a compatibilidade da API antiga (`title`, `subtitle`, `onRefresh`,
/// `onLogout`, `showBackButton`) — só a apresentação mudou.
class AppNavbar extends StatefulWidget implements PreferredSizeWidget {
  const AppNavbar({
    super.key,
    required this.title,
    required this.subtitle,
    this.onRefresh,
    this.onLogout,
    this.showBackButton = true,
  });

  final String title;
  final String subtitle;

  /// Retorna Future<void> pra permitir mostrar spinner enquanto executa.
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLogout;
  final bool showBackButton;

  /// Altura visível (fora da status bar).
  static const double _toolbarHeight = 76;

  @override
  Size get preferredSize => const Size.fromHeight(_toolbarHeight);

  @override
  State<AppNavbar> createState() => _AppNavbarState();
}

class _AppNavbarState extends State<AppNavbar> {
  bool _refreshing = false;

  /// Nome do usuário logado, buscado uma vez no `initState` para exibir
  /// no header do menu `⋮`. Fica em cache no state (a sessão não muda
  /// enquanto a AppBar está montada).
  String _nomeLogado = '';

  /// MSEC.6 — arquivo local da foto do condutor. Null enquanto carrega,
  /// ou se o condutor não tem foto cadastrada. Se veio, os avatares
  /// mostram a foto real; senão, fallback pra `Icons.account_circle`.
  File? _fotoLocal;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _carregarNome();
    // ignore: discarded_futures
    _carregarFoto();
  }

  Future<void> _carregarNome() async {
    final nome = await AuthService.getNomeLogado();
    if (!mounted || nome.isEmpty) return;
    setState(() => _nomeLogado = nome);
  }

  Future<void> _carregarFoto() async {
    // Se o cache está vazio, `obterCached` agora espera o refetch em
    // foreground (fix do bug: antes voltava null imediato e a foto
    // só aparecia no próximo abrir da tela).
    final f = await UsuarioFotoService.obterCached();
    if (!mounted) return;
    if (f != null) {
      debugPrint('AppNavbar: foto carregada (${f.path})');
      setState(() => _fotoLocal = f);
    } else {
      // null = condutor não tem foto cadastrada OU download falhou —
      // fallback pro ícone genérico já está renderizado.
      debugPrint('AppNavbar: sem foto no cache (fallback ícone)');
    }
  }

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
    final showBack = widget.showBackButton && canPop;

    return AppBar(
      // Cor real fica no flexibleSpace (para permitir gradient + sombra).
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: AppNavbar._toolbarHeight,
      automaticallyImplyLeading: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),

      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primary,          // 0xFF0D47A1
              Color(0xFF002171),         // azul UERJ mais profundo
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),

      leading: showBack
          ? IconButton(
              tooltip: 'Voltar',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,

      titleSpacing: showBack ? 4 : 12,

      title: Row(
        children: [
          _LogoBrasao(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                if (widget.subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
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
                : const Icon(Icons.refresh),
          ),
        if (widget.onLogout != null) _buildUserMenu(),
        const SizedBox(width: 8),
      ],
    );
  }

  /// Menu do usuário logado. Substitui o `⋮` clássico por um avatar
  /// — na primeira versão eram as iniciais do nome, mas isso gerava
  /// combinações constrangedoras ("CU" para Cláudio Ulisses, "PP",
  /// "VD", etc.). A foto real do condutor será implementada na
  /// MSEC.6 (endpoint autenticado + cache local com TTL). Até lá,
  /// mostramos um ícone `account_circle` genérico e neutro.
  ///
  /// Ao tocar: card do usuário no topo (avatar + label + nome
  /// completo), divisor, e "Sair" em vermelho como única ação.
  Widget _buildUserMenu() {
    return PopupMenuButton<String>(
      tooltip: _nomeLogado.isEmpty
          ? 'Menu do usuário'
          : 'Logado como $_nomeLogado',
      offset: const Offset(0, 56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) {
        if (v == 'logout') widget.onLogout!();
      },
      itemBuilder: (context) => [
        // Cabeçalho do menu — card do usuário. `enabled: false` deixa
        // ele não-clicável (não é ação), e o layout com avatar + label
        // "Condutor logado" + nome torna óbvio o que representa.
        if (_nomeLogado.isNotEmpty)
          PopupMenuItem(
            enabled: false,
            height: 68,
            child: Row(
              children: [
                // MSEC.6 — foto real se tem, senão fallback ícone.
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.primary,
                  backgroundImage: _fotoLocal != null
                      ? FileImage(_fotoLocal!)
                      : null,
                  child: _fotoLocal == null
                      ? const Icon(
                          Icons.account_circle,
                          color: Colors.white,
                          size: 28,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Condutor logado',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.black54,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _nomeLogado,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_nomeLogado.isNotEmpty) const PopupMenuDivider(height: 6),

        // "Sair" com cor de ação destrutiva — ícone e texto em vermelho
        // (AppTheme.danger). Antes o ícone padrão ficava quase invisível
        // sobre o fundo claro do menu.
        const PopupMenuItem(
          value: 'logout',
          height: 44,
          child: Row(
            children: [
              Icon(Icons.logout, size: 20, color: AppTheme.danger),
              SizedBox(width: 12),
              Text(
                'Sair',
                style: TextStyle(
                  color: AppTheme.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
      // Trigger do menu — foto real se cached, senão ícone genérico
      // account_circle (MSEC.6). Border branca destaca sobre o
      // gradient azul da AppBar.
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70, width: 1.5),
        ),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: Colors.white,
          backgroundImage:
              _fotoLocal != null ? FileImage(_fotoLocal!) : null,
          child: _fotoLocal == null
              ? const Icon(
                  Icons.account_circle,
                  color: AppTheme.primary,
                  size: 26,
                )
              : null,
        ),
      ),
    );
  }
}

/// Logo institucional da UERJ dentro de uma "capsule" circular branca.
/// A capsule é necessária porque o brasão em si tem tocha laranja e
/// contorno azul — no fundo azul da AppBar ele "some". A borda branca
/// destaca e mantém a identidade visual limpa em qualquer tema.
class _LogoBrasao extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/logomarca-uerj.png',
        fit: BoxFit.contain,
      ),
    );
  }
}
