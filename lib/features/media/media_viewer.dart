import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class MediaViewer extends StatefulWidget {
  const MediaViewer({super.key, required this.path, required this.image});
  final String path;
  final bool image;
  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  Player? player;
  VideoController? video;
  @override
  void initState() {
    super.initState();
    if (!widget.image) {
      player = Player();
      video = VideoController(player!);
      player!.open(Media(widget.path));
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Media')),
    body: Center(
      child: widget.image
          ? InteractiveViewer(
              child: Image.file(
                File(widget.path),
                errorBuilder: (_, error, stack) =>
                    const Text('This image format cannot be displayed.'),
              ),
            )
          : Video(controller: video!),
    ),
  );
}
