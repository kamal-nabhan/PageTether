import 'package:flutter/material.dart';

import '../../../core/models/book.dart';
import '../../../core/theme/app_theme.dart';

/// A premium-styled card for a single book on the library dashboard.
///
/// Shows a gradient cover banner, title/author, a progress bar, and a
/// call-to-action button that either resumes reading (progress > 0) or
/// opens the book for the first time.
class BookCard extends StatelessWidget {
  const BookCard({super.key, required this.book, required this.onOpen});

  final Book book;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final started = book.progress > 0;

    return Card(
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _CoverBanner(book: book),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  _ProgressBar(progress: book.progress),
                  const SizedBox(height: 4),
                  Text(
                    started
                        ? '${book.progressPercent}% • page ${book.currentPage} of ${book.pageCount}'
                        : '${book.pageCount} pages',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onOpen,
                      style: FilledButton.styleFrom(
                        backgroundColor: started
                            ? AppColors.card
                            : AppColors.accentPurple,
                        foregroundColor: AppColors.textPrimary,
                        side: started
                            ? const BorderSide(color: AppColors.border)
                            : BorderSide.none,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: Icon(
                        started ? Icons.play_arrow_rounded : Icons.menu_book_rounded,
                        size: 18,
                      ),
                      label: Text(started ? 'Continue Reading' : 'Open'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverBanner extends StatelessWidget {
  const _CoverBanner({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: book.coverGradient),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.25),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            top: 12,
            right: 12,
            child: Icon(
              Icons.picture_as_pdf_rounded,
              color: Colors.white70,
              size: 20,
            ),
          ),
          Positioned(
            left: 14,
            bottom: 12,
            right: 14,
            child: Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.2,
                shadows: [Shadow(blurRadius: 6, color: Colors.black45)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: progress.clamp(0.0, 1.0).toDouble(),
        minHeight: 6,
        backgroundColor: AppColors.card,
        valueColor: const AlwaysStoppedAnimation(AppColors.accentTeal),
      ),
    );
  }
}
