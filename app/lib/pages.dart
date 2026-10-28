import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'api.dart';

// ============ 主题（跟随系统亮暗） ============
ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2BBBAD),
    brightness: b,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF0F1720) : const Color(0xFFF6F8FA),
    useMaterial3: true,
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: dark ? const Color(0xFF111A24) : const Color(0xFFEDF1F4),
      indicatorColor: scheme.primary.withValues(alpha: .18),
      selectedIconTheme: IconThemeData(color: scheme.primary),
      selectedLabelTextStyle: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
      unselectedIconTheme: const IconThemeData(color: Color(0xFF8FA3B5)),
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF141E28) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: dark ? const Color(0xFF223141) : const Color(0xFFE2E8EE)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1A2733) : const Color(0xFFEDF1F4),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

// ============ 主界面：侧边栏 ============
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _loggedIn = false;
  Map<String, dynamic> _me = {};
  final List<_NavItem> _pages = [
    _NavItem(Icons.send_rounded, '发送', const SendPage()),
    _NavItem(Icons.download_rounded, '接收', const ReceivePage()),
    _NavItem(Icons.history_rounded, '历史', const HistoryPage()),
    _NavItem(Icons.settings_rounded, '设置', const SettingsPage()),
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await Api.status();
    final m = await Api.me();
    if (mounted) {
      setState(() {
        _loggedIn = (s['logged_in'] == true) || (m['logged_in'] == true);
        _me = (m['user'] as Map?)?.cast<String, dynamic>() ?? {};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Row(
        children: [
          // 侧边栏
          Container(
            width: 190,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF111A24) : const Color(0xFFEDF1F4),
              border: Border(right: BorderSide(color: dark ? const Color(0xFF223141) : const Color(0xFFE2E8EE))),
            ),
            child: Column(
              children: [
                const SizedBox(height: 24),
                // Logo
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF2BBBAD), Color(0xFF0F766E)]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Darling File', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      Text('闪传', style: TextStyle(fontSize: 11, color: Color(0xFF8FA3B5))),
                    ]),
                  ],
                ),
                const SizedBox(height: 28),
                // 导航
                for (var i = 0; i < _pages.length; i++)
                  _SideItem(
                    icon: _pages[i].icon,
                    label: _pages[i].title,
                    selected: _index == i,
                    onTap: () => setState(() => _index = i),
                  ),
                const Spacer(),
                // 登录状态
                if (_loggedIn)
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: const Color(0xFF2BBBAD).withValues(alpha: .2),
                          child: const Icon(Icons.person, size: 16, color: Color(0xFF2BBBAD)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_me['email'] ?? '已登录',
                              style: const TextStyle(fontSize: 11.5),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: FilledButton.icon(
                      onPressed: () => _openLogin(),
                      icon: const Icon(Icons.login, size: 16),
                      label: const Text('登录'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                    ),
                  ),
              ],
            ),
          ),
          // 内容区
          Expanded(child: _pages[_index].page),
        ],
      ),
    );
  }

  Future<void> _openLogin() async {
    await showDialog(context: context, builder: (_) => const LoginDialog());
    _refresh();
  }
}

class _NavItem {
  final IconData icon;
  final String title;
  final Widget page;
  _NavItem(this.icon, this.title, this.page);
}

class _SideItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SideItem({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: .16) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: selected ? scheme.primary : const Color(0xFF8FA3B5)),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? scheme.primary : null)),
            ],
          ),
        ),
      ),
    );
  }
}

