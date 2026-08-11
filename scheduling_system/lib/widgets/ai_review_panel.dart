// The AI's read on a replacement shortlist, above the ranked list on the
// Find Replacement screen.
//
// WHY THIS LOOKS NOTHING LIKE THE CARDS BELOW IT
//
// The candidate cards say what the rules found: a score, and chips for
// each reason. That is what a scoring function can produce, and it looks
// like one — which is exactly the problem this panel exists to solve.
// Ranking is invisible work. Two lists ordered slightly differently are
// indistinguishable to anyone who was not told to look.
//
// So this panel deliberately shows the three things chips cannot:
//
//   a written trade-off   prose, weighing one guard against another
//   a named risk          what this choice costs, when it costs something
//   the runner-up         who else, and why not them
//
// and, when it happens, the disagreement: the AI recommending somebody
// the rule-based score did not rank first is the single clearest
// evidence that judgement was applied rather than arithmetic.
//
// NOTHING HERE IS LOAD-BEARING. `review` is null whenever the AI has
// nothing to say and the panel renders nothing at all — not an error,
// not a placeholder. The list below is the feature; this is commentary
// on it.

import 'package:flutter/material.dart';

import '../models/replacement.dart';

class AiReviewPanel extends StatelessWidget {
  final AiReview? review;
  final bool isLoading;

  // Whoever the rule-based ranking put first, or null while the list is
  // still loading. Only used to decide whether to show the disagreement
  // line — the panel renders fully without it.
  final String? topRankedId;

  // Resolves a candidate id to a display name. Returns null for anyone
  // not on the shortlist, which the backend's validation makes
  // impossible for `recommendedId` but not for a stale `runnerUpId`.
  final String? Function(String id) nameFor;

  const AiReviewPanel({
    super.key,
    required this.review,
    required this.isLoading,
    required this.nameFor,
    this.topRankedId,
  });

  static const _ink = Color(0xFF1034A6);
  static const _wash = Color(0xFFF5F7FF);
  static const _edge = Color(0xFFC7D2FE);

  @override
  Widget build(BuildContext context) {
    if (isLoading) return _shell(child: _loading());
    final r = review;
    // The whole point of the fallback: no review, no panel, no gap where
    // one should have been.
    if (r == null) return const SizedBox.shrink();

    final name = nameFor(r.recommendedId);
    if (name == null) return const SizedBox.shrink();

    return _shell(child: _content(context, r, name));
  }

  Widget _shell({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _wash,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _edge),
      ),
      child: child,
    );
  }

  Widget _loading() {
    return Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: _ink),
        ),
        const SizedBox(width: 12),
        Text(
          'Reviewing the candidates…',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, AiReview r, String name) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: _ink),
            const SizedBox(width: 8),
            const Text(
              'AI Recommendation',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: _ink,
              ),
            ),
            const Spacer(),
            _confidenceChip(r.confidence),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          name,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          r.rationale,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: Color(0xFF334155),
          ),
        ),

        // The disagreement. Only shown when there is one, because a badge
        // that is always present stops being read — and this is the line
        // that proves the ranking was reconsidered rather than restated.
        if (r.differsFrom(topRankedId)) ...[
          const SizedBox(height: 12),
          _note(
            icon: Icons.swap_vert,
            color: const Color(0xFF7C3AED),
            text: 'Ranked differently from the rule-based score, which put '
                'someone else first.',
          ),
        ],

        if (r.risk != null && r.risk!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          _note(
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFFB45309),
            text: r.risk!.trim(),
          ),
        ],

        if (r.runnerUpId != null &&
            r.runnerUpTradeoff != null &&
            nameFor(r.runnerUpId!) != null) ...[
          const SizedBox(height: 12),
          const Divider(height: 1, color: _edge),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Color(0xFF64748B),
              ),
              children: [
                const TextSpan(
                  text: 'Runner-up: ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: '${nameFor(r.runnerUpId!)} — ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: r.runnerUpTradeoff!.trim()),
              ],
            ),
          ),
        ],

        // Named, not hidden. An admin overriding a recommendation is
        // entitled to know what produced it, and a capstone panel is
        // entitled to ask.
        if (r.model != null && r.model!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            r.model!,
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.grey[500],
              letterSpacing: 0.2,
            ),
          ),
        ],
      ],
    );
  }

  Widget _confidenceChip(String confidence) {
    final (label, color) = switch (confidence) {
      'strong' => ('Strong fit', const Color(0xFF16A34A)),
      'weak' => ('Weak fit', const Color(0xFFB45309)),
      _ => ('Moderate fit', const Color(0xFF2563EB)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _note({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, height: 1.4, color: color),
          ),
        ),
      ],
    );
  }
}
