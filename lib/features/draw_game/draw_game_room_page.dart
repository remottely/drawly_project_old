import 'dart:async';
import 'dart:developer' as developer;

import 'package:drawing_board/drawing_board.dart';
import 'package:drawly/features/draw_game/chats/answers_chat/answers_chat_view.dart';
import 'package:drawly/features/draw_game/chats/message_chat/messages_chat_view.dart';
import 'package:drawly/features/draw_game/participants/all_participants.dart';
import 'package:drawly/testing/tests.dart';
import 'package:drawly_core/drawly_core.dart';
import 'package:drawly_design_system/drawly_design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DrawGameRoomPage extends StatefulWidget {
  const DrawGameRoomPage({
    required this.userId,
    required this.username,
    required this.roomName,
    super.key,
  }) : assert(
         username.length >= 3,
         'The username must be at least 3 characters long',
       ),
       assert(
         roomName.length >= 3,
         'The roomName must be at least 3 characters long',
       );

  final String userId;
  final String username;
  final String roomName;

  @override
  State<DrawGameRoomPage> createState() => _DrawGameRoomPageState();
}

abstract class GamePageViewModel extends State<DrawGameRoomPage> {
  final rxWord = ValueNotifier<String?>(null);
  final rxCurrentDrawerUserId = ValueNotifier<String?>(null);
  final rxCurrentDrawerUsername = ValueNotifier<String?>(null);
  final rxIsCurrentDrawerUserId = ValueNotifier<bool>(false);
  final rxTotalDuration = ValueNotifier<int>(0);
  final rxIsGameStarted = ValueNotifier<bool>(false);
  final rxTimeLeft = ValueNotifier<int>(0);
  final rxTurn = ValueNotifier<int>(0);
  Timer? _countdownTimer;

  late final void Function(dynamic) _onConnectEvent;
  late final void Function(dynamic) _onNewTurnEvent;

  @override
  void initState() {
    super.initState();
    _initializeSocket();
  }

  @override
  void dispose() {
    SocketManager.instance.off(SocketEvents.connect, _onConnectEvent);
    SocketManager.instance.off(SocketEvents.gameTurnNew, _onNewTurnEvent);
    _leaveRoom();
    rxCurrentDrawerUserId.dispose();
    rxIsCurrentDrawerUserId.dispose();
    rxTotalDuration.dispose();
    rxTimeLeft.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  String? userAvatar;

  Future<void> getLocalStorageUserAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    userAvatar = prefs.getString('user_avatar_path');
  }

  Future<void> _initializeSocket() async {
    await getLocalStorageUserAvatar();
    Tests.createRoom(widget.roomName);
    await _joinGameRoom();
    _onConnectEvent = (_) async {
      await _joinGameRoom();
    };
    _onNewTurnEvent = (data) {
      rxWord.value = (data as Map<String, dynamic>)['word'] as String;
      rxCurrentDrawerUserId.value = data['currentDrawerUserId'] as String;
      rxIsCurrentDrawerUserId.value =
          rxCurrentDrawerUserId.value == widget.userId;
      rxCurrentDrawerUsername.value = data['currentDrawerUsername'] as String;
      rxTotalDuration.value = data['totalDuration'] as int;
      rxTurn.value = data['turn'] as int;
      rxTimeLeft.value = rxTotalDuration.value - 300;

      rxIsGameStarted.value = data['isGameStarted'] as bool;

      startCountdown(rxTotalDuration.value);
    };
    SocketManager.instance.on(SocketEvents.connect, _onConnectEvent);
    SocketManager.instance.on(SocketEvents.gameTurnNew, _onNewTurnEvent);
  }

  void startCountdown(int durationInMs) {
    // Cancela o temporizador anterior, se existir.
    _countdownTimer?.cancel();

    var remaining = durationInMs;

    _countdownTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (remaining <= 0) {
        timer.cancel();
        _countdownTimer = null;
        return;
      }

      remaining -= 100;
      rxTimeLeft.value = remaining;
    });
  }

  Future<void> _joinGameRoom() async {
    final payload =
        RoomUserDTO(
          roomName: widget.roomName,
          userId: widget.userId,
          username: widget.username,
          userAvatar: userAvatar,
          isLogged: false,
        ).toJson();

    try {
      final responseData = await SocketManager.instance.emitWithAck(
        SocketEvents.roomJoin,
        payload,
      );
      if (responseData['success'] == false) {
        if (mounted) {
          developer.log('join message: ${responseData['message']}');
          Navigator.of(context).pop();
        }
      } else {
        rxTurn.value = responseData['turn'] as int;
        rxIsGameStarted.value = responseData['isGameStarted'] as bool;
        rxCurrentDrawerUserId.value =
            responseData['currentDrawerUserId'] as String;
        rxIsCurrentDrawerUserId.value =
            rxCurrentDrawerUserId.value == widget.userId;
      }
    } catch (e) {
      developer.log('Error joining room: $e');
    }
  }

  void _leaveRoom() {
    final payload =
        RoomUserDTO(
          roomName: widget.roomName,
          userId: widget.userId,
          username: widget.username,
          userAvatar: userAvatar,
          isLogged: false,
        ).toJson();

    SocketManager.instance.emit(SocketEvents.roomLeave, payload);
  }
}

