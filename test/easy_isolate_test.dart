import 'dart:isolate';
import 'dart:math';

import 'package:easy_isolate/src/worker.dart';
import 'package:flutter_test/flutter_test.dart';

class FileDownloaderWorker {
  final worker = Worker();

  Future<void> init(String workerId) async {
    await worker.init(
      mainMessageHandler,
      isolateMessageHandler,
      errorHandler: print,
    );
    worker.sendMessage(DownloadFileEvent(workerId));
  }

  void mainMessageHandler(dynamic data, SendPort isolateSendPort) {
    if (data is DownloadFileEventResponse) {
      print('DownloadFileEventResponse Completed workerId: ${data.workerId}');
    }
  }

  static isolateMessageHandler(
      dynamic data, SendPort mainSendPort, SendErrorFunction sendError) async {
    if (data is DownloadFileEvent) {
      await Future.delayed(Duration(milliseconds: Random().nextInt(1500)));
      print('DownloadFileEvent workerId: ${data.workerId}');
      await Future.delayed(Duration(milliseconds: Random().nextInt(1500)));
      mainSendPort.send(DownloadFileEventResponse(data.workerId));
    }
  }
}

class FileDownloader {
  static final FileDownloader _singleton = FileDownloader._internal();

  factory FileDownloader() {
    return _singleton;
  }

  FileDownloader._internal();
}

class DownloadFileEvent {
  DownloadFileEvent(this.workerId);

  final String workerId;
}

class DownloadFileEventResponse {
  DownloadFileEventResponse(this.workerId);

  final String workerId;
}

void main() {
  test('adds one to input values', () async {
    await Future.delayed(Duration(seconds: 1));
  });
}