// ============ 登录对话框 ============
class LoginDialog extends StatefulWidget {
  const LoginDialog({super.key});
  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('登录'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('使用 Darling AI 账号直接登录，无需注册', style: TextStyle(fontSize: 12.5, color: Color(0xFF8FA3B5))),
            const SizedBox(height: 16),
            TextField(controller: _email, decoration: const InputDecoration(labelText: '邮箱', prefixIcon: Icon(Icons.mail_outline, size: 18))),
            const SizedBox(height: 10),
            TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: '密码', prefixIcon: Icon(Icons.lock_outline, size: 18))),
            if (_err != null) ...[
              const SizedBox(height: 10),
              Text(_err!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12.5)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: _busy ? null : () async {
            setState(() { _busy = true; _err = null; });
            final r = await Api.login(_email.text.trim(), _pass.text);
            setState(() => _busy = false);
            if (r['ok'] == true) {
              if (mounted) Navigator.pop(context);
            } else {
              setState(() => _err = r['error']?.toString() ?? '登录失败');
            }
          },
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('登录'),
        ),
      ],
    );
  }
}

// ============ 发送页 ============
class SendPage extends StatefulWidget {
  const SendPage({super.key});
  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> _peers = [];
  String? _peerIp;
  final _ipCtrl = TextEditingController();
  String? _msg;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _poll();
    Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  Future<void> _poll() async {
    final r = await Api.peers();
    if (mounted && r['ok'] == true) {
      setState(() => _peers = (r['peers'] as List? ?? []).cast<Map<String, dynamic>>());
    }
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (res == null) return;
    setState(() {
      for (final f in res.files) {
        if (f.path != null) _files.add({'path': f.path!, 'name': f.name, 'size': File(f.path!).lengthSync()});
      }
    });
  }

  Future<void> _send({String method = 'auto'}) async {
    if (_files.isEmpty) return;
    setState(() { _busy = true; _msg = null; });
    try {
      Map<String, dynamic> r;
      if (method == 'relay') {
        r = await Api.sendMulti(_files.map((f) => f['path'] as String).toList());
        if (r['ok'] == true) {
          final url = r['url'];
          setState(() => _msg = '中转会话已建立，口令: ${r['code']}\n$url\n把链接发给对方，对方输入口令接收');
          if (mounted) _showCodeDialog(r['code'] as String, url as String);
        } else {
          setState(() => _msg = '中转失败: ${r['error']}');
        }
        return;
      }
      for (final f in _files) {
        r = await Api.send(f['path'] as String, method: method, ip: _peerIp);
        if (r['ok'] != true) {
          setState(() => _msg = '${f['name']} 发送失败: ${r['error']}');
          return;
        }
      }
      setState(() => _msg = '发送完成');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _showCodeDialog(String code, String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('中转口令已生成'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('把下面链接发给对方（接收方无需登录）：', style: TextStyle(fontSize: 12.5, color: Color(0xFF8FA3B5))),
              const SizedBox(height: 12),
              SelectableText(url, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF2BBBAD).withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  Text(code, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 8, color: Theme.of(ctx).colorScheme.primary)),
                  const SizedBox(height: 4),
                  const Text('口令（6位大写字母+数字）', style: TextStyle(fontSize: 11, color: Color(0xFF8FA3B5))),
                ]),
              ),
              const SizedBox(height: 12),
              const Text('对方在「接收」页输入口令即可接收 · 发送完成或关闭应用后口令自动释放', style: TextStyle(fontSize: 11.5, color: Color(0xFF8FA3B5))),
            ],
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('好的')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('发送文件', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 6),
          const Text('小文件自动走 UDP 极速快传，大文件走 TCP 直连，异地可走官方中转', style: TextStyle(fontSize: 12.5, color: Color(0xFF8FA3B5))),
          const SizedBox(height: 20),
          // 文件选择区
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF141E28) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF223141) : const Color(0xFFE2E8EE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('已选文件', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('${_files.length} 个', style: const TextStyle(color: Color(0xFF8FA3B5), fontSize: 12)),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('选择文件'),
                  ),
                ]),
                if (_files.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 26),
                    child: Center(child: Text('尚未选择文件，点击右上角「选择文件」', style: TextStyle(color: Color(0xFF8FA3B5), fontSize: 13))),
                  )
                else
                  ..._files.map((f) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.insert_drive_file_outlined, color: Color(0xFF2BBBAD)),
                        title: Text(f['name'] as String, style: const TextStyle(fontSize: 13.5), overflow: TextOverflow.ellipsis),
                        subtitle: Text(_fmtSize(f['size'] as int), style: const TextStyle(fontSize: 11.5, color: Color(0xFF8FA3B5))),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 17),
                          onPressed: () => setState(() => _files.remove(f)),
                        ),
                      )),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // 目标选择
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF141E28) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF223141) : const Color(0xFFE2E8EE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('发送到', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (_peers.isEmpty)
                  const Text('未发现局域网设备（两台设备连同一网络会自动出现）', style: TextStyle(fontSize: 12.5, color: Color(0xFF8FA3B5)))
                else
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final p in _peers)
                      ChoiceChip(
                        label: Text('${p['name']} (${p['ip']})', style: const TextStyle(fontSize: 12)),
                        selected: _peerIp == p['ip'],
                        onSelected: (_) => setState(() => _peerIp = p['ip'] as String),
                      ),
                  ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _ipCtrl,
                      decoration: const InputDecoration(
                        labelText: '对方 IP 地址（局域网 / 公网 / 内网穿透）',
                        prefixIcon: Icon(Icons.dns_outlined, size: 18),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _peerIp = v.trim().isEmpty ? _peerIp : v.trim()),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          const Spacer(),
          if (_msg != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2BBBAD).withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_msg!, style: const TextStyle(fontSize: 13)),
            ),
          Row(children: [
            FilledButton.icon(
              onPressed: _busy ? null : () => _send(method: 'auto'),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(_busy ? '发送中…' : '发送'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _send(method: 'relay'),
              icon: const Icon(Icons.cloud_outlined, size: 18),
              label: const Text('官方中转'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _send(method: 'udp'),
              icon: const Icon(Icons.bolt_outlined, size: 18),
              label: const Text('UDP 快传'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _send(method: 'tcp'),
              icon: const Icon(Icons.swap_vert_rounded, size: 18),
              label: const Text('TCP 直连'),
            ),
          ]),
        ],
      ),
    );
  }
}

