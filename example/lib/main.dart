import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:easy_isolate/easy_isolate.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: FileDownloaderScreen(),
    );
  }
}

class FileDownloaderScreen extends StatefulWidget {
  FileDownloaderScreen({Key? key}) : super(key: key);

  @override
  _FileDownloaderScreenState createState() => _FileDownloaderScreenState();
}

class _FileDownloaderScreenState extends State<FileDownloaderScreen> {
  final List<DownloadItem> items =
      List.generate(100, (index) => DownloadItem('Item ${index + 1}'));

  final Map<DownloadItem, double> itemsDownloadProgress = {};

  void notifyProgress(DownloadItemProgressEvent event) {
    final item = event.item;
    if (itemsDownloadProgress.containsKey(item)) {
      itemsDownloadProgress.update(
        item,
        (value) => event.progress,
      );
    } else {
      itemsDownloadProgress.addAll({item: event.progress});
    }
    setState(() {});
  }

  bool hasOngoingDownload(DownloadItem item) {
    return itemsDownloadProgress.containsKey(item);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          SizedBox(height: 20),
          Text('File downloader simulation', style: theme.textTheme.headline5),
          SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Text(item.name),
                        Spacer(),
                        Text('${item.size}mb'),
                        SizedBox(width: 10),
                        if (hasOngoingDownload(item))
                          SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              value: itemsDownloadProgress[item],
                            ),
                          )
                        else ...[
                          IconButton(
                            icon: Icon(Icons.download),
                            onPressed: () => FileDownloaderWorker(
                              item: item,
                              onNotifyProgress: notifyProgress,
                            ).init(),
                          ),
                        ]
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DownloadItem {
  DownloadItem(this.name) : size = Random().nextInt(50);

  final String name;
  final int size;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadItem &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          size == other.size);

  @override
  int get hashCode => name.hashCode ^ size.hashCode;
}

class FileDownloaderWorker {
  FileDownloaderWorker({required this.onNotifyProgress, required this.item});

  final Function(DownloadItemProgressEvent event) onNotifyProgress;
  final DownloadItem item;
  final worker = Worker();

  /// Initiate the worker (new thread) and start listen from messages between
  /// the threads
  Future<void> init() async {
    await worker.init(
      mainMessageHandler,
      isolateMessageHandler,
      errorHandler: print,
    );
    worker.sendMessage(DownloadItemEvent(item));
  }

  /// Handle the messages coming from the isolate
  void mainMessageHandler(dynamic data, SendPort isolateSendPort) {
    if (data is DownloadItemProgressEvent) {
      onNotifyProgress(data);
    }
  }

  /// Handle the messages coming from the main
  static isolateMessageHandler(
      dynamic data, SendPort mainSendPort, SendErrorFunction sendError) async {
    if (data is DownloadItemEvent) {
      final fragmentTime = 1 / data.item.size;
      double progress = 0;
      Timer.periodic(
        Duration(seconds: 1),
        (timer) {
          if (progress < 1) {
            progress += fragmentTime;
            mainSendPort.send(DownloadItemProgressEvent(data.item, progress));
          } else {
            timer.cancel();
          }
        },
      );
    }
  }
}

class DownloadItemEvent {
  DownloadItemEvent(this.item);

  final DownloadItem item;
}

class DownloadItemProgressEvent {
  DownloadItemProgressEvent(this.item, this.progress);

  final DownloadItem item;
  final double progress;
}
