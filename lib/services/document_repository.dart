import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/canvas_models.dart';

abstract class DocumentRepository {
  Future<List<DocumentSummary>> loadIndex();
  Future<DocumentModel?> loadDocument(String id);
  Future<void> saveDocument(DocumentModel document);
  Future<void> deleteDocument(String id);
}

/// 文件一文档，索引只保存列表，降低单个损坏文件的影响范围。
class FileDocumentRepository implements DocumentRepository {
  Future<void> _tail = Future<void>.value();

  Future<Directory> _documentsDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final documents =
        Directory('${root.path}${Platform.pathSeparator}documents');
    if (!await documents.exists()) await documents.create(recursive: true);
    return documents;
  }

  Future<File> _indexFile() async {
    final root = await getApplicationDocumentsDirectory();
    return File('${root.path}${Platform.pathSeparator}documents_index.json');
  }

  @override
  Future<List<DocumentSummary>> loadIndex() async {
    final file = await _indexFile();
    await _recoverInterruptedWrite(file);
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
      final summaries = decoded
          .map((item) => DocumentSummary.fromJson(item as Map<String, dynamic>))
          .toList();
      summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return summaries;
    } on Object {
      return [];
    }
  }

  @override
  Future<DocumentModel?> loadDocument(String id) async {
    final directory = await _documentsDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$id.json');
    await _recoverInterruptedWrite(file);
    if (!await file.exists()) return null;
    try {
      return DocumentModel.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveDocument(DocumentModel document) => _enqueue(() async {
        final directory = await _documentsDirectory();
        final file = File(
            '${directory.path}${Platform.pathSeparator}${document.id}.json');
        await _writeAtomically(file, jsonEncode(document.toJson()));
        final summaries = await loadIndex();
        summaries.removeWhere((summary) => summary.id == document.id);
        summaries.add(document.summary);
        summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        await _writeAtomically(
          await _indexFile(),
          jsonEncode(summaries.map((summary) => summary.toJson()).toList()),
        );
      });

  @override
  Future<void> deleteDocument(String id) => _enqueue(() async {
        final directory = await _documentsDirectory();
        final document =
            File('${directory.path}${Platform.pathSeparator}$id.json');
        if (await document.exists()) await document.delete();
        final summaries = await loadIndex();
        summaries.removeWhere((summary) => summary.id == id);
        await _writeAtomically(
          await _indexFile(),
          jsonEncode(summaries.map((summary) => summary.toJson()).toList()),
        );
      });

  Future<void> _writeAtomically(File target, String contents) async {
    await _recoverInterruptedWrite(target);
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    if (!await target.exists()) {
      await temporary.rename(target.path);
      return;
    }
    final backup = File('${target.path}.bak');
    if (await backup.exists()) await backup.delete();
    await target.rename(backup.path);
    try {
      await temporary.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }

  /// 写入中断时保留旧版本；首次写入可安全采用完成的 tmp 文件。
  Future<void> _recoverInterruptedWrite(File target) async {
    final backup = File('${target.path}.bak');
    final temporary = File('${target.path}.tmp');
    if (await target.exists()) {
      if (await backup.exists()) await backup.delete();
      return;
    }
    if (await backup.exists()) {
      await backup.rename(target.path);
    } else if (await temporary.exists()) {
      await temporary.rename(target.path);
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }
}

/// 供 Widget/单元测试使用，不会触及设备磁盘。
class MemoryDocumentRepository implements DocumentRepository {
  final Map<String, DocumentModel> _documents = {};

  @override
  Future<void> deleteDocument(String id) async {
    _documents.remove(id);
  }

  @override
  Future<DocumentModel?> loadDocument(String id) async => _documents[id];

  @override
  Future<List<DocumentSummary>> loadIndex() async {
    final result =
        _documents.values.map((document) => document.summary).toList();
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  @override
  Future<void> saveDocument(DocumentModel document) async {
    _documents[document.id] = document;
  }
}
