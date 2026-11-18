# Binarios portables de FFmpeg para Windows (`windows/bin/`)

Para empaquetar **FFmpeg** de manera 100% portable junto a `local_convert.exe` sin depender del `PATH` del sistema operativo:

1. Descarga o compila `ffmpeg.exe` y (opcionalmente) `ffprobe.exe` para Windows x64.
2. Coloca ambos archivos dentro de esta carpeta (`windows/bin/ffmpeg.exe` y `windows/bin/ffprobe.exe`).
3. Ejecuta `flutter build windows --release`.

El archivo `windows/CMakeLists.txt` detectará automáticamente su presencia en `windows/bin/` y los copiará junto a `local_convert.exe` dentro de `build/windows/x64/runner/Release/`.

En tiempo de ejecución, `DesktopFfmpegEngine` (`lib/core/media/media_processing_engine.dart`) buscará `ffmpeg.exe` en este orden:
1. Junto a `local_convert.exe` (carpeta del ejecutable Release).
2. En `<proyecto>/windows/bin/ffmpeg.exe`.
3. En el `PATH` global de Windows si existe en el equipo.
