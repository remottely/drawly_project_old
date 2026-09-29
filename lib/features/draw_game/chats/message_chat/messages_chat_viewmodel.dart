import 'package:drawly/features/draw_game/chats/message_chat/messages_chat_view.dart';
import 'package:drawly/features/draw_game/models/message.dart';
import 'package:drawly_core/drawly_core.dart';
import 'package:flutter/material.dart';

abstract class MessagesChatViewModel extends State<MessagesChatView> {
  final messageController = TextEditingController();
  final scrollController = ScrollController();
  final rxAllMessages = ValueNotifier<List<Message>>([]);

  late final void Function(dynamic) _onNewMessageEvent;

  @override
  void initState() {
    super.initState();
    _initializeSocket();
  }

  @override
  void dispose() {
    messageController.dispose();
    SocketManager.instance.off(SocketEvents.chatMessage, _onNewMessageEvent);
    super.dispose();
  }

  void _initializeSocket() {
    _onNewMessageEvent = (data) {
      final message = Message.fromJson(data as Map<String, dynamic>);
      rxAllMessages.value = List.from(rxAllMessages.value)..add(message);
    };
    SocketManager.instance.on(SocketEvents.chatMessage, _onNewMessageEvent);
  }

  void sendMessage() {
    if (messageController.text.isNotEmpty) {
      final message = messageController.text;
      final payload =
          RoomUserMessageDTO(
            roomName: widget.roomName,
            userId: widget.userId,
            username: widget.username,
            text: message,
          ).toJson();

      SocketManager.instance.emit(SocketEvents.chatMessage, payload);

      messageController.clear();
    }
  }
}
