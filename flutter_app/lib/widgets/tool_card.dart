import 'package:flutter/material.dart';
import '../config/theme.dart';

/// Tool card yang aman untuk layar Android kecil, rotasi, dan grid sempit.
class ToolCard extends StatefulWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const ToolCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final shortestSide = mediaQuery.size.shortestSide;
    final isCompact = shortestSide < 380;

    final borderRadius = BorderRadius.circular(isCompact ? 14 : 18);
    final isInteractive = _isHovered || _isPressed;
    final cardColor = isInteractive ? AppTheme.cardHover : AppTheme.cardDark;
    final borderColor =
        isInteractive ? widget.color.withOpacity(0.45) : AppTheme.dividerColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Semantics(
        button: true,
        label: widget.title,
        hint: widget.description,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: widget.onTap,
            onHighlightChanged: (value) {
              if (_isPressed != value) {
                setState(() => _isPressed = value);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: borderRadius,
                border: Border.all(
                  color: borderColor,
                  width: 1.2,
                ),
                boxShadow: isInteractive
                    ? [
                        BoxShadow(
                          color: widget.color.withOpacity(0.12),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : const [],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxH = constraints.maxHeight;
                  final maxW = constraints.maxWidth;
                  final hasBoundedH = constraints.hasBoundedHeight;

                  // Adaptive padding based on available height and width
                  final vPadding = hasBoundedH
                      ? (maxH < 90 ? 8.0 : (maxH < 120 ? 10.0 : (maxH < 150 ? 12.0 : 16.0)))
                      : 14.0;
                  final hPadding = maxW < 120 ? 8.0 : (maxW < 160 ? 12.0 : 16.0);

                  // Adaptive icon box size
                  final iconBoxSize = hasBoundedH
                      ? (maxH < 85 ? 26.0 : (maxH < 110 ? 32.0 : (maxH < 140 ? 38.0 : 44.0)))
                      : 42.0;
                  final iconSize = iconBoxSize * 0.52;

                  // Adaptive spacing
                  final spacing = hasBoundedH
                      ? (maxH < 95 ? 4.0 : (maxH < 130 ? 6.0 : 10.0))
                      : 8.0;

                  // Adaptive font size
                  final titleFontSize = hasBoundedH
                      ? (maxH < 90 ? 11.5 : (maxH < 120 ? 13.0 : 14.5))
                      : 14.5;
                  final descFontSize = (titleFontSize - 2.0).clamp(10.0, 12.0);

                  // Calculate space left for description
                  final titleLineHeight = titleFontSize * 1.25;
                  final usedHeight = (vPadding * 2) + iconBoxSize + spacing + titleLineHeight;
                  final remainingHeight = hasBoundedH ? (maxH - usedHeight) : 100.0;

                  // Only show description if there is at least ~18px remaining space
                  final canShowDesc = remainingHeight >= 18.0 && maxW >= 100;
                  final descMaxLines = remainingHeight >= 40.0 ? 2 : 1;

                  // Check if card is extremely wide and short -> render as horizontal Row
                  final isWideFlat = maxW >= 190 && hasBoundedH && maxH < 100;

                  Widget content;
                  if (isWideFlat) {
                    content = Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: iconBoxSize,
                          height: iconBoxSize,
                          decoration: BoxDecoration(
                            color: widget.color.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.color,
                            size: iconSize,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              if (canShowDesc) ...[
                                const SizedBox(height: 2),
                                Text(
                                  widget.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: descFontSize,
                                    height: 1.2,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  } else {
                    content = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: iconBoxSize,
                          height: iconBoxSize,
                          decoration: BoxDecoration(
                            color: widget.color.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(
                              iconBoxSize < 30 ? 6 : (iconBoxSize < 36 ? 8 : 10),
                            ),
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.color,
                            size: iconSize,
                          ),
                        ),
                        SizedBox(height: spacing),
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (canShowDesc) ...[
                          const SizedBox(height: 3),
                          Flexible(
                            fit: FlexFit.loose,
                            child: Text(
                              widget.description,
                              maxLines: descMaxLines,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: descFontSize,
                                height: 1.25,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  }

                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: hPadding,
                      vertical: vPadding,
                    ),
                    child: ClipRect(
                      child: content,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
