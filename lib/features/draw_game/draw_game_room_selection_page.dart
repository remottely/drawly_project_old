import 'package:drawly/features/draw_game/draw_game_room_page.dart';
import 'package:drawly_core/drawly_core.dart';
import 'package:flutter/material.dart';

class DrawGameRoomSelectionPage extends StatefulWidget {
  const DrawGameRoomSelectionPage({
    required this.userId,
    required this.username,
    super.key,
  });

  final String userId;
  final String username;

  @override
  State<DrawGameRoomSelectionPage> createState() =>
      _DrawGameRoomSelectionPageState();
}

class _DrawGameRoomSelectionPageState extends State<DrawGameRoomSelectionPage> {
  final roomController = TextEditingController();
  final List<String> allRooms = [];

  late final void Function(dynamic) _onAllRoomsEvent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void initState() {
    _initializeSocket();
    super.initState();
  }

  @override
  void dispose() {
    roomController.dispose();
    SocketManager.instance.off(SocketEvents.roomAll, _onAllRoomsEvent);
    super.dispose();
  }

  void _initializeSocket() {
    _onAllRoomsEvent = (data) {
      final rooms = (data as Map<String, dynamic>)['allRooms'];
      if (rooms is List<dynamic>) {
        setState(() {
          allRooms
            ..clear()
            ..addAll(rooms.whereType<String>());
        });
      } else {
        debugPrint('Unexpected data type: ${data.runtimeType}');
      }
    };
    SocketManager.instance.on(SocketEvents.roomAll, _onAllRoomsEvent);
  }

  void _createRoom() {
    final roomName = roomController.text.trim();
    if (roomName.isNotEmpty && roomName.length >= 3) {
      final payload = RoomDTO(roomName: roomName).toJson();

      SocketManager.instance.emit(SocketEvents.roomCreate, payload);
      roomController.clear();
    }
  }

  void _joinRoom(String roomName) {
    Navigator.push(
      context,
      MaterialPageRoute<Widget>(
        builder:
            (context) => DrawGameRoomPage(
              userId: widget.userId,
              username: widget.username,
              roomName: roomName,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select or Create a Room')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: roomController,
              decoration: const InputDecoration(
                labelText: 'Nome da sala', // Room Name
                hintText: 'Insira o nome da sala...', // Enter a room name...
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _createRoom,
              child: const Text('Nova Sala'), // Create Room
            ),
            const SizedBox(height: 16),
            const Text(
              'Salas disponíveis:', // Available Rooms:
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child:
                  allRooms.isEmpty
                      ? const Center(
                        child: Text('Nenhuma sala disponível no momento!'),
                      ) // No rooms available
                      : ListView.builder(
                        itemCount: allRooms.length,
                        itemBuilder: (context, index) {
                          final roomName = allRooms[index];
                          return ListTile(
                            title: Text(roomName),
                            trailing: ElevatedButton(
                              onPressed: () => _joinRoom(roomName),
                              child: const Text('Entrar na sala'),
                            ), // Join the room
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
