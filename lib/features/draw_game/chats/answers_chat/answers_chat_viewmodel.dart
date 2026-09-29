import 'package:drawly/features/draw_game/chats/answers_chat/answers_chat_view.dart';
import 'package:drawly/features/draw_game/models/answer.dart';
import 'package:drawly_core/drawly_core.dart';
import 'package:flutter/material.dart';

abstract class AnswersChatViewModel extends State<AnswersChatView> {
  final answerController = TextEditingController();
  final scrollController = ScrollController();
  final rxAllAnswers = ValueNotifier<List<Answer>>([]);
  final rxIsCurrentUserCorrectAnswer = ValueNotifier<bool>(false);

  late final void Function(dynamic) _onNewTurnEvent;
  late final void Function(dynamic) _onNewAnswerEvent;

  @override
  void initState() {
    super.initState();
    _initializeSocket();
  }

  @override
  void dispose() {
    answerController.dispose();
    SocketManager.instance.off(
      SocketEvents.chatAnswerResult,
      _onNewAnswerEvent,
    );
    super.dispose();
  }

  void _initializeSocket() {
    _onNewTurnEvent = (data) {
      rxAllAnswers.value = [];
      rxIsCurrentUserCorrectAnswer.value = false;
    };
    _onNewAnswerEvent = (data) {
      final answer = Answer.fromJson(data as Map<String, dynamic>);
      rxAllAnswers.value = List.from(rxAllAnswers.value)..add(answer);
      rxIsCurrentUserCorrectAnswer.value =
          answer.isCorrect && answer.userId == widget.userId;
    };
    SocketManager.instance.on(SocketEvents.gameTurnNew, _onNewTurnEvent);
    SocketManager.instance.on(SocketEvents.chatAnswerResult, _onNewAnswerEvent);
  }

  void sendAnswer() {
    if (answerController.text.isNotEmpty) {
      final answer = answerController.text;

      final payload =
          RoomUserAnswerDTO(
            roomName: widget.roomName,
            userId: widget.userId,
            username: widget.username,
            text: answer,
          ).toJson();

      SocketManager.instance.emit(SocketEvents.chatAnswerGuess, payload);

      answerController.clear();
    }
  }
}