// ============ 接收页 ============
class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key});
  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  final _codeCtrl = TextEditingController();
  String? _msg;
  bool _busy = false;
  List<Map<String, dynamic>> _incoming = [];

  @override
  void initState() {
    super.initState();
    Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  Future<void> _poll() async {
    final r = await Api.incoming();
    if (mounted && r['ok'] == true) {
      setState(() => _incoming = (r['incoming'] as List? ?? []).cast<Map<String, dynamic>>());
    }
  }

  Future<void> _recv() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() { _busy = true; _msg = null; });
    final r = await Api.relayRecv(code);
    setState(() => _busy = false);
    if (r['ok'] == true) {
      setState(() => _msg = '已连接中转，正在接收文件…');
      _codeCtrl.clear();
    } else {
      setState(() => _msg = r['error']?.toString() ?? '接收失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('接收文件', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 6),
          const Text('输入对方的中转口令接收（无需登录），或等待局域网设备直连', style: TextStyle(fontSize: 12.5, color: Color(0xFF8FA3B5))),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF141E28) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF223141) : const Color(0xFFE2E8EE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('官方中转接收', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: '输入 6 位口令（如 AB3XY9）',
                        prefixIcon: Icon(Icons.vpn_key_outlined, size: 18),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _recv,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(_busy ? '连接中…' : '接收'),
                  ),
                ]),
                if (_msg != null) ...[
                  const SizedBox(height: 10),
                  Text(_msg!, style: const TextStyle(fontSize: 13, color: Color(0xFF2BBBAD))),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('正在接收', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Expanded(
            child: _incoming.isEmpty
                ? const Center(child: Text('暂无接收任务', style: TextStyle(color: Color(0xFF8FA3B5))))
                : ListView.builder(
                    itemCount: _incoming.length,
                    itemBuilder: (c, i) {
                      final it = _incoming[i];
                      final done = it['status'] == 'done';
                      final total = (it['size'] as num?)?.toDouble() ?? 0;
                      final prog = (it['progress'] as num?)?.toDouble() ?? 0;
                      return Card(
                        child: ListTile(
                          leading: Icon(done ? Icons.check_circle : Icons.downloading, color: done ? const Color(0xFF34D399) : const Color(0xFF2BBBAD)),
                          title: Text(it['name'] ?? '', style: const TextStyle(fontSize: 13.5), overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${it['method']} · ${_fmtSize(prog.toInt())}/${_fmtSize(total.toInt())} · ${done ? "完成" : it['status']}',
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF8FA3B5))),
                              if (!done && total > 0)
                                LinearProgressIndicator(value: total > 0 ? prog / total : 0, minHeight: 3, borderRadius: BorderRadius.circular(3)),
                            ],
                          ),
                          trailing: done ? IconButton(
                            icon: const Icon(Icons.folder_open, size: 18),
                            tooltip: '打开接收目录',
                            onPressed: () => Process.start('xdg-open', [it['path'] ?? '']),
                          ) : null,
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

// ============ 历史页 ============
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _poll();
    Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  Future<void> _poll() async {
    final r = await Api.history();
    if (mounted && r['ok'] == true) {
      setState(() => _history = (r['history'] as List? ?? []).cast<Map<String, dynamic>>());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('传输历史', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 16),
          Expanded(
            child: _history.isEmpty
                ? const Center(child: Text('暂无传输记录', style: TextStyle(color: Color(0xFF8FA3B5))))
                : ListView.separated(
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (c, i) {
                      final h = _history[i];
                      final send = h['direction'] == '发';
                      final done = h['status'] == 'done';
                      return Card(
                        child: ListTile(
                          leading: Icon(send ? Icons.upload_rounded : Icons.download_rounded,
                              color: send ? const Color(0xFF2BBBAD) : const Color(0xFF8B5CF6)),
                          title: Text(h['name'] ?? '', style: const TextStyle(fontSize: 13.5), overflow: TextOverflow.ellipsis),
                          subtitle: Text('${send ? "发出" : "接收"} · ${h['method']} · ${_fmtSize((h['size'] as num?)?.toInt() ?? 0)} · ${done ? "成功" : h['status']}',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF8FA3B5))),
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

// ============ 设置页 ============
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic> _me = {};
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Api.me();
    if (mounted) {
      setState(() {
        _loggedIn = r['logged_in'] == true;
        _me = (r['user'] as Map?)?.cast<String, dynamic>() ?? {};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设置', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline, color: Color(0xFF2BBBAD)),
              title: Text(_loggedIn ? (_me['email'] ?? '已登录') : '未登录', style: const TextStyle(fontSize: 14)),
              subtitle: Text(_loggedIn ? 'Darling AI 账号互通' : '登录后可使用官方中转（发送方需登录）', style: const TextStyle(fontSize: 12, color: Color(0xFF8FA3B5))),
              trailing: _loggedIn
                  ? TextButton(onPressed: () async { await Api.logout(); _load(); }, child: const Text('退出登录'))
                  : FilledButton(onPressed: () async { await showDialog(context: context, builder: (_) => const LoginDialog()); _load(); }, child: const Text('登录')),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_outlined, color: Color(0xFF2BBBAD)),
              title: const Text('官方中转', style: TextStyle(fontSize: 14)),
              subtitle: const Text('relay.darling02.de5.net · 数据流过即走，不占用存储空间', style: TextStyle(fontSize: 12, color: Color(0xFF8FA3B5))),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_outlined, color: Color(0xFF2BBBAD)),
              title: const Text('接收目录', style: TextStyle(fontSize: 14)),
              subtitle: const Text('~/DarlingFile/Received', style: TextStyle(fontSize: 12, color: Color(0xFF8FA3B5))),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline, color: Color(0xFF2BBBAD)),
              title: const Text('Darling File', style: TextStyle(fontSize: 14)),
              subtitle: Text('v$kVersion · 跨设备闪传 · GitHub: DarlingZeroTwo-Cloud/Darling-File', style: const TextStyle(fontSize: 12, color: Color(0xFF8FA3B5))),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtSize(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  if (bytes >= 1024 * 1024) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}
