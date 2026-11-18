import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Servicio de gestión del Sandbox Local Estricto.
///
/// Garantiza que todos los archivos intermedios o de pre-exportación vivan
/// exclusivamente en subdirectorios aislados dentro de `TemporaryDirectory`
/// (`CacheDir`) y se destruyan inmediatamente tras exportar, cancelar o iniciar la app.
class SandboxCleanerService {
  static const String _workspaceFolderName = 'local_convert_sandbox';

  final Future<Directory> Function() _tempDirProvider;

  SandboxCleanerService({
    Future<Directory> Function()? tempDirProvider,
  }) : _tempDirProvider = tempDirProvider ?? getTemporaryDirectory;

  /// Obtiene o crea el directorio raíz del sandbox temporal de LocalConvert.
  Future<Directory> getSandboxRoot() async {
    final tempDir = await _tempDirProvider();
    final sandboxDir = Directory(p.join(tempDir.path, _workspaceFolderName));
    if (!await sandboxDir.exists()) {
      await sandboxDir.create(recursive: true);
    }
    return sandboxDir;
  }

  /// Crea una sesión efímera aislada para una tarea de conversión específica.
  Future<Directory> createSessionDir(String sessionId) async {
    final root = await getSandboxRoot();
    final sessionDir = Directory(p.join(root.path, sessionId));
    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }
    return sessionDir;
  }

  /// Destruye de forma inmediata y recursiva los archivos temporales de una sesión.
  Future<void> purgeSession(String sessionId) async {
    try {
      final root = await getSandboxRoot();
      final sessionDir = Directory(p.join(root.path, sessionId));
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
      }
    } on FileSystemException {
      // Ignorar bloqueos transitorios del SO; purgeAll() limpiará residuos en el próximo ciclo.
    }
  }

  /// Elimina un archivo temporal específico si aún existe.
  Future<void> deleteTempFile(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Silencioso en caso de que ya haya sido eliminado.
    }
  }

  /// Elimina de forma recursiva un directorio de sesión temporal por ruta absoluta.
  Future<void> deleteSessionDir(String? dirPath) async {
    if (dirPath == null || dirPath.isEmpty) return;
    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } on FileSystemException {
      // Silencioso si el SO libera descriptores de forma diferida.
    }
  }

  /// Purga absolutamente todo el directorio temporal de LocalConvert.
  /// Debe invocarse al iniciar la aplicación y al cerrar herramientas activas.
  Future<void> purgeAll() async {
    try {
      final root = await getSandboxRoot();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    } on FileSystemException {
      // Silencioso si el SO retiene algún descriptor momentáneamente.
    }
  }
}



