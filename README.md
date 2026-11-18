# LocalConvert

Suite multiplataforma 100% offline y privada para conversión y manipulación local de PDFs, imágenes y documentos en Escritorio (Windows, macOS, Linux) y Móvil (Android, iOS).

## Privacidad y Arquitectura
- **Zero-Network:** Sin llamadas a APIs externas ni permisos de internet en `android/app/src/main/AndroidManifest.xml` o `macos/Runner/Release.entitlements`.
- **Sandbox Local:** Todo archivo temporal se genera en sesiones efímeras dentro de `TemporaryDirectory/local_convert_sandbox` y se destruye al exportar, cancelar o iniciar la aplicación (`SandboxCleanerService`).
- **Aislamiento de Hilos:** El procesamiento pesado de imágenes, PDFs, archivos ZIP y compilación de Markdown ocurre dentro de `Isolate`s dedicados.
- **Guardas de Memoria (`MemoryGuardConfig`):** Límites diferenciados de resolución y decodificación de miniaturas entre móvil y escritorio.

## Módulos Incluidos
1. **PDF:** Imágenes a PDF (con reordenamiento Drag & Drop, tamaño, orientación, márgenes y calidad), PDF a Imágenes (PNG/JPG/ZIP), Unir PDFs y Dividir PDF (rangos tipo `1-3, 5, 8-10` o selección visual).
2. **Imágenes:** Conversión bidireccional por lotes (`PNG`, `JPG`, `WEBP`, `BMP`) y Compresor/Redimensionador con estimación de peso final en tiempo real.
3. **Documentos:** Conversión de `.txt` y `.md` (Markdown AST) a PDF con fuentes Roboto y RobotoMono embebidas localmente (soporte Unicode completo).

## Comandos Útiles
```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```
