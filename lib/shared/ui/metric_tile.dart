import 'package:flutter/material.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/shared/ui/app_panel.dart';
import 'package:mise_gui/shared/ui/status_badge.dart';

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.metric});

  final SummaryMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusBadge(label: metric.label, level: metric.level),
          const SizedBox(height: 18),
          Text(
            metric.value,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 10),
          Text(
            metric.caption,
            style: TextStyle(color: colors.textMuted, height: 1.45),
          ),
        ],
      ),
    );
  }
}
