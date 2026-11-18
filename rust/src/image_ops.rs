use std::fs;
use std::io::{Cursor, Write};
use std::path::Path;

use image::codecs::jpeg::JpegEncoder;
use image::imageops::FilterType;
use image::metadata::Orientation;
use image::{DynamicImage, GenericImageView, ImageDecoder, ImageFormat, ImageReader, RgbImage, Rgba, RgbaImage};
use rayon::prelude::*;
use serde::Serialize;
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipWriter};

#[derive(Debug, Serialize)]
pub struct BatchImagesResult {
    pub output_files: Vec<String>,
    pub zip_file_path: Option<String>,
    pub total_original_bytes: usize,
    pub total_compressed_bytes: usize,
}

#[derive(Debug, Serialize)]
pub struct EstimateImageResult {
    pub original_bytes: usize,
    pub estimated_bytes: usize,
    pub original_width: u32,
    pub original_height: u32,
    pub target_width: u32,
    pub target_height: u32,
}

/// Decodifica cualquier imagen soportada y aplica su rotación/espejado EXIF real.
pub fn decode_with_exif_orientation(bytes: &[u8]) -> Result<DynamicImage, String> {
    let reader = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|e| format!("Error leyendo cabecera de imagen: {}", e))?;

    let mut decoder = reader
        .into_decoder()
        .map_err(|e| format!("Formato de imagen corrupto o no soportado: {}", e))?;

    let orientation = decoder.orientation().unwrap_or(Orientation::NoTransforms);
    let mut img = DynamicImage::from_decoder(decoder)
        .map_err(|e| format!("Error decodificando píxeles de imagen: {}", e))?;
    img.apply_orientation(orientation);
    Ok(img)
}

/// Compone una imagen RGBA sobre lienzo blanco sólido (255, 255, 255).
pub fn flatten_rgba_on_white(rgba: &RgbaImage) -> RgbImage {
    let (w, h) = rgba.dimensions();
    let mut rgb = RgbImage::new(w, h);
    for (x, y, px) in rgba.enumerate_pixels() {
        let [r, g, b, a] = px.0;
        let out_px = if a == 255 {
            image::Rgb([r, g, b])
        } else if a == 0 {
            image::Rgb([255, 255, 255])
        } else {
            let alpha = a as u16;
            let inv = 255 - alpha;
            let nr = ((r as u16 * alpha + 255 * inv) / 255) as u8;
            let ng = ((g as u16 * alpha + 255 * inv) / 255) as u8;
            let nb = ((b as u16 * alpha + 255 * inv) / 255) as u8;
            image::Rgb([nr, ng, nb])
        };
        rgb.put_pixel(x, y, out_px);
    }
    rgb
}

pub fn image_has_meaningful_alpha(img: &DynamicImage) -> bool {
    if !img.color().has_alpha() {
        return false;
    }
    let rgba = img.to_rgba8();
    rgba.pixels().any(|p| p.0[3] < 255)
}

pub fn cap_max_dimension(img: DynamicImage, max_dimension_px: u32) -> DynamicImage {
    let safe_limit = max_dimension_px.clamp(1, 16383);
    let (w, h) = img.dimensions();
    if w <= safe_limit && h <= safe_limit {
        return img;
    }
    if w >= h {
        let new_h = (((h as u64 * safe_limit as u64) / w as u64).max(1)) as u32;
        img.resize_exact(safe_limit, new_h, FilterType::Lanczos3)
    } else {
        let new_w = (((w as u64 * safe_limit as u64) / h as u64).max(1)) as u32;
        img.resize_exact(new_w, safe_limit, FilterType::Lanczos3)
    }
}