class _DrawGameRoomPageState extends GamePageViewModel {
  @override
  Widget build(BuildContext context) {
    void testDisconnection4s() => Tests.testDisconnectionThenReconnection4s();

    return Stack(
      children: [
        AnimatedBuilder(
          animation: Listenable.merge([rxIsCurrentDrawerUserId, rxTurn]),
          builder: (context, _) {
            return Scaffold(
              backgroundColor:
                  rxIsCurrentDrawerUserId.value
                      ? AppColors.greenAccent
                      : AppColors.lightPrimary,
              body: Column(
                children: [
                  AnimatedBuilder(
                    animation: Listenable.merge([rxTimeLeft, rxTotalDuration]),
                    builder: (context, _) {
                      if (rxTimeLeft.value <= 0) return const SizedBox.shrink();
                      return LinearProgressIndicator(
                        value: rxTimeLeft.value / rxTotalDuration.value,
                        minHeight: 5,
                        backgroundColor: AppColors.lightGrey300,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.redAccent,
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              DrawlyFakeAppBar(
                                children: [
                                  Flexible(
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Text(
                                        '${widget.roomName} | ${rxTurn.value}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Expanded(
                                child: AnimatedBuilder(
                                  animation: Listenable.merge([
                                    rxCurrentDrawerUserId,
                                  ]),
                                  builder: (context, _) {
                                    return AllParticipants(
                                      userId: widget.userId,
                                      currentDrawerUserId:
                                          rxCurrentDrawerUserId.value,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: AnimatedBuilder(
                            animation: Listenable.merge([
                              rxWord,
                              rxCurrentDrawerUserId,
                            ]),
                            builder: (context, _) {
                              return Column(
                                children: [
                                  DrawlyFakeAppBar(
                                    children: [
                                      if (rxIsCurrentDrawerUserId.value)
                                        DrawlyTitleContainer(
                                          text: rxWord.value ?? '',
                                        )
                                      else
                                        DrawlyTitleContainer(
                                          text:
                                              rxCurrentDrawerUserId.value ==
                                                      null
                                                  ? 'Intervalo...'
                                                  : '''Vez de ${rxCurrentDrawerUsername.value}''',
                                          textColor: AppColors.black,
                                          color:
                                              rxIsCurrentDrawerUserId.value
                                                  ? AppColors.greenAccent
                                                  : AppColors.yellowAccent,
                                        ),
                                      if (Tests.isTesting) ...[
                                        IconButton(
                                          onPressed: testDisconnection4s,
                                          icon: const Icon(
                                            Icons.wifi_off_sharp,
                                            color: Colors.white,
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: testDisconnection4s,
                                          icon: const Icon(
                                            Icons.wifi_off_sharp,
                                          ),
                                        ),
                                      ] else
                                        const SizedBox.shrink(),
                                    ],
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        DrawingBoard(
                                          username: widget.username,
                                          roomName: widget.roomName,
                                          word: rxWord.value ?? '',
                                          isCurrentDrawer:
                                              rxIsCurrentDrawerUserId.value,
                                        ),
                                        ValueListenableBuilder<int>(
                                          valueListenable: rxTurn,
                                          builder: (_, value, __) {
                                            return Opacity(
                                              opacity: value == 0 ? 1.0 : 0.0,
                                              child: IgnorePointer(
                                                ignoring: value != 0,
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  child: DrawlyBackFilter(
                                                    child: Center(
                                                      child: ElevatedButton(
                                                        onPressed: () {
                                                          final payload =
                                                              RoomDTO(
                                                                roomName:
                                                                    widget
                                                                        .roomName,
                                                              ).toJson();

                                                          SocketManager.instance
                                                              .emit(
                                                                SocketEvents
                                                                    .gameTurnsStart,
                                                                payload,
                                                              );
                                                        },
                                                        child: const Text(
                                                          'Start Game',
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: AnimatedBuilder(
                                      animation: Listenable.merge([
                                        rxIsGameStarted,
                                      ]),
                                      builder: (context, _) {
                                        return Row(
                                          children: [
                                            Expanded(
                                              child: AnswersChatView(
                                                userId: widget.userId,
                                                username: widget.username,
                                                roomName: widget.roomName,
                                                isCurrentDrawer:
                                                    rxIsCurrentDrawerUserId
                                                        .value,
                                                isGameStarted:
                                                    rxIsGameStarted.value,
                                              ),
                                            ),
                                            Expanded(
                                              child: MessagesChatView(
                                                userId: widget.userId,
                                                username: widget.username,
                                                roomName: widget.roomName,
                                                isCurrentDrawer:
                                                    rxIsCurrentDrawerUserId
                                                        .value,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        // const MeteorShower(
        //   numberOfMeteors: 20,
        //   child: Center(),
        // ),
      ],
    );
  }
}

class DrawlyFakeAppBar extends StatelessWidget {
  const DrawlyFakeAppBar({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: children,
      ),
    );
  }
}
