import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sync_client/sync_client.dart';

Future<Response> uploadConcurrently_old(
    {required String jsonString,
    required String url,
    required Map<String, String> headers,
    required String syncId,
    required int chunkSize,
    required int maxRetries,
    required SyncController syncController}) async {
  // Definisci il numero massimo di upload concorrenti
  final int maxConcurrentUploads = 3;
  final Uint8List fileBytes = Uint8List.fromList(utf8.encode(jsonString));
  final int totalSize = fileBytes.length;
  final int totalChunks = (totalSize / chunkSize).ceil();

  // Crea una coda di lavoro
  final queue = <Future>[];
  final results = <int, dynamic>{};
  final completer = Completer<void>();

  int completedChunks = 0;
  // Funzione per elaborare un singolo chunk
  Future<void> processChunk(int chunkIndex) async {
    try {
      print("ProcessChunk $chunkIndex");
      // Calcola gli indici di inizio e fine del chunk
      final int start = chunkIndex * chunkSize;
      final int end =
          (start + chunkSize > totalSize) ? totalSize : start + chunkSize;

      // Data to send...
      final String chunkData = jsonString.substring(start, end);
      // Estrai i dati del chunk
      //final List<int> chunkBytes = fileBytes.sublist(start, end);
      // Converti in base64 o altra rappresentazione come richiesto
      //final String chunkData = base64Encode(chunkBytes);
      // int retries = 0;
      //while (retries < maxRetries) {
      // Update the UI
      //FIXME
      /*syncController.add(SyncProgress(
          status: SyncStatus.pushing,
          message: 'Sending $chunkIndex/$totalChunks',
          processedItems: completedChunks + 1,
          totalItems: totalChunks));*/

      //try {
      // Post the data
      final Response response = await dio.post(url,
          data: jsonEncode({
            "chunkIndex": chunkIndex,
            "chunks": totalChunks,
            "data": chunkData,
            "start": start,
            "end": end,
            "syncId": syncId,
            "totalSize": totalSize
          }),
          options: Options(
              headers: {
                ...headers,
                'Content-Encoding': 'gzip',
              },
              requestEncoder: (data, options) =>
                  gzip.encode(utf8.encode(data))));
      results[chunkIndex] = response;
      return;
      // } catch (e) {
      //   retries++;
      //   debugPrint(
      //       "⚠️ Tentativo $retries per il chunk $chunkIndex fallito: $e");
      //   await Future.delayed(
      //       Duration(seconds: 2 * retries)); // Backoff esponenziale
      // }
      // if (retries >= maxRetries) {
      //   debugPrint("❌ Upload fallito dopo $maxRetries tentativi.");
      //   throw {"Upload fallito dopo $maxRetries tentativi"};
      // }
      // }
      // throw ("Failed upload attempt...");
    } catch (e) {
      // Gestione degli errori (potrebbe includere logica di retry)
      results[chunkIndex] = e;
      rethrow;
    } finally {
      completedChunks++;

      // Verifica se tutti i chunk sono stati completati
      if (completedChunks == totalChunks) {
        completer.complete();
      }
      // Rimuove questo task dalla coda e aggiunge il prossimo chunk se disponibile
      queue.remove(queue.first);
      final nextIndex = chunkIndex + maxConcurrentUploads;
      if (nextIndex < totalChunks) {
        final nextTask = processChunk(nextIndex);
        queue.add(nextTask);
      }
    }
  }

  // Avvia i primi N upload concorrenti
  for (int i = 0; i < min(maxConcurrentUploads, totalChunks); i++) {
    final task = processChunk(i);
    queue.add(task);
  }

  // Attendi il completamento di tutti i chunk
  await completer.future;

  // Verifica risultati e gestisci eventuali errori
  final errors = results.entries.where((e) => e.value is Exception).toList();
  if (errors.isNotEmpty) {
    throw Exception(
        'Errori in ${errors.length} chunk: ${errors.map((e) => e.key).join(', ')}');
  }

  return results.values.firstWhere((e) => (e as Response).statusCode == 200);
}

Future<Response> uploadConcurrently({
  required String jsonString,
  required String url,
  required Map<String, String> headers,
  required String syncId,
  required int chunkSize,
  required int maxRetries,
  required SyncController syncController,
}) async {
  const int maxConcurrentUploads = 3;
  final Uint8List fileBytes = Uint8List.fromList(utf8.encode(jsonString));
  final int totalSize = fileBytes.length;
  final int totalChunks = (totalSize / chunkSize).ceil();

  final Queue<Future<void>> queue = Queue();
  final Map<int, Response?> results = {};
  final Set<int> completedChunks = {};
  final Dio dio = Dio();
  final chunksInProcess = <int>{};

  /// Estrazione sicura della stringa UTF-8 senza spezzare caratteri multibyte
  String getSafeChunk(int start, int end) {
    return utf8.decode(fileBytes.sublist(start, end));
  }

  Future<void> processChunk(int chunkIndex) async {
    if (chunksInProcess.contains(chunkIndex)) {
      return;
    }
    chunksInProcess.add(chunkIndex);
    int retries = 0;
    while (retries < maxRetries) {
      try {
        final int start = chunkIndex * chunkSize;
        final int end =
            (start + chunkSize > totalSize) ? totalSize : start + chunkSize;
        final String chunkData = getSafeChunk(start, end);

        final Response response = await dio.post(url,
            data: jsonEncode({
              "chunkIndex": chunkIndex,
              "chunks": totalChunks,
              "data": chunkData,
              "start": start,
              "end": end,
              "syncId": syncId,
              "totalSize": totalSize,
              "multiple": 1 // Upload concurrency
            }),
            options: Options(
                headers: {
                  ...headers,
                  'Content-Encoding': 'gzip',
                },
                requestEncoder: (data, options) =>
                    gzip.encode(utf8.encode(data))));

        if (response.statusCode == 200 || response.statusCode == 206) {
          results[chunkIndex] = response;
          completedChunks.add(chunkIndex);
          return;
        }
      } catch (e) {
        retries++;
        debugPrint("⚠️ Retry $retries per il chunk $chunkIndex: $e");
        await Future.delayed(Duration(
            milliseconds: 500 * (1 << retries))); // Backoff esponenziale
      }
    }

    throw Exception(
        "❌ Upload fallito dopo $maxRetries tentativi per il chunk $chunkIndex");
  }

  // Avvia i primi chunk concorrenti
  for (int i = 0; i < min(maxConcurrentUploads, totalChunks); i++) {
    queue.add(processChunk(i));
  }

  // Gestione della coda di upload mantenendo maxConcurrentUploads attivi
  while (completedChunks.length < totalChunks) {
    await queue.removeFirst(); // Attende il completamento del primo task
    for (int i = 0; i < totalChunks; i++) {
      if (!completedChunks.contains(i) && queue.length < maxConcurrentUploads) {
        queue.add(processChunk(i));
      }
    }
  }

  await Future.wait(queue); // Attende il completamento di tutti i task

  // Gestione errori
  final errors = results.entries.where((e) => e.value == null).toList();
  if (errors.isNotEmpty) {
    throw Exception('Errori nei chunk: ${errors.map((e) => e.key).join(', ')}');
  }

  // Restituisce una delle risposte di successo
  return results.values.firstWhere((e) => e?.statusCode == 200)!;
}