/// Codifica un `DynamicImage` al formato destino solicitado (`png`, `jpg`, `webp`,
/// `bmp`, `tiff`, `ico`, `gif`, `tga`).
pub fn encode_dynamic_image(
    img: &DynamicImage,
    format: &str,
    quality: u8,
) -> Result<Vec<u8>, String> {
    let q = quality.clamp(1, 100);
    let fmt = format.trim().to_ascii_lowercase();
    let mut buf: Vec<u8> = Vec::new();

    match fmt.as_str() {
        "png" => {
            img.write_to(&mut Cursor::new(&mut buf), ImageFormat::Png)
                .map_err(|e| format!("Error codificando PNG: {}", e))?;
        }
        "jpg" | "jpeg" => {
            let rgb = if img.color().has_alpha() {
                flatten_rgba_on_white(&img.to_rgba8())
            } else {
                img.to_rgb8()
            };
            let encoder = JpegEncoder::new_with_quality(&mut buf, q);
            rgb.write_with_encoder(encoder)
                .map_err(|e| format!("Error codificando JPEG: {}", e))?;
        }
        "webp" => {
            let rgba = img.to_rgba8();
            DynamicImage::ImageRgba8(rgba)
                .write_to(&mut Cursor::new(&mut buf), ImageFormat::WebP)
                .map_err(|e| format!("Error codificando WEBP: {}", e))?;
        }
        "bmp" => {
            let rgba_or_rgb = if img.color().has_alpha() {
                DynamicImage::ImageRgba8(img.to_rgba8())
            } else {
                DynamicImage::ImageRgb8(img.to_rgb8())
            };
            rgba_or_rgb
                .write_to(&mut Cursor::new(&mut buf), ImageFormat::Bmp)
                .map_err(|e| format!("Error codificando BMP: {}", e))?;
        }
        "tiff" | "tif" => {
            let rgba_or_rgb = if img.color().has_alpha() {
                DynamicImage::ImageRgba8(img.to_rgba8())
            } else {
                DynamicImage::ImageRgb8(img.to_rgb8())
            };
            rgba_or_rgb
                .write_to(&mut Cursor::new(&mut buf), ImageFormat::Tiff)
                .map_err(|e| format!("Error codificando TIFF: {}", e))?;
        }
        "ico" => {
            let (w, h) = img.dimensions();
            let ico_img = if w > 256 || h > 256 {
                cap_max_dimension(img.clone(), 256)
            } else {
                img.clone()
            };
            let rgba = DynamicImage::ImageRgba8(ico_img.to_rgba8());
            rgba.write_to(&mut Cursor::new(&mut buf), ImageFormat::Ico)
                .map_err(|e| format!("Error codificando ICO: {}", e))?;
        }
        "gif" => {
            let rgba = DynamicImage::ImageRgba8(img.to_rgba8());
            rgba.write_to(&mut Cursor::new(&mut buf), ImageFormat::Gif)
                .map_err(|e| format!("Error codificando GIF: {}", e))?;
        }
        "tga" => {
            let rgba_or_rgb = if img.color().has_alpha() {
                DynamicImage::ImageRgba8(img.to_rgba8())
            } else {
                DynamicImage::ImageRgb8(img.to_rgb8())
            };
            rgba_or_rgb
                .write_to(&mut Cursor::new(&mut buf), ImageFormat::Tga)
                .map_err(|e| format!("Error codificando TGA: {}", e))?;
        }
        other => {
            return Err(format!("Formato de imagen no soportado: {}", other));
        }
    }

    Ok(buf)
}

/// Codifica un buffer RGBA crudo (4 bytes por píxel) al formato destino en memoria.
pub fn encode_rgba_buffer(
    rgba_bytes: &[u8],
    width: u32,
    height: u32,
    format: &str,
    quality: u8,
) -> Result<Vec<u8>, String> {
    let expected_len = (width as usize)
        .checked_mul(height as usize)
        .and_then(|v| v.checked_mul(4))
        .ok_or_else(|| "Dimensiones de buffer RGBA desbordadas.".to_string())?;

    if rgba_bytes.len() < expected_len {
        return Err(format!(
            "Buffer RGBA insuficiente: esperados {} bytes, recibidos {}.",
            expected_len,
            rgba_bytes.len()
        ));
    }

    let img_buf = RgbaImage::from_raw(width, height, rgba_bytes[..expected_len].to_vec())
        .ok_or_else(|| "No se pudo construir RgbaImage desde el buffer.".to_string())?;
    let dyn_img = DynamicImage::ImageRgba8(img_buf);
    encode_dynamic_image(&dyn_img, format, quality)
}

