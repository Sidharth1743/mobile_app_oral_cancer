import 'dart:io';

import 'package:flutter/material.dart';

import '../../inference/yolo_prefilter.dart';
import '../components/status_badge.dart';

/// Shows each YOLO-processed frame before Gemma screening runs.
class YoloFrameReviewScreen extends StatefulWidget {
  const YoloFrameReviewScreen({super.key, required this.frames});

  final List<GemmaInputFrame> frames;

  @override
  State<YoloFrameReviewScreen> createState() => _YoloFrameReviewScreenState();
}

class _YoloFrameReviewScreenState extends State<YoloFrameReviewScreen> {
  late final PageController _pageController;
  int _index = 0;
  bool _showGemmaCrop = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  GemmaInputFrame get _current => widget.frames[_index];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.frames.length;
    final isLast = _index >= total - 1;
    final selectionLabel = _current.selection == 'yolo_crop'
        ? 'YOLO crop'
        : 'Full frame fallback';

    return Scaffold(
      appBar: AppBar(
        title: Text('YOLO frames (${_index + 1}/$total)'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                StatusBadge(
                  label: selectionLabel,
                  color: _current.selection == 'yolo_crop'
                      ? Colors.teal
                      : Colors.orange,
                ),
                const SizedBox(width: 8),
                if (_current.detection != null)
                  Text(
                    'conf ${(_current.detection!.confidence * 100).round()}%',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: total,
              onPageChanged: (value) => setState(() {
                _index = value;
                _showGemmaCrop = false;
              }),
              itemBuilder: (context, pageIndex) {
                final frame = widget.frames[pageIndex];
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      _showGemmaCrop
                          ? 'Image sent to Gemma (224×224)'
                          : 'Frame with YOLO boxes',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    _FrameImage(
                      path: _showGemmaCrop
                          ? frame.gemmaImagePath
                          : frame.annotatedFramePath,
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('YOLO boxes'),
                          icon: Icon(Icons.crop_free),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Gemma input'),
                          icon: Icon(Icons.image_outlined),
                        ),
                      ],
                      selected: {_showGemmaCrop},
                      onSelectionChanged: (selection) {
                        setState(() => _showGemmaCrop = selection.first);
                      },
                    ),
                    if (frame.detections.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Detections', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      for (var i = 0; i < frame.detections.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '#${i + 1}  '
                            'x1=${frame.detections[i].x1.toStringAsFixed(0)} '
                            'y1=${frame.detections[i].y1.toStringAsFixed(0)} '
                            'x2=${frame.detections[i].x2.toStringAsFixed(0)} '
                            'y2=${frame.detections[i].y2.toStringAsFixed(0)} '
                            'conf=${frame.detections[i].confidence.toStringAsFixed(2)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: _index > 0
                      ? () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                        }
                      : null,
                  child: const Text('Previous'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    if (isLast) {
                      Navigator.of(context).pop(true);
                    } else {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  child: Text(isLast ? 'Run Gemma analysis' : 'Next frame'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameImage extends StatelessWidget {
  const _FrameImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) {
      return const AspectRatio(
        aspectRatio: 1,
        child: ColoredBox(
          color: Color(0xFF1F2937),
          child: Center(child: Text('Image not found')),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        file,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Center(
          child: Text('Could not load image'),
        ),
      ),
    );
  }
}
