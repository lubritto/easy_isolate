import 'dart:async';
import 'dart:isolate';

import 'worker.dart';

/// Only copies
class Parallel {
  static FutureOr<R?> execute<T, R>(ParallelCallback<T, R> operation,
      {T? entry}) async {
    final completer = Completer();
    final worker = Worker();
    await worker.init((data, _) {
      completer.complete(data);
      worker.dispose();
    }, _isolateHandler);
    worker.sendMessage(_ParallelExecuteParams<T, R>(entry, operation));
    return await completer.future;
  }

  static FutureOr<List<R>> map<T, R>(
      List<T> entry, FutureOr<R> Function(T item) operation) async {
    final completers = Map.fromIterables(entry, entry.map((e) => Completer()));

    for (final item in entry) {
      final worker = Worker();
      await worker.init((data, _) {
        completers[item]?.complete(data);
        worker.dispose();
      }, _isolateHandler);

      worker.sendMessage(_ParallelMapParams(item, operation));
    }

    final result = await Future.wait(completers.values.map((e) => e.future));
    return result.cast<R>();
  }

  static FutureOr<void> foreach<T extends dynamic>(
      List<T> entry, FutureOr<void> Function(T item) operation) async {
    final completers = Map.fromIterables(entry, entry.map((e) => Completer()));

    for (final item in entry) {
      final worker = Worker();
      await worker.init((data, _) {
        completers[item]?.complete(null);
        worker.dispose();
      }, _isolateHandler);

      worker.sendMessage(_ParallelForeachParams(item, operation));
    }

    await Future.wait(completers.values.map((e) => e.future));
  }

  static void _isolateHandler(
      event, SendPort mainSendPort, SendErrorFunction? sendError) async {
    if (event is _ParallelMapParams) {
      final result = await event.apply();
      mainSendPort.send(result);
    } else if (event is _ParallelForeachParams) {
      await event.operation(event.item);
      mainSendPort.send(null);
    } else if (event is _ParallelExecuteParams) {
      final result = await event.apply();
      mainSendPort.send(result);
    }
  }
}

typedef ParallelCallback<T, R> = FutureOr<R> Function({T? item});

class _ParallelMapParams<T, R> {
  final T item;
  final FutureOr<R> Function(T item) operation;

  FutureOr<R> apply() => operation(item);

  _ParallelMapParams(this.item, this.operation);
}

class _ParallelForeachParams<T> {
  final dynamic item;
  final FutureOr<void> Function(T item) operation;

  FutureOr<void> apply() => operation(item);

  _ParallelForeachParams(this.item, this.operation);
}

class _ParallelExecuteParams<T, R> {
  final T? item;
  final ParallelCallback<T, R> _operation;

  FutureOr<R> apply() => _operation(item: item);

  _ParallelExecuteParams(this.item, this._operation);
}