/// Convierte un lote de imágenes en paralelo mediante `rayon::par_iter`.
pub fn convert_image_batch(
    input_paths: &[String],
    session_dir_path: &str,
    target_format: &str,
    quality: u8,
    max_dimension_px: u32,
    package_as_zip: bool,
) -> Result<BatchImagesResult, String> {
    if input_paths.is_empty() {
        return Err("No se seleccionaron imágenes para convertir.".to_string());
    }

    fs::create_dir_all(session_dir_path)
        .map_err(|e| format!("No se pudo crear el directorio de sesión: {}", e))?;

    let ext_lower = target_format.trim().to_ascii_lowercase();
    let results: Result<Vec<(String, usize, usize)>, String> = input_paths
        .par_iter()
        .enumerate()
        .map(|(i, input_path)| {
            let raw_bytes = fs::read(input_path)
                .map_err(|e| format!("No se pudo leer '{}': {}", input_path, e))?;
            let orig_len = raw_bytes.len();
            let decoded = decode_with_exif_orientation(&raw_bytes)?;
            let bounded = cap_max_dimension(decoded, max_dimension_px);
            let encoded = encode_dynamic_image(&bounded, &ext_lower, quality)?;
            let comp_len = encoded.len();

            let stem = Path::new(input_path)
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("imagen");
            let out_name = format!("{}_{}.{}", stem, i + 1, ext_lower);
            let out_path = Path::new(session_dir_path).join(out_name);
            fs::write(&out_path, &encoded)
                .map_err(|e| format!("Error al escribir '{}': {}", out_path.display(), e))?;

            Ok((out_path.to_string_lossy().into_owned(), orig_len, comp_len))
        })
        .collect();

    let items = results?;
    let mut output_files = Vec::with_capacity(items.len());
    let mut total_orig = 0usize;
    let mut total_comp = 0usize;
    for (path, o_len, c_len) in items {
        output_files.push(path);
        total_orig += o_len;
        total_comp += c_len;
    }

    let zip_file_path = if package_as_zip || output_files.len() > 1 {
        let ext_upper = ext_lower.to_ascii_uppercase();
        let zip_path = Path::new(session_dir_path).join(format!("LocalConvert_{}_Lote.zip", ext_upper));
        let zip_str = zip_path.to_string_lossy().into_owned();
        create_zip_archive(&output_files, &zip_str)?;
        Some(zip_str)
    } else {
        None
    };

    Ok(BatchImagesResult {
        output_files,
        zip_file_path,
        total_original_bytes: total_orig,
        total_compressed_bytes: total_comp,
    })
}

fn apply_resize_mode(
    source: DynamicImage,
    resize_mode: &str,
    scale_percent: u32,
    target_width_px: Option<u32>,
    target_height_px: Option<u32>,
    maintain_aspect_ratio: bool,
    max_dimension_px: u32,
) -> DynamicImage {
    let safe_limit = max_dimension_px.clamp(1, 16383);
    let (src_w, src_h) = source.dimensions();

    let resized = if resize_mode == "percentage" {
        let clamped = scale_percent.clamp(10, 100);
        if clamped == 100 {
            source
        } else {
            let new_w = (((src_w as f64 * clamped as f64) / 100.0).round() as u32).clamp(1, safe_limit);
            let new_h = (((src_h as f64 * clamped as f64) / 100.0).round() as u32).clamp(1, safe_limit);
            source.resize_exact(new_w, new_h, FilterType::Lanczos3)
        }
    } else {
        let w = target_width_px.filter(|&v| v > 0).map(|v| v.clamp(1, safe_limit));
        let h = target_height_px.filter(|&v| v > 0).map(|v| v.clamp(1, safe_limit));

        match (w, h) {
            (None, None) => source,
            _ if maintain_aspect_ratio => {
                if let Some(tw) = w {
                    let th = (((src_h as f64 * tw as f64) / src_w.max(1) as f64).round() as u32).clamp(1, safe_limit);
                    source.resize_exact(tw, th, FilterType::Lanczos3)
                } else if let Some(th) = h {
                    let tw = (((src_w as f64 * th as f64) / src_h.max(1) as f64).round() as u32).clamp(1, safe_limit);
                    source.resize_exact(tw, th, FilterType::Lanczos3)
                } else {
                    source
                }
            }
            (tw, th) => source.resize_exact(
                tw.unwrap_or(src_w).clamp(1, safe_limit),
                th.unwrap_or(src_h).clamp(1, safe_limit),
                FilterType::Lanczos3,
            ),
        }
    };

    cap_max_dimension(resized, safe_limit)
}

