import 'package:flutter/material.dart';
import 'package:untitled1/utils/growth_recommendation.dart';

class GrowthRecommendationCard extends StatelessWidget {
  final String title;
  final GrowthRecommendation recommendation;
  final bool isRtl;
  final VoidCallback? onAction;

  const GrowthRecommendationCard({
    super.key,
    required this.title,
    required this.recommendation,
    this.isRtl = false,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final tip = recommendation;
    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
          ),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.tips_and_updates_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tip.summary,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tip.action,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (tip.ctaLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1D4ED8),
                ),
                onPressed: onAction,
                child: Text(tip.ctaLabel!, textAlign: TextAlign.center),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
