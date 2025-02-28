import 'dart:async';
import 'dart:isolate';

typedef SendErrorFunction = Function(Object? data);

typedef MessageHandler = Function(dynamic data);

typedef MainMessageHandler = FutureOr Function(
  dynamic data,
  SendPort isolateSendPort,
);

typedef IsolateMessageHandler = FutureOr Function(
  dynamic data,
  SendPort mainSendPort,
  SendErrorFunction onSendError,
);

/// An abstraction of the [Isolate] to make it easier to use without loosing
/// the control of it's capabilities.
///
/// Each worker will handle one isolate (thread), before using it you need to
/// call the [init] function providing the parameters that you need. Since the
/// isolate needs to be started and return the port to communicate with the main
/// thread, it needs to be awaited.
///
/// Example:
///
/// ```dart
///
/// ...
/// Future myMethod() async {
///   final worker = Worker();
///   await worker.init(mainMessageHandler, isolateMessageHandler);
/// }
///
/// void mainMessageHandler(dynamic data) {}
///
/// static void isolateMessageHandler(
///   dynamic data, SendPort mainSendPort, SendErrorFunction sendError) {}
/// ...
///
/// ```
///
/// Note: The isolate handler should be static or a top level function, and
/// since it's called inside another thread doesn't share any instance with the
/// main thread.
///
/// Check the [init] and [send] documentation for more information.
class Worker {
  /// Holds the instance of the isolate
  late Isolate _isolate;

  /// Holds the instance of the main thread port for communication
  late ReceivePort _mainReceivePort;

  /// Holds the instance of the isolate open port to send messages
  late SendPort _isolateSendPort;

  /// The completer used to make the [init] async awaiting until receive the
  /// isolate send port from the isolate
  final _completer = Completer<void>();

  /// Return if the worker is initialized. Can be used to validate before
  /// sending messages in the case where it's not possible to await the [init]
  /// execution.
  bool get isInitialized => _completer.isCompleted;

  /// The worker initializer.
  ///
  /// Provides 4 parameters:
  ///
  /// - MainHandler: Receives and handle the messages coming from the isolate
  /// with the message data and the isolate SendPort as parameters, that can be
  /// used to send messages back to the isolate or using the [send] method.
  ///
  /// - IsolateHandler: Receives and handle messages coming from the sender with
  /// the message data and the main SendPort as parameters, that can be
  /// used to send messages back to the main thread.
  ///
  /// - initialMessage: Can be used to start the isolate sending a initial
  /// message
  ///
  /// - queueMode: when enabled, the ports await the last event being handled to
  /// read the next one. By default is false.
  ///
  /// - errorHandler: Receives the error events from the isolate. Tt can be
  /// non handled errors or errors manually sent using the [SendErrorFunction]
  /// inside the isolate handler.
  ///
  /// - exitHandler: Called when the isolate is being closed.
  ///
  /// Important note: Be careful with non handled errors inside the isolate,
  /// it automatically closes sending the exit event. To avoid this, you can use
  /// try catch on the operations or wraps everything in a [runZonedGuarded].
  Future<void> init(
    MainMessageHandler mainHandler,
    IsolateMessageHandler isolateHandler, {
    Object? initialMessage = const _NoParameterProvided(),
    bool queueMode = false,
    MessageHandler? errorHandler,
    MessageHandler? exitHandler,
  }) async {
    assert(isInitialized == false);
    if (isInitialized) return;

    /// The port to communicate with the main thread
    _mainReceivePort = ReceivePort();
    final errorPort = _initializeAndListen(errorHandler);
    final exitPort = _initializeAndListen(exitHandler);

    _isolate = await Isolate.spawn(
      _isolateInitializer,
      _IsolateInitializerParams(
        _mainReceivePort.sendPort,
        errorPort?.sendPort,
        isolateHandler,
        queueMode,
      ),
      onError: errorPort?.sendPort,
      onExit: exitPort?.sendPort,
    );

    /// Listen the main port to handle messages coming from the isolate
    _mainReceivePort.listen((message) async {
      /// The first message received from the isolate will be the isolate port,
      /// the port is saved and the worker is ready to work
      if (message is SendPort) {
        _isolateSendPort = message;
        if (!(initialMessage is _NoParameterProvided)) {
          _isolateSendPort.send(initialMessage);
        }
        _completer.complete();
        return;
      }
      final handlerFuture = mainHandler(message, _isolateSendPort);
      if (queueMode) {
        await handlerFuture;
      }
    }).onDone(() async {
      /// Waits 2 seconds to close the error and exit ports, enabling to receive
      /// the events when the worker is disposed manually.
      await Future.delayed(Duration(seconds: 2));
      errorPort?.close();
      exitPort?.close();
    });

    return await _completer.future;
  }

  /// Responsible for killing the isolate and close the main thread port
  ///
  /// The shutdown is performed at different times depending on the priority:
  ///
  /// * `immediate = true`: The isolate shuts down as soon as possible.
  ///     Control messages are handled in order, so all previously sent control
  ///     events from this isolate will all have been processed.
  ///     The shutdown should happen no later than if sent with
  ///     `immediate = false`.
  ///     It may happen earlier if the system has a way to shut down cleanly
  ///     at an earlier time, even during the execution of another event.
  /// * `immediate = false`: The shutdown is scheduled for the next time
  ///     control returns to the event loop of the receiving isolate,
  ///     after the current event, and any already scheduled control events,
  ///     are completed.
  void dispose({bool immediate = false}) {
    _mainReceivePort.close();
    _isolate.kill(
      priority: immediate ? Isolate.immediate : Isolate.beforeNextEvent,
    );
  }

  ReceivePort? _initializeAndListen(MessageHandler? handler) {
    if (handler == null) return null;
    return ReceivePort()..listen(handler);
  }

  /// Responsible for sending messages to the isolate.
  ///
  /// The isolate worker should be initiated before using it, validating with
  /// the [isInitialized] or awaiting the [init]
  void sendMessage(Object? message) {
    if (!isInitialized) throw Exception('Worker is not initialized');
    _isolateSendPort.send(message);
  }

  /// Responsible for initializing the isolate, send the sendPort to the main,
  /// and call the [isolateHandler] provided in the [init].
  static Future<void> _isolateInitializer(
    _IsolateInitializerParams params,
  ) async {
    /// Create the port to communicate with the isolate
    var isolateReceiverPort = ReceivePort();

    /// Send the isolate port to the main thread using the port in the params
    params.mainSendPort.send(isolateReceiverPort.sendPort);

    /// Listen the isolate port to handle messages coming from the main
    await for (var data in isolateReceiverPort) {
      final handlerFuture = params.isolateHandler(
        data,
        params.mainSendPort,
        params.errorSendPort?.send ?? (_) {},
      );
      if (params.queueMode) {
        await handlerFuture;
      }
    }
  }
}

/// The parameters used to initiate the isolate internally
class _IsolateInitializerParams {
  _IsolateInitializerParams(
    this.mainSendPort,
    this.errorSendPort,
    this.isolateHandler,
    this.queueMode,
  );

  final SendPort mainSendPort;
  final SendPort? errorSendPort;
  final IsolateMessageHandler isolateHandler;
  final bool queueMode;
}

class _NoParameterProvided {
  const _NoParameterProvided();
}
