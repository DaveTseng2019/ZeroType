import 'package:flutter/material.dart';

/// 清單列尾端的圓框動作按鈕（歷史記錄、常用詞彙共用）
class ActionIcon extends StatelessWidget {
  const ActionIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Theme.of(context).colorScheme.onSurface.withOpacity(0.55);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        // 每顆都套同一個圓框。實心與線條圖示在同一個 size 下看起來就是不一樣大，
        // 外框把佔位畫出來，眼睛才對得齊。框一律用品牌橘 —— 框是共通的容器，
        // 多種顏色的框反而又變成不一致；圖示本身仍各自保留顏色語意。
        child: Container(
          padding: const EdgeInsets.all(8),
          // 原本緊貼，加了框會黏成一條，補一點間距
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
            ),
          ),
          child: Icon(icon, size: 24, color: iconColor),
        ),
      ),
    );
  }
}
