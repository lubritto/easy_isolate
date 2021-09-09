# Easy Isolate
[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat&logo=appveyor&logo=Flutter&logoColor=white)](https://flutter.dev)
[![pub package](https://img.shields.io/pub/v/easy_isolate.svg)](https://pub.dartlang.org/packages/easy_isolate)
[![GitHub](https://img.shields.io/badge/github-%23121011.svg?style=flat&logo=github&logoColor=white)](https://github.com/lubritto/easy_isolate)

An abstraction of isolates providing an easy way to work with different threads

## Features
 - [Worker](#worker)
 - [Parallel](#parallel) 
    - [Run](#parallel-run) - Executes a function in a different thread.
    - [Map](#parallel-map) -  Works like a map but each value will be adapted in a different thread
    - [Foreach](#parallel-foreach) - Works like a for in loop but each value will be executed in a different thread
   
## How it works

### Worker <a id="worker"></a>

A worker is responsible for 1 new thread (isolate). Everything you need to do to start a new thread is initiate
a new worker and call the `init` function providing 2 parameters, a MainMessageHandler and an IsolateMessageHandler.

```dart
void main() async {
  final worker = Worker();
  await worker.init(mainHandler, isolateHandler);  
}

void mainHandler(dynamic data, SendPort isolateSendPort) {
  
}

void isolateHandler(dynamic data, SendPort mainSendPort, SendErrorFunction onSendError) {
  
}
```

The `mainHandler` will receive messages coming from the isolate, and the `isolateHandler` the messages coming from the
main thread.

> Important note: Since you are working with different threads remember that they don't share the same space of memory,
> which means that all instances and states present on the main thread are not available on the new threads.
>
> Because of these particularities, the `isolateHandler` should be a top-level function or a static method.

You can use the worker `initialMessage` parameter to start the isolate sending an initial message. When the worker be
ready, the initial message will be sent to the isolate and received in the isolateHandler.

```dart
...
  await worker.init(mainHandler, isolateHandler, initialMessage: 'firstMessage');  
}

...
void isolateHandler(dynamic data, SendPort mainSendPort, SendErrorFunction onSendError) {
  // Event 'firstMessage' received when the worker is ready
}
```

Now that you have the worker ready, and with that a new thread running, the next step is understanding how to
communicate between them.

#### Sending messages to the isolate/thread

There are two ways to communicate with the isolate, the first one is using the method available in the worker
`worker.sendMessage(null)`, and the other one is using the SendPort inside the `mainHandler`. Let's suppose that you
are running more than one worker in your application and want to handle all the incoming messages from the isolates
to the main using only one handler. For this case, the SendPort inside the `mainHandler` is always related to the
isolate that is sending the message.

Example using the sendMessage:

```dart
void main() async {
  final worker = Worker();
  await worker.init(mainHandler, isolateHandler);
  
  worker.sendMessage(null);
}

...
```

Example using the mainHandler SendPort:

```dart
...

void mainHandler(dynamic data, SendPort isolateSendPort) {
  isolateSendPort.send(null);
}

...
```

#### Sending messages to the main thread

There is only one way to communicate with the main thread through the isolate, using the main SendPort available in the
`isolateHandler`.


```dart
...

void isolateHandler(dynamic data, SendPort mainSendPort, SendErrorFunction onSendError) {
  mainSendPort.send(null);
}
```

> Good to know: Only primitive types can be sent on the messages, but you can send class objects between them containing
> the primitive values. Example: You can instantiate a Car class inside the isolate and send it to the main thread, the
> object will be copied to another instance with all the primitive values intact.

#### Queue mode
By default, both handlers will handle all messages without awaiting the last one being processed. If your handlers 
are asynchronous and needs to be awaited before handling the next message, you can enable the 
`queueMode`. With this, only one message will be handled by time.

```
...
  await worker.init(mainHandler, isolateHandler, queueMode: true);
...
```

Now that you know how to start a worker and send messages, this plugin provides more two handlers on the init function,
the `errorHandler` and `exitHandler`.

The `errorHandler` will be called on two occasions, the first one is when any
unhandled exception being thrown on the isolate sending the exception stacktrace. The other one is using the
`SendErrorFunction` inside the isolateHandler, can be used to send the errors manually without necessarily having an
exception.

Example using the `errorHandler`:

```dart
void main() async {
  final worker = Worker();
  await worker.init(mainHandler, isolateHandler, errorHandler);

  worker.sendMessage(null);
}

void errorHandler(dynamic data) {
  // Handle the error here
}

...
```

Example sending messages manually:

```dart
...

void isolateHandler(dynamic data, SendPort mainSendPort, SendErrorFunction onSendError) {
  onSendError('Error');
}
```

The `exitHandler` is called when the worker is disposed or the isolate is closing.

Example:

```dart
void main() async {
  final worker = Worker();
  await worker.init(mainHandler, isolateHandler, errorHandler, exitHandler);

  worker.sendMessage(null);
}

void exitHandler(dynamic data) {
  // Handle the exit here
}

...
```

> Important note: The isolate automatically closes when unhandled exceptions happens inside the isolate. One way to 
> prevent this is using the `runGuardedZone` or wrapping the operations with try catchs.

#### Killing the worker

To kill the worker and close the open ports, the `worker.dispose()` should be called. By default, the dispose 
method will wait until the last message received (before dispose being called), or the current operations inside the 
isolate being processed to kill the isolate. The immediate option, `worker.dispose(immediate: true)`, can be used to kill the isolate the fast as possible,
without necessarily awaiting the last message or current operations finishing.

Congratulation, now you are ready to use the worker in your project.

### Parallel <a id="parallel"></a>

The Parallel class provides a set of ready to use methods including:

#### Run <a id="parallel-run"></a>

Executes a function in a different thread.

The `run` method will run the `handler` function provided in a separated thread, returning a value or not. There is 
also an `entryValue` parameter that can be used inside the `handler`.

Example:

```dart
Future main() async {
  final result = await Parallel.run(isEven, entryValue: 1);
  print(result);
}

// Top-level function (or static)
bool isEven({int? item}) {
  return item != null && item % 2 == 0;
}
```

#### Map <a id="parallel-map"></a>

Executes a map function in a different thread.

The `map` method works like a traditional mapper, iterating through the `values`, adapting with the `handler` function 
provided in the parameters, and returning a new List with the adapted values.

Example:

```dart
Future main() async {
  final result = await Parallel.map([1, 2, 3, 4], intToStringAdapter);
  print(result); // Should print all the values as a String
}

// Top-level function (or static)
String intToStringAdapter(int i) {
  return i.toString();
}
```

#### Foreach <a id="parallel-foreach"></a>

Executes a 'for in' loop function in a different thread.

The `foreach` method works like a traditional 'for in' loop, iterating through the `values`, running the `handler` 
function on each value provided in the parameters.

Example:

```dart
Future main() async {
  await Parallel.foreach(['test'], writeFile);
}

// Top-level function (or static)
void writeFile(String name) {
  File(Directory.systemTemp.path + '/$name').createSync();
}
```

###  Example

The example project is a simulation of a file downloader using a separated thread for each download. It will help you to 
understand how it works in practice. See the code [here](https://github.com/lubritto/easy_isolate/blob/main/example/lib/main.dart).

![macOS](https://github.com/lubritto/easy_isolate/blob/main/assets/gifs/example.gif)

### Contributions

If you liked the package and would like to contribute feels free to:
   - Open issues for suggestions or bugs [here](https://github.com/lubritto/easy_isolate/issues)
   - Sponsor the repo using the button on the top of the [github page](https://github.com/lubritto/easy_isolate/)
   - Leave your like on the [pub page](https://pub.dev/packages/easy_isolate) or a star in the [github page](https://github.com/lubritto/easy_isolate/)
   - Open PR's for new features
   - Share with your friends
