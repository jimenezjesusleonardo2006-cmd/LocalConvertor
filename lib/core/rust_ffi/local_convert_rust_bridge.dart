import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

typedef _RustAllocBufferNative = Pointer<Uint8> Function(UintPtr size);
typedef _RustAllocBufferDart = Pointer<Uint8> Function(int size);

typedef _RustFreeBufferNative = Void Function(Pointer<Uint8> ptr, UintPtr size);
typedef _RustFreeBufferDart = void Function(Pointer<Uint8> ptr, int size);

typedef _RustExecuteJsonNative = Pointer<Uint8> Function(
  Pointer<Uint8> reqPtr,
  UintPtr reqLen,
  Pointer<UintPtr> outLen,
);
typedef _RustExecuteJsonDart = Pointer<Uint8> Function(
  Pointer<Uint8> reqPtr,
  int reqLen,
  Pointer<UintPtr> outLen,
);

typedef _RustEncodeRgbaNative = Pointer<Uint8> Function(
  Pointer<Uint8> rgbaPtr,
  UintPtr rgbaLen,
  Uint32 width,
  Uint32 height,
  Pointer<Uint8> formatPtr,
  UintPtr formatLen,
  Uint8 quality,
  Pointer<UintPtr> outLen,
);
typedef _RustEncodeRgbaDart = Pointer<Uint8> Function(
  Pointer<Uint8> rgbaPtr,
  int rgbaLen,
  int width,
  int height,
  Pointer<Uint8> formatPtr,
  int formatLen,
  int quality,
  Pointer<UintPtr> outLen,
);

/// Puente seguro `dart:ffi` hacia el motor nativo en Rust (`local_convert_core`).
///
/// Diseñado para ejecutarse de forma síncrona dentro de un [Isolate] trabajador
/// (`Isolate.spawn` / `Isolate.run`), liberando explícitamente todos los buffers
/// nativos en bloques `finally` para garantizar cero fugas de memoria.
class LocalConvertRustBridge {
  LocalConvertRustBridge._(DynamicLibrary library)
      : _allocBuffer = library
            .lookup<NativeFunction<_RustAllocBufferNative>>('rust_alloc_buffer')
            .asFunction<_RustAllocBufferDart>(),
        _freeBuffer = library
            .lookup<NativeFunction<_RustFreeBufferNative>>('rust_free_buffer')
            .asFunction<_RustFreeBufferDart>(),
        _executeJson = library
            .lookup<NativeFunction<_RustExecuteJsonNative>>('rust_execute_json')
            .asFunction<_RustExecuteJsonDart>(),
        _encodeRgbaBuffer = library
            .lookup<NativeFunction<_RustEncodeRgbaNative>>(
              'rust_encode_rgba_buffer',
            )
            .asFunction<_RustEncodeRgbaDart>();

  static LocalConvertRustBridge? _instance;

  final _RustAllocBufferDart _allocBuffer;
  final _RustFreeBufferDart _freeBuffer;
  final _RustExecuteJsonDart _executeJson;
  final _RustEncodeRgbaDart _encodeRgbaBuffer;

  static String get _libraryFileName {
    if (Platform.isWindows) return 'local_convert_core.dll';
    if (Platform.isMacOS) return 'liblocal_convert_core.dylib';
    return 'liblocal_convert_core.so';
  }

  /// Resuelve la ruta en disco de la librería compartida nativa según el entorno
  /// (ejecutable Release/Debug empaquetado, `flutter run` o `flutter test`).
  static String? resolveLibraryPath() {
    final fileName = _libraryFileName;
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    final candidates = <String>[
      p.join(exeDir, fileName),
      p.join(Directory.current.path, 'rust', 'target', 'release', fileName),
      p.join(Directory.current.path, 'rust', 'target', 'debug', fileName),
      p.join(
        Directory.current.path,
        'build',
        'windows',
        'x64',
        'runner',
        'Release',
        fileName,
      ),
      p.join(
        Directory.current.path,
        'build',
        'windows',
        'x64',
        'runner',
        'Debug',
        fileName,
      ),
    ];

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    Directory cursor = Directory.current;
    for (int i = 0; i < 4; i++) {
      final probe = p.join(cursor.path, 'rust', 'target', 'release', fileName);
      if (File(probe).existsSync()) {
        return probe;
      }
      final parent = cursor.parent;
      if (parent.path == cursor.path) break;
      cursor = parent;
    }

    return null;
  }

  static LocalConvertRustBridge get instance {
    final cached = _instance;
    if (cached != null) return cached;

    final resolved = resolveLibraryPath();
    final DynamicLibrary lib;
    if (resolved != null) {
      lib = DynamicLibrary.open(resolved);
    } else {
      try {
        lib = DynamicLibrary.open(_libraryFileName);
      } catch (e) {
        throw StateError(
          'No se encontró la librería nativa de Rust ($_libraryFileName). '
          'Compila el crate con `cargo build --release` en `rust/` ($e).',
        );
      }
    }

    final bridge = LocalConvertRustBridge._(lib);
    _instance = bridge;
    return bridge;
  }

