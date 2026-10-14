import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

class SegmentedSwitchItem<T> {
  final T value;
  final String label;

  const SegmentedSwitchItem({
    required this.value,
    required this.label,
  });
}

class AppSegmentedSwitch<T> extends StatelessWidget {
  final T selectedValue;
  final List<SegmentedSwitchItem<T>> items;
  final ValueChanged<T> onChanged;
  final bool isExpanded;

  const AppSegmentedSwitch({
    super.key,
    required this.selectedValue,
    required this.items,
    required this.onChanged,
    this.isExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final containerColor = colors.subtleBackground;
    final borderColor = colors.cardBorder;
    final unselectedTextColor = colors.textSecondary;

    final children = items.map((item) {
      final isSelected = item.value == selectedValue;
      Widget content = GestureDetector(
        onTap: () => onChanged(item.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1565C0) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            item.label,
            style: GoogleFonts.roboto(
              color: isSelected ? Colors.white : unselectedTextColor,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              letterSpacing: 0.8,
            ),
          ),
        ),
      );

      if (isExpanded) {
        return Expanded(child: content);
      }
      return content;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
        children: children,
      ),
    );
  }
}
