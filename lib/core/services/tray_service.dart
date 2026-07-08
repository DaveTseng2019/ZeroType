import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

class TrayService with TrayListener {
  VoidCallback? _onShowWindow;
  VoidCallback? _onQuit;

  Future<void> initialize({
    required VoidCallback onShowWindow,
    required VoidCallback onQuit,
  }) async {
    _onShowWindow = onShowWindow;
    _onQuit = onQuit;

    trayManager.addListener(this);

    // Windows 的系統匣只吃 .ico，PNG 會靜默失敗導致沒有圖示。
    await trayManager.setIcon(
      Platform.isWindows
          ? 'assets/icons/tray_icon.ico'
          : 'assets/icons/tray_icon.png',
    );
    await trayManager.setToolTip('ZeroType');
    await _buildMenu();
  }

  Future<void> _buildMenu() async {
    final menu = Menu(
      items: [
        MenuItem(
          key: 'show',
          label: '顯示視窗',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'quit',
          label: '結束 ZeroType',
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() {
    _onShowWindow?.call();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _onShowWindow?.call();
      case 'quit':
        _onQuit?.call();
    }
  }

  void dispose() {
    trayManager.removeListener(this);
  }
}

typedef VoidCallback = void Function();
