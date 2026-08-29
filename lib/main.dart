import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/settings.dart';
import 'services/storage.dart';
import 'state/app_state.dart';
import 'ui/pages/devices_page.dart';
import 'ui/pages/history_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/receive_gate.dart';
import 'ui/solar_icons.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先出画面再初始化:任何初始化异常都渲染成可见的错误页,
  // 而不是卡在首帧之前白屏
  runApp(const BootstrapApp());
}

/// 启动引导:加载中 → 主界面 / 启动失败详情
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  AppState? _app;
  Object? _error;
  StackTrace? _stack;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final storage = await Storage.init();
      final app = AppState(storage);
      await app.init();
      if (mounted) setState(() => _app = app);
    } catch (e, st) {
      if (mounted) {
        setState(() {
          _error = e;
          _stack = st;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    if (app != null) return LanDropApp(app: app);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: SafeArea(
          child: _error == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('启动失败',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      SelectableText('$_error',
                          style: const TextStyle(fontSize: 14, height: 1.5)),
                      const SizedBox(height: 12),
                      SelectableText('$_stack',
                          style: const TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: AppColors.subtextLight)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class LanDropApp extends StatelessWidget {
  const LanDropApp({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: app,
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final themeMode = switch (state.settings.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          };
          return MaterialApp(
            title: '知行快传',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: themeMode,
            home: const ReceiveGate(child: MainShell()),
          );
        },
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _pages = [
    DevicesPage(),
    HistoryPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final busy = app.active.length;
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(SolarIcons.devicesOutline),
            selectedIcon: Icon(SolarIcons.devices),
            label: '设备',
          ),
          NavigationDestination(
            // 传输中时给「记录」加个角标,不用切页也知道有任务在跑
            icon: Badge(
              isLabelVisible: busy > 0,
              label: Text('$busy'),
              child: const Icon(SolarIcons.historyOutline),
            ),
            selectedIcon: Badge(
              isLabelVisible: busy > 0,
              label: Text('$busy'),
              child: const Icon(SolarIcons.history),
            ),
            label: '记录',
          ),
          const NavigationDestination(
            icon: Icon(SolarIcons.settingsOutline),
            selectedIcon: Icon(SolarIcons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