  static bool get isAvailable {
    try {
      instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Invoca una operación estructurada en Rust mediante JSON UTF-8 sobre FFI.
  static Map<String, dynamic> invokeJsonSync(Map<String, dynamic> payload) {
    final bridge = instance;
    final reqBytes = utf8.encode(jsonEncode(payload));
    if (reqBytes.isEmpty) {
      throw ArgumentError('La petición JSON a Rust no puede estar vacía.');
    }

    final reqPtr = bridge._allocBuffer(reqBytes.length);
    final outLenBytePtr = bridge._allocBuffer(sizeOf<UintPtr>());
    Pointer<Uint8> respPtr = nullptr;
    int respLen = 0;

    try {
      if (reqPtr == nullptr || outLenBytePtr == nullptr) {
        throw StateError('Sin memoria al reservar buffers FFI de petición.');
      }

      reqPtr.asTypedList(reqBytes.length).setAll(0, reqBytes);
      final outLenPtr = outLenBytePtr.cast<UintPtr>();
      outLenPtr.value = 0;

      respPtr = bridge._executeJson(reqPtr, reqBytes.length, outLenPtr);
      respLen = outLenPtr.value;

      if (respPtr == nullptr || respLen == 0) {
        throw StateError('El motor nativo de Rust devolvió una respuesta vacía.');
      }

      final respCopy = Uint8List.fromList(respPtr.asTypedList(respLen));
      final decoded = jsonDecode(utf8.decode(respCopy)) as Map<String, dynamic>;

      if (decoded['ok'] != true) {
        throw Exception(
          decoded['error']?.toString() ??
              'Error desconocido en el motor nativo de Rust.',
        );
      }

      final data = decoded['data'];
      if (data is Map<String, dynamic>) {
        return data;
      }
      return const <String, dynamic>{};
    } finally {
      if (respPtr != nullptr && respLen > 0) {
        bridge._freeBuffer(respPtr, respLen);
      }
      if (reqPtr != nullptr) {
        bridge._freeBuffer(reqPtr, reqBytes.length);
      }
      if (outLenBytePtr != nullptr) {
        bridge._freeBuffer(outLenBytePtr, sizeOf<UintPtr>());
      }
    }
  }

  /// Codifica en memoria un buffer RGBA crudo (4 bytes/px) mediante Rust FFI.
  static Uint8List encodeRgbaBufferSync({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
    required String format,
    required int quality,
  }) {
    final bridge = instance;
    final fmtBytes = utf8.encode(format);
    if (rgbaBytes.isEmpty || fmtBytes.isEmpty || width <= 0 || height <= 0) {
      throw ArgumentError(
        'Parámetros inválidos para codificación RGBA en Rust ($width x $height).',
      );
    }

    final rgbaPtr = bridge._allocBuffer(rgbaBytes.length);
    final fmtPtr = bridge._allocBuffer(fmtBytes.length);
    final outLenBytePtr = bridge._allocBuffer(sizeOf<UintPtr>());
    Pointer<Uint8> encodedPtr = nullptr;
    int encodedLen = 0;

    try {
      if (rgbaPtr == nullptr || fmtPtr == nullptr || outLenBytePtr == nullptr) {
        throw StateError('Sin memoria al reservar buffers RGBA FFI.');
      }

      rgbaPtr.asTypedList(rgbaBytes.length).setAll(0, rgbaBytes);
      fmtPtr.asTypedList(fmtBytes.length).setAll(0, fmtBytes);
      final outLenPtr = outLenBytePtr.cast<UintPtr>();
      outLenPtr.value = 0;

      encodedPtr = bridge._encodeRgbaBuffer(
        rgbaPtr,
        rgbaBytes.length,
        width,
        height,
        fmtPtr,
        fmtBytes.length,
        quality.clamp(1, 100),
        outLenPtr,
      );
      encodedLen = outLenPtr.value;

      if (encodedPtr == nullptr || encodedLen == 0) {
        throw StateError(
          'No se pudo codificar el buffer RGBA a "$format" desde Rust.',
        );
      }

      return Uint8List.fromList(encodedPtr.asTypedList(encodedLen));
    } finally {
      if (encodedPtr != nullptr && encodedLen > 0) {
        bridge._freeBuffer(encodedPtr, encodedLen);
      }
      if (rgbaPtr != nullptr) {
        bridge._freeBuffer(rgbaPtr, rgbaBytes.length);
      }
      if (fmtPtr != nullptr) {
        bridge._freeBuffer(fmtPtr, fmtBytes.length);
      }
      if (outLenBytePtr != nullptr) {
        bridge._freeBuffer(outLenBytePtr, sizeOf<UintPtr>());
      }
    }
  }
}
