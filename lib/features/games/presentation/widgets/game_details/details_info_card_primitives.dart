part of 'details_info_card.dart';

class _StatLine extends StatelessWidget {
  const _StatLine({required this.label, required this.value});

  final Widget label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetricLine extends StatelessWidget {
  const _HeroMetricLine({
    required this.label,
    required this.value,
    this.trailingText,
    this.trailing,
  });

  final Widget label;
  final String value;
  final String? trailingText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  value,
                  style: AppTypography.monoMedium.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (trailingText != null)
                  Text(
                    trailingText!,
                    style: AppTypography.label.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ?trailing,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLabel extends StatelessWidget {
  const _InfoLabel(this.text, {this.emphasized = false});

  static const double _labelWidth = 110;
  static const double _labelGap = 12;
  static final TextStyle _baseStyle = AppTypography.bodySmall.copyWith(
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w500,
  );
  static final TextStyle _emphasizedStyle = AppTypography.bodySmall.copyWith(
    color: AppColors.textSecondary,
    fontWeight: FontWeight.w600,
  );

  final String text;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _labelWidth,
      child: Padding(
        padding: const EdgeInsets.only(right: _labelGap),
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: emphasized ? _emphasizedStyle : _baseStyle,
        ),
      ),
    );
  }
}
