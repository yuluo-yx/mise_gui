import 'package:flutter/material.dart';
import 'package:mise_gui/app/theme/app_theme.dart';

class AppPageScaffold extends StatefulWidget {
  const AppPageScaffold({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final String description;
  final Widget child;
  final List<Widget> actions;

  @override
  State<AppPageScaffold> createState() => _AppPageScaffoldState();
}

class _AppPageScaffoldState extends State<AppPageScaffold> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final scrollBehavior = ScrollConfiguration.of(
      context,
    ).copyWith(scrollbars: false);

    return ScrollConfiguration(
      behavior: scrollBehavior,
      child: RawScrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        trackVisibility: false,
        thickness: 8,
        radius: const Radius.circular(999),
        crossAxisMargin: 10,
        mainAxisMargin: 16,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(24, 24, 34, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colors.panelRaised.withValues(alpha: 0.26),
                      colors.panel.withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: colors.border.withValues(alpha: 0.55),
                  ),
                ),
                child: Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.description,
                            style: TextStyle(
                              color: colors.textMuted,
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.actions.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.backgroundSoft.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: colors.border),
                        ),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: widget.actions,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              widget.child,
            ],
          ),
        ),
      ),
    );
  }
}
