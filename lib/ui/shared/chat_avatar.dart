import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../telegram/client/td_client.dart';

class ChatAvatar extends StatefulWidget {
  const ChatAvatar({
    super.key,
    required this.app,
    required this.chat,
    this.topic = false,
  });
  final AppController app;
  final Json? chat;
  final bool topic;
  @override
  State<ChatAvatar> createState() => _ChatAvatarState();
}

class _ChatAvatarState extends State<ChatAvatar> {
  int? requested;
  @override
  Widget build(BuildContext context) {
    final photo = widget.chat?['photo']?['small'] as Json?;
    final file = photo == null ? null : widget.app.files[photo['id']] ?? photo;
    final path = file?['local']?['path'] as String?;
    if (file != null &&
        file['id'] != requested &&
        file['local']?['is_downloading_completed'] != true) {
      requested = file['id'] as int;
      widget.app.client
          ?.call('downloadFile', {
            'file_id': requested,
            'priority': 1,
            'offset': 0,
            'limit': 0,
            'synchronous': false,
          })
          .catchError((Object _) => <String, dynamic>{});
    }
    return CircleAvatar(
      backgroundImage:
          path != null && path.isNotEmpty && File(path).existsSync()
          ? FileImage(File(path))
          : null,
      child: path != null && path.isNotEmpty && File(path).existsSync()
          ? null
          : Icon(
              widget.chat == null
                  ? Icons.lock_outline
                  : widget.topic
                  ? Icons.tag
                  : widget.chat?['type']?['@type'] == 'chatTypePrivate'
                  ? Icons.person
                  : Icons.group_outlined,
            ),
    );
  }
}
