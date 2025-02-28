import 'dart:async';
import 'dart:isolate';

import 'worker.dart';

typedef ParallelCallback<T, R> = FutureOr<R> Function({T? item});

/// A set of helpers for parallel computing
///
/// Methods provided:
///   - [Parallel.run] : Executes a function in a different thread.
///   - [Parallel.map] : Works like a map but each value will be adapted in a
///   different thread
///   - [Parallel.foreach] : Works like a for in loop but each value will be
///   executed in a different thread
class Parallel {
  /// Executes a function in a different thread.
  ///
  /// The [run] method will run the [handler] function provided in a
  /// separated thread, returning a value or not. There is also an [entryValue]
  /// parameter that can be used inside the [handler].
  ///
  /// Important note: Isolates/Threads don't share memory between them, which
  /// means that the [handler] provided should be a top-level or static function
  /// and the [entryValue] should use primitive values.
  ///
  /// Example:
  ///
  /// ```dart
  ///
  /// Future main() async {
  ///   final result = await Parallel.run(isEven, entryValue: 1);
  ///   print(result);
  /// }
  ///
  /// // Top-level function (or static)
  /// bool isEven({int? item}) {
  ///   return item != null && item % 2 == 0;
  /// }
  ///
  /// ```
  static FutureOr<R?> run<T, R>(
    ParallelCallback<T, R> handler, {
    T? entryValue,
  }) async {
    final completer = Completer();
    final worker = Worker();

    await worker.init(
      (data, _) {
        completer.complete(data);
        worker.dispose();
      },
      _isolateHandler,
      initialMessage: _ParallelRunParams<T, R>(entryValue, handler),
    );

    return await completer.future;
  }

  /// Executes a map function in a different thread.
  ///
  /// The [map] method works like a traditional mapper, iterating through the
  /// [values], adapting using the [handler] function provided in the
  /// parameters, and returning a new List with the adapted values.
  ///
  /// Important note: Isolates/Threads don't share memory between them, which
  /// means that the [handler] provided should be a top-level or static function
  /// and the [values] should use primitive values.
  ///
  /// Example:
  ///
  /// ```dart
  ///
  /// Future main() async {
  ///   final result = await Parallel.map([1, 2, 3, 4], intToStringAdapter);
  ///   print(result); // Should print all the values as a String
  /// }
  ///
  /// // Top-level function (or static)
  /// String intToStringAdapter(int i) {
  ///   return i.toString();
  /// }
  ///
  /// ```
  static FutureOr<List<R>> map<T, R>(
    List<T> values,
    FutureOr<R> Function(T item) handler,
  ) async {
    final completerList = Map.fromIterables(
      values,
      values.map((e) => Completer()),
    );

    for (final item in values) {
      final worker = Worker();
      await worker.init(
        (data, _) {
          completerList[item]?.complete(data);
          worker.dispose();
        },
        _isolateHandler,
        initialMessage: _ParallelMapParams(item, handler),
      );
    }

    final result = await Future.wait(completerList.values.map((e) => e.future));
    return result.cast<R>();
  }

  /// Executes a 'for in' loop function in a different thread.
  ///
  /// The [foreach] method works like a traditional 'for in' loop, iterating through
  /// the [values], running the [handler] function on each value provided in the
  /// parameters.
  ///
  /// Important note: Isolates/Threads don't share memory between them, which
  /// means that the [handler] provided should be a top-level or static function
  /// and the [values] should use primitive values.
  ///
  /// Example:
  ///
  /// ```dart
  ///
  /// Future main() async {
  ///   await Parallel.foreach(['test'], writeFile);
  /// }
  ///
  /// // Top-level function (or static)
  /// void writeFile(String name) {
  ///   File(Directory.systemTemp.path + '/$name').createSync();
  /// }
  ///
  /// ```
  static FutureOr<void> foreach<T>(
    List<T> values,
    FutureOr<void> Function(T item) handler,
  ) async {
    final completerList = Map.fromIterables(
      values,
      values.map((e) => Completer()),
    );

    for (final item in values) {
      final worker = Worker();
      await worker.init(
        (data, _) {
          completerList[item]?.complete(null);
          worker.dispose();
        },
        _isolateHandler,
        initialMessage: _ParallelForeachParams(item, handler),
      );
    }

    await Future.wait(completerList.values.map((e) => e.future));
  }

  /// The isolates handler for the parallel methods
  static void _isolateHandler(
    event,
    SendPort mainSendPort,
    SendErrorFunction? sendError,
  ) async {
    if (event is _ParallelMapParams) {
      final result = await event.apply();
      mainSendPort.send(result);
    } else if (event is _ParallelForeachParams) {
      await event.apply();
      mainSendPort.send(null);
    } else if (event is _ParallelRunParams) {
      final result = await event.apply();
      mainSendPort.send(result);
    }
  }
}

class _ParallelMapParams<T, R> {
  final T item;
  final FutureOr<R> Function(T item) handler;

  FutureOr<R> apply() => handler(item);

  _ParallelMapParams(this.item, this.handler);
}

class _ParallelForeachParams<T> {
  final dynamic item;
  final FutureOr<void> Function(T item) handler;

  FutureOr<void> apply() => handler(item);

  _ParallelForeachParams(this.item, this.handler);
}

class _ParallelRunParams<T, R> {
  final T? item;
  final ParallelCallback<T, R> _handler;

  FutureOr<R> apply() => _handler(item: item);

  _ParallelRunParams(this.item, this._handler);
}
