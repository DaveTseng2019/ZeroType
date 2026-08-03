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

    await setRecording(false);
    await _buildMenu();
  }

  /// 錄音中換成橘底圖示 + tooltip，讓視窗縮在系統匣時也看得出正在錄。
  ///
  /// notes: 只動系統匣，工作列按鈕維持 exe 的 app_icon 不變 —— 試過用
  /// WM_SETICON 讓它跟著換，視窗圖示每次都設定成功（WM_GETICON 讀得到），
  /// 但 shell 不重畫按鈕。從外部行程做同一件事卻永遠有效，原因沒查出來。
  /// 真要做的話得改用 ITaskbarList3::SetOverlayIcon（右下角疊徽章）。
  Future<void> setRecording(bool recording) async {
    final name = recording ? 'tray_icon_recording' : 'tray_icon';
    // Windows 的系統匣只吃 .ico，PNG 會靜默失敗導致沒有圖示。
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/icons/$name.ico' : 'assets/icons/$name.png',
    );
    await trayManager.setToolTip(recording ? 'ZeroType — 錄音中' : 'ZeroType');
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