fn encode_compressed_with_ext(
    img: &DynamicImage,
    source_ext: &str,
    quality: u8,
) -> Result<(Vec<u8>, &'static str), String> {
    let q = quality.clamp(1, 100);
    let ext = source_ext.trim().to_ascii_lowercase();

    if ext == ".webp" || ext == "webp" {
        let bytes = encode_dynamic_image(img, "webp", q)?;
        return Ok((bytes, ".webp"));
    }

    if ext == ".png" || ext == "png" {
        let has_alpha = image_has_meaningful_alpha(img);
        if !has_alpha && q < 95 {
            let bytes = encode_dynamic_image(img, "jpg", q)?;
            return Ok((bytes, ".jpg"));
        }

        if q < 95 {
            // Cuantización rápida por bits de color para reducir entropía PNG cuando q < 95
            let step = (((100 - q) as u32) / 14).clamp(1, 5);
            let mask = !((1u8 << step) - 1);
            let mut rgba = img.to_rgba8();
            for px in rgba.pixels_mut() {
                px.0[0] &= mask;
                px.0[1] &= mask;
                px.0[2] &= mask;
                px.0[3] = ((px.0[3] & mask).max(if px.0[3] > 0 { 1 } else { 0 })).min(255);
            }
            let bytes = encode_dynamic_image(&DynamicImage::ImageRgba8(rgba), "png", q)?;
            return Ok((bytes, ".png"));
        }

        let bytes = encode_dynamic_image(img, "png", q)?;
        return Ok((bytes, ".png"));
    }

    let bytes = encode_dynamic_image(img, "jpg", q)?;
    Ok((bytes, ".jpg"))
}

pub fn estimate_single_image(
    file_path: &str,
    resize_mode: &str,
    scale_percent: u32,
    target_width_px: Option<u32>,
    target_height_px: Option<u32>,
    maintain_aspect_ratio: bool,
    quality: u8,
    max_dimension_px: u32,
) -> Result<EstimateImageResult, String> {
    let raw_bytes = fs::read(file_path)
        .map_err(|e| format!("No se pudo leer '{}': {}", file_path, e))?;
    let orig_len = raw_bytes.len();
    let oriented = decode_with_exif_orientation(&raw_bytes)?;
    let (orig_w, orig_h) = oriented.dimensions();

    let resized = apply_resize_mode(
        oriented,
        resize_mode,
        scale_percent,
        target_width_px,
        target_height_px,
        maintain_aspect_ratio,
        max_dimension_px,
    );
    let (target_w, target_h) = resized.dimensions();

    let ext = Path::new(file_path)
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("jpg");
    let (encoded, _) = encode_compressed_with_ext(&resized, ext, quality)?;

    Ok(EstimateImageResult {
        original_bytes: orig_len,
        estimated_bytes: encoded.len(),
        original_width: orig_w,
        original_height: orig_h,
        target_width: target_w,
        target_height: target_h,
    })
}

