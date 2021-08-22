import 'dart:async';
import 'dart:isolate';

typedef SendErrorFunction = Function(Object? data);
typedef MessageHandler = Function(dynamic data);
typedef MainMessageHandler = Function(dynamic data, SendPort isolateSendPort);
typedef IsolateMessageHandler = Function(
    dynamic data, SendPort mainSendPort, SendErrorFunction onSendError);

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

  /// Holds the instance of the isolate open port to send messages
  late SendPort _isolateSendPort;

  /// The completer used to make the [init] async awaiting until receive the
  /// isolate send port from the isolate
  final _completer = Completer();

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
    MessageHandler? errorHandler,
    MessageHandler? exitHandler,
  }) async {
    assert(isInitialized == false);
    if (isInitialized) return;

    /// The port to communicate with the main thread
    final mainReceivePort = ReceivePort();
    final errorPort = _initializeAndListen(errorHandler);
    final exitPort = _initializeAndListen(exitHandler);

    _isolate = await Isolate.spawn(
      _isolateInitializer,
      _IsolateInitializerParams(
          mainReceivePort.sendPort, errorPort?.sendPort, isolateHandler),
      onError: errorPort?.sendPort,
      onExit: exitPort?.sendPort,
    );

    /// Listen the main port to handle messages coming from the isolate
    mainReceivePort.listen((message) {
      /// The first message received from the isolate will be the isolate port,
      /// the port is saved and the worker is ready to work
      if (message is SendPort) {
        _isolateSendPort = message;
        _completer.complete();
        return;
      }
      mainHandler(message, _isolateSendPort);
    });

    return await _completer.future;
  }

  void dispose() {
    _isolate.kill();
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
      params.isolateHandler(
        data,
        params.mainSendPort,
        params.errorSendPort?.send ?? (_) {},
      );
    }
  }
}

/// The parameters used to initiate the isolate internally
class _IsolateInitializerParams {
  _IsolateInitializerParams(
      this.mainSendPort, this.errorSendPort, this.isolateHandler);

  final SendPort mainSendPort;
  final SendPort? errorSendPort;
  final IsolateMessageHandler isolateHandler;
}
