import 'package:drawing_board/src/src.dart';
import 'package:drawly_core/drawly_core.dart';
import 'package:drawly_design_system/drawly_design_system.dart';
import 'package:flutter/material.dart';

class DrawingBoard extends StatefulWidget {
  const DrawingBoard({
    required this.username,
    required this.roomName,
    required this.word,
    required this.isCurrentDrawer,
    super.key,
  })  : assert(
          username.length >= 3,
          'The username must be at least 3 characters long',
        ),
        assert(
          roomName.length >= 3,
          'The roomName must be at least 3 characters long',
        );

  final String username;
  final String roomName;
  final String word;
  final bool isCurrentDrawer;

  @override
  State<DrawingBoard> createState() => _DrawingBoardState();
}

class _DrawingBoardState extends State<DrawingBoard>
    with SingleTickerProviderStateMixin {
  final canvasGlobalKey = GlobalKey();
  late UndoRedoStack undoRedoStack;
  CurrentStrokeValueNotifier rxCurrentStroke = CurrentStrokeValueNotifier();
  final rxSelectedColor = ValueNotifier<Color>(Colors.black);
  final rxSelectedColorOpacity = ValueNotifier<double>(1);
  final rxCurrentStrokeSize = ValueNotifier<double>(6);
  // final rxEraserSize = ValueNotifier<double>(30.0);
  final rxDrawingTool = ValueNotifier<DrawingTool>(DrawingTool.pencil);
  final rxIsFilled = ValueNotifier<bool>(false);
  final rxPolygonSides = ValueNotifier<int>(3);
  // final rxBackgroundImage = ValueNotifier<ui.Image?>(null);
  final rxAllStrokes = ValueNotifier<List<Stroke>>([]);
  final rxIsShowGrid = ValueNotifier<bool>(false);

  late final void Function(dynamic) _onNewTurnEvent;

  @override
  void initState() {
    super.initState();
    undoRedoStack = UndoRedoStack(
      rxCurrentStroke: rxCurrentStroke,
      rxAllStrokes: rxAllStrokes,
    );
    _initializeSocket();
  }

  @override
  void dispose() {
    SocketManager.instance.off(SocketEvents.gameTurnNew, _onNewTurnEvent);
    super.dispose();
  }

  void _initializeSocket() {
    _onNewTurnEvent = (_) {
      undoRedoStack = UndoRedoStack(
        rxCurrentStroke: rxCurrentStroke,
        rxAllStrokes: rxAllStrokes,
      );
      rxCurrentStroke = CurrentStrokeValueNotifier();
      rxSelectedColor.value = Colors.black;
      rxSelectedColorOpacity.value = 1.0;
      rxCurrentStrokeSize.value = 6.0;
      // rxEraserSize.value = 30.0;
      rxDrawingTool.value = DrawingTool.pencil;
      rxIsFilled.value = false;
      rxPolygonSides.value = 3;
      // rxBackgroundImage.value = null;
      rxAllStrokes.value = [];
      rxIsShowGrid.value = false;
    };
    SocketManager.instance.on(SocketEvents.gameTurnNew, _onNewTurnEvent);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.isCurrentDrawer,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // backgroundColor: widget.isCurrentDrawer
        //     ? AppColors.lightSecondary
        //     : AppColors.lightPrimary,
        body: HotkeyListener(
          onRedo: undoRedoStack.redo,
          onUndo: undoRedoStack.undo,
          child: Row(
            children: [
              CanvasSideBar(
                rxDrawingTool: rxDrawingTool,
                rxSelectedColor: rxSelectedColor,
                rxSelectedColorOpacity: rxSelectedColorOpacity,
                rxCurrentStrokeSize: rxCurrentStrokeSize,
                // rxEraserSize: rxEraserSize,
                // rxCurrentSketch: rxCurrentStroke,
                // allSketches: allStrokes,
                rxIsFilled: rxIsFilled,
                rxPolygonSides: rxPolygonSides,
                // backgroundImage: backgroundImage,
                rxIsShowGrid: rxIsShowGrid,
                canvasGlobalKey: canvasGlobalKey,
                undoRedoStack: undoRedoStack,
                roomName: widget.roomName,
                isCurrentDrawer: widget.isCurrentDrawer,
              ),
              Expanded(
                flex: 5,
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    rxDrawingTool,
                    rxCurrentStrokeSize,
                    rxSelectedColor,
                    rxSelectedColorOpacity,
                    // rxEraserSize,
                    rxPolygonSides,
                    rxIsShowGrid,
                    rxIsFilled,
                    rxCurrentStroke,
                    rxAllStrokes,
                    // rxBackgroundImage,
                  ]),
                  builder: (context, _) {
                    return Stack(
                      children: [
                        DrawingCanvas(
                          options: DrawingCanvasOptions(
                            currentTool: rxDrawingTool.value,
                            size: rxCurrentStrokeSize.value,
                            strokeColor: rxSelectedColor.value,
                            opacity: rxSelectedColorOpacity.value,
                            backgroundColor: kCanvasColor,
                            polygonSides: rxPolygonSides.value,
                            showGrid: rxIsShowGrid.value,
                            fillShape: rxIsFilled.value,
                          ),
                          rxCurrentStroke: rxCurrentStroke,
                          rxAllStrokes: rxAllStrokes,
                          // rxBackgroundImage: rxBackgroundImage,
                          canvasGlobalKey: canvasGlobalKey,
                          username: widget.username,
                          roomName: widget.roomName,
                        ),
                        // Align(
                        //   alignment: Alignment.topCenter,
                        //   child: widget.isCurrentDrawer
                        //       ? DrawlyTitleContainer(
                        //   text:
                        // 'Current drawer: ${rxCurrentDrawerUsername.value}',
                        // )
                        //       : const SizedBox.shrink(),
                        //   // TODO(Kevin): Draw Tip
                        //   // Center(
                        //   //   child: Text(widget.word),
                        //   // ),
                        // ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