pub fn compress_resize_batch(
    input_paths: &[String],
    session_dir_path: &str,
    resize_mode: &str,
    scale_percent: u32,
    target_width_px: Option<u32>,
    target_height_px: Option<u32>,
    maintain_aspect_ratio: bool,
    quality: u8,
    max_dimension_px: u32,
) -> Result<BatchImagesResult, String> {
    if input_paths.is_empty() {
        return Err("No se seleccionaron imágenes para comprimir.".to_string());
    }

    fs::create_dir_all(session_dir_path)
        .map_err(|e| format!("No se pudo crear la sesión '{}': {}", session_dir_path, e))?;

    let results: Result<Vec<(String, usize, usize)>, String> = input_paths
        .par_iter()
        .map(|input_path| {
            let raw_bytes = fs::read(input_path)
                .map_err(|e| format!("No se pudo leer '{}': {}", input_path, e))?;
            let orig_len = raw_bytes.len();
            let oriented = decode_with_exif_orientation(&raw_bytes)?;
            let resized = apply_resize_mode(
                oriented,
                resize_mode,
                scale_percent,
                target_width_px,
                target_height_px,
                maintain_aspect_ratio,
                max_dimension_px,
            );

            let src_ext = Path::new(input_path)
                .extension()
                .and_then(|s| s.to_str())
                .unwrap_or("jpg");
            let (encoded, out_ext) = encode_compressed_with_ext(&resized, src_ext, quality)?;
            let comp_len = encoded.len();

            let stem = Path::new(input_path)
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("imagen");
            let out_name = format!("{}_opt{}", stem, out_ext);
            let out_path = Path::new(session_dir_path).join(out_name);
            fs::write(&out_path, &encoded)
                .map_err(|e| format!("Error al escribir '{}': {}", out_path.display(), e))?;

            Ok((out_path.to_string_lossy().into_owned(), orig_len, comp_len))
        })
        .collect();

    let items = results?;
    let mut output_files = Vec::with_capacity(items.len());
    let mut total_orig = 0usize;
    let mut total_comp = 0usize;
    for (path, o_len, c_len) in items {
        output_files.push(path);
        total_orig += o_len;
        total_comp += c_len;
    }

    let zip_file_path = if output_files.len() > 1 {
        let zip_path = Path::new(session_dir_path).join("LocalConvert_Comprimidas.zip");
        let zip_str = zip_path.to_string_lossy().into_owned();
        create_zip_archive(&output_files, &zip_str)?;
        Some(zip_str)
    } else {
        None
    };

    Ok(BatchImagesResult {
        output_files,
        zip_file_path,
        total_original_bytes: total_orig,
        total_compressed_bytes: total_comp,
    })
}

/// Empaqueta una lista de archivos en disco dentro de un archivo `.ZIP` comprimido.
pub fn create_zip_archive(input_paths: &[String], output_zip_path: &str) -> Result<String, String> {
    if let Some(parent) = Path::new(output_zip_path).parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("No se pudo crear directorio de ZIP: {}", e))?;
    }

    let zip_file = fs::File::create(output_zip_path)
        .map_err(|e| format!("No se pudo crear el ZIP '{}': {}", output_zip_path, e))?;
    let mut zip = ZipWriter::new(zip_file);
    let options = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);

    for path in input_paths {
        let p = Path::new(path);
        if !p.exists() {
            continue;
        }
        let bytes = fs::read(p)
            .map_err(|e| format!("Error leyendo '{}' para ZIP: {}", path, e))?;
        let name = p
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("archivo.bin");
        zip.start_file(name, options)
            .map_err(|e| format!("Error iniciando entrada ZIP '{}': {}", name, e))?;
        zip.write_all(&bytes)
            .map_err(|e| format!("Error escribiendo '{}' en ZIP: {}", name, e))?;
    }

    zip.finish()
        .map_err(|e| format!("Error cerrando ZIP '{}': {}", output_zip_path, e))?;

    Ok(output_zip_path.to_string())
}

#[allow(dead_code)]
fn _keep_rgba_type(_: Rgba<u8>) {}
