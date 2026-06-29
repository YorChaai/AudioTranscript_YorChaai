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
    final isVeryCompact = shortestSide < 340;

    final borderRadius = BorderRadius.circular(isCompact ? 16 : 20);
    final iconBoxSize = isVeryCompact ? 38.0 : (isCompact ? 42.0 : 46.0);
    final iconSize = isVeryCompact ? 18.0 : 22.0;
    final horizontalPadding = isVeryCompact ? 12.0 : 16.0;
    final verticalPadding = isVeryCompact ? 12.0 : 16.0;
    final titleFontSize = isVeryCompact ? 13.0 : 15.0;
    final descFontSize = isVeryCompact ? 11.0 : 12.0;
    final spacingSmall = isVeryCompact ? 8.0 : 12.0;
    final titleLines = isVeryCompact ? 1 : 2;
    final descLines = isVeryCompact ? 2 : 3;

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
              constraints: const BoxConstraints(
                minHeight: 132,
              ),
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
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrowCard = constraints.maxWidth < 170;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Container(
                          width: iconBoxSize,
                          height: iconBoxSize,
                          decoration: BoxDecoration(
                            color: widget.color.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(
                              isVeryCompact ? 10 : 12,
                            ),
                          ),
                          child: Icon(
                            widget.icon,
                            color: widget.color,
                            size: iconSize,
                          ),
                        ),
                        SizedBox(height: spacingSmall),
                        Text(
                          widget.title,
                          maxLines: titleLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Flexible(
                          child: Text(
                            widget.description,
                            maxLines: narrowCard ? 2 : descLines,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: descFontSize,
                              height: 1.35,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
