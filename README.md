# Easy Isolate
[![pub package](https://img.shields.io/pub/v/easy_isolate.svg)](https://pub.dartlang.org/packages/easy_isolate)

An abstraction of the isolate providing an easy way to work with different threads

### How it works

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

Congratulation, now you are ready to use the worker in your project.

###  Example

The example project is a simulation of a file downloader using a separated thread for each download. It will help you to 
understand how it works in practice. See the code [here](https://github.com/lubritto/easy_isolate/blob/main/example/lib/main.dart).

![macOS](https://github.com/lubritto/easy_isolate/blob/main/assets/gifs/example.gif)

Feels free to open issues or add suggestions and, if you are happy using the plugin and would like to have more plugins
like this, help me with the sponsor button.