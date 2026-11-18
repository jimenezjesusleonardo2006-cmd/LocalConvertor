use std::fs;
use std::io::{BufWriter, Cursor};
use std::path::Path;

use image::{ColorType, DynamicImage, ImageFormat, Rgb, RgbImage};
use printpdf::{
    Color, ColorBits, ColorSpace, Image, ImageTransform, ImageXObject, Mm, PdfDocument, Px,
    Rgb as PdfRgb,
};
use qrcode::render::svg;
use qrcode::{Color as QrColor, EcLevel, QrCode};
use rayon::prelude::*;
use serde::Serialize;

use crate::image_ops::create_zip_archive;
use crate::pdf_gen::{measure_text_mm, pt_to_mm};

#[derive(Debug, Serialize)]
pub struct QrPreviewResult {
    pub preview_path: String,
    pub module_count: usize,
    pub width_px: u32,
}

#[derive(Debug, Serialize)]
pub struct QrBatchResult {
    pub output_files: Vec<String>,
    pub zip_file_path: Option<String>,
    pub generated_count: usize,
}

fn parse_ec_level(level: &str) -> EcLevel {
    match level.trim().to_ascii_uppercase().as_str() {
        "L" => EcLevel::L,
        "Q" => EcLevel::Q,
        "H" => EcLevel::H,
        _ => EcLevel::M,
    }
}

fn render_qr_rgb_image(content: &str, ec_level: &str, target_px: u32) -> Result<(RgbImage, usize), String> {
    let ec = parse_ec_level(ec_level);
    let code = QrCode::with_error_correction_level(content.as_bytes(), ec)
        .map_err(|e| format!("No se pudo codificar el contenido QR: {}", e))?;

    let modules = code.width();
    let quiet = 3usize;
    let total_modules = modules + quiet * 2;
    let size = target_px.clamp(128, 2048);
    let cell_px = (size as usize / total_modules).max(2);
    let actual_size = (total_modules * cell_px) as u32;

    let mut img = RgbImage::from_pixel(actual_size, actual_size, Rgb([255, 255, 255]));
    let dark = Rgb([15, 23, 42]);

    for my in 0..modules {
        for mx in 0..modules {
            if code[(mx, my)] == QrColor::Dark {
                let px0 = ((mx + quiet) * cell_px) as u32;
                let py0 = ((my + quiet) * cell_px) as u32;
                for dy in 0..(cell_px as u32) {
                    for dx in 0..(cell_px as u32) {
                        img.put_pixel(px0 + dx, py0 + dy, dark);
                    }
                }
            }
        }
    }

    Ok((img, modules))
}

fn render_qr_svg(content: &str, ec_level: &str, target_px: u32) -> Result<String, String> {
    let ec = parse_ec_level(ec_level);
    let code = QrCode::with_error_correction_level(content.as_bytes(), ec)
        .map_err(|e| format!("No se pudo generar SVG QR: {}", e))?;
    let svg_str = code
        .render::<svg::Color>()
        .min_dimensions(target_px.clamp(128, 2048), target_px.clamp(128, 2048))
        .dark_color(svg::Color("#0F172A"))
        .light_color(svg::Color("#FFFFFF"))
        .build();
    Ok(svg_str)
}

fn sanitize_slug(input: &str, idx: usize) -> String {
    let clean: String = input
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_')
        .take(24)
        .collect();
    if clean.is_empty() {
        format!("qr_{:03}", idx + 1)
    } else {
        format!("qr_{:03}_{}", idx + 1, clean)
    }
}

pub fn generate_qr_preview(
    content: &str,
    ec_level: &str,
    size_px: u32,
    output_path: &str,
) -> Result<QrPreviewResult, String> {
    let trimmed = content.trim();
    if trimmed.is_empty() {
        return Err("El contenido del código QR no puede estar vacío.".to_string());
    }

    let (rgb_img, modules) = render_qr_rgb_image(trimmed, ec_level, size_px)?;
    let width_px = rgb_img.width();

    if let Some(parent) = Path::new(output_path).parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Error creando carpeta de preview QR: {}", e))?;
    }

    let mut png_bytes = Vec::new();
    DynamicImage::ImageRgb8(rgb_img)
        .write_to(&mut Cursor::new(&mut png_bytes), ImageFormat::Png)
        .map_err(|e| format!("Error codificando preview PNG QR: {}", e))?;

    fs::write(output_path, &png_bytes)
        .map_err(|e| format!("Error escribiendo preview QR '{}': {}", output_path, e))?;

    Ok(QrPreviewResult {
        preview_path: output_path.to_string(),
        module_count: modules,
        width_px,
    })
}

fn render_qr_sheet_pdf(
    entries: &[(String, RgbImage)],
    output_pdf_path: &str,
    regular_font_path: &str,
    bold_font_path: &str,
) -> Result<(), String> {
    let regular_bytes = fs::read(regular_font_path)
        .map_err(|e| format!("No se pudo leer fuente '{}': {}", regular_font_path, e))?;
    let bold_bytes = fs::read(bold_font_path).unwrap_or_else(|_| regular_bytes.clone());

    let page_w = 210.0f32;
    let page_h = 297.0f32;
    let margin_x = 14.0f32;
    let margin_top = 16.0f32;
    let cols = 3usize;
    let rows_per_page = 4usize;
    let per_page = cols * rows_per_page;

    let cell_w = (page_w - margin_x * 2.0) / (cols as f32);
    let cell_h = (page_h - margin_top - 16.0 - 10.0) / (rows_per_page as f32);
    let qr_draw_mm = cell_w.min(cell_h - 11.0).min(46.0);

    let (doc, page1, layer1) =
        PdfDocument::new("LocalConvert Códigos QR", Mm(page_w), Mm(page_h), "Layer 1");
    let doc = doc
        .with_producer("LocalConvert Rust QR Studio")
        .with_creator("LocalConvert");

    let reg_ref = doc
        .add_external_font(Cursor::new(regular_bytes.clone()))
        .map_err(|e| format!("Error fuente Regular TTF: {:?}", e))?;
    let bold_ref = doc
        .add_external_font(Cursor::new(bold_bytes))
        .map_err(|e| format!("Error fuente Bold TTF: {:?}", e))?;

    let total_pages = (entries.len() + per_page - 1) / per_page;
    let mut page_refs = Vec::with_capacity(total_pages);

    for page_num in 0..total_pages {
        let (p_idx, l_idx) = if page_num == 0 {
            (page1, layer1)
        } else {
            doc.add_page(Mm(page_w), Mm(page_h), "Layer 1")
        };
        page_refs.push((p_idx, l_idx));
        let layer = doc.get_page(p_idx).get_layer(l_idx);

        layer.set_fill_color(Color::Rgb(PdfRgb::new(0.06, 0.09, 0.16, None)));
        layer.use_text(
            "Lámina de Códigos QR — LocalConvert",
            12.0,
            Mm(margin_x),
            Mm(page_h - 11.0),
            &bold_ref,
        );

        let start = page_num * per_page;
        let end = (start + per_page).min(entries.len());

        for (slot, (label_raw, rgb_img)) in entries[start..end].iter().enumerate() {
            let col = slot % cols;
            let row = slot / cols;
            let x0 = margin_x + (col as f32) * cell_w;
            let y_top = page_h - margin_top - 4.0 - (row as f32) * cell_h;

            let qr_x = x0 + (cell_w - qr_draw_mm) / 2.0;
            let qr_y = y_top - qr_draw_mm - 2.0;

            let (w, h) = rgb_img.dimensions();
            let base_w_mm = pt_to_mm(w as f32).max(0.1);
            let scale = qr_draw_mm / base_w_mm;

            let xobj = ImageXObject {
                width: Px(w as usize),
                height: Px(h as usize),
                color_space: ColorSpace::Rgb,
                bits_per_component: ColorBits::Bit8,
                interpolate: false,
                image_data: rgb_img.as_raw().clone(),
                image_filter: None,
                smask: None,
                clipping_bbox: None,
            };
            let pdf_img = Image::from(xobj);
            pdf_img.add_to_layer(
                layer.clone(),
                ImageTransform {
                    translate_x: Some(Mm(qr_x)),
                    translate_y: Some(Mm(qr_y)),
                    rotate: None,
                    scale_x: Some(scale),
                    scale_y: Some(scale),
                    dpi: Some(72.0),
                },
            );

            let mut label: String = label_raw.chars().take(28).collect();
            if label_raw.chars().count() > 28 {
                label.push_str("...");
            }
            let lw = measure_text_mm(&regular_bytes, &label, 7.8);
            let lx = x0 + ((cell_w - lw) / 2.0).max(2.0);
            let ly = qr_y - 4.5;
            layer.set_fill_color(Color::Rgb(PdfRgb::new(0.20, 0.24, 0.30, None)));
            layer.use_text(label, 7.8, Mm(lx), Mm(ly), &reg_ref);
        }

        let footer = format!("Página {} de {}", page_num + 1, total_pages);
        let fw = measure_text_mm(&regular_bytes, &footer, 8.5);
        layer.set_fill_color(Color::Rgb(PdfRgb::new(0.45, 0.49, 0.56, None)));
        layer.use_text(
            footer,
            8.5,
            Mm((page_w - margin_x - fw).max(margin_x)),
            Mm(6.0),
            &reg_ref,
        );
    }

    if let Some(parent) = Path::new(output_pdf_path).parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Error creando carpeta de lámina PDF QR: {}", e))?;
    }
    let out_file = fs::File::create(output_pdf_path)
        .map_err(|e| format!("Error creando '{}': {}", output_pdf_path, e))?;
    let mut writer = BufWriter::new(out_file);
    doc.save(&mut writer)
        .map_err(|e| format!("Error guardando lámina PDF QR: {:?}", e))?;
    Ok(())
}

#[allow(clippy::too_many_arguments)]
pub fn generate_qr_batch(
    items: &[String],
    session_dir_path: &str,
    output_format: &str,
    ec_level: &str,
    size_px: u32,
    package_as_zip: bool,
    regular_font_path: &str,
    bold_font_path: &str,
) -> Result<QrBatchResult, String> {
    let cleaned: Vec<String> = items
        .iter()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    if cleaned.is_empty() {
        return Err("Ingresa al menos un texto, URL o línea para generar códigos QR.".to_string());
    }

    fs::create_dir_all(session_dir_path)
        .map_err(|e| format!("No se pudo crear sesión QR '{}': {}", session_dir_path, e))?;

    let fmt = output_format.trim().to_ascii_lowercase();
    if fmt == "pdf" {
        let generated: Result<Vec<(String, RgbImage)>, String> = cleaned
            .par_iter()
            .map(|text| {
                let (img, _) = render_qr_rgb_image(text, ec_level, size_px.min(512))?;
                Ok((text.clone(), img))
            })
            .collect();
        let pairs = generated?;
        let pdf_path = Path::new(session_dir_path)
            .join("LocalConvert_QR_Lamina.pdf")
            .to_string_lossy()
            .into_owned();
        render_qr_sheet_pdf(&pairs, &pdf_path, regular_font_path, bold_font_path)?;
        return Ok(QrBatchResult {
            generated_count: pairs.len(),
            output_files: vec![pdf_path],
            zip_file_path: None,
        });
    }

    let generated_files: Result<Vec<String>, String> = cleaned
        .par_iter()
        .enumerate()
        .map(|(idx, text)| {
            let slug = sanitize_slug(text, idx);
            if fmt == "svg" {
                let svg_str = render_qr_svg(text, ec_level, size_px)?;
                let out_path = Path::new(session_dir_path).join(format!("{}.svg", slug));
                fs::write(&out_path, svg_str.as_bytes())
                    .map_err(|e| format!("Error escribiendo '{}': {}", out_path.display(), e))?;
                Ok(out_path.to_string_lossy().into_owned())
            } else {
                let (rgb_img, _) = render_qr_rgb_image(text, ec_level, size_px)?;
                let mut png_bytes = Vec::new();
                DynamicImage::ImageRgb8(rgb_img)
                    .write_to(&mut Cursor::new(&mut png_bytes), ImageFormat::Png)
                    .map_err(|e| format!("Error codificando PNG QR: {}", e))?;
                let out_path = Path::new(session_dir_path).join(format!("{}.png", slug));
                fs::write(&out_path, &png_bytes)
                    .map_err(|e| format!("Error escribiendo '{}': {}", out_path.display(), e))?;
                Ok(out_path.to_string_lossy().into_owned())
            }
        })
        .collect();

    let output_files = generated_files?;
    let zip_file_path = if package_as_zip || output_files.len() > 1 {
        let zip_path = Path::new(session_dir_path)
            .join("LocalConvert_QR_Lote.zip")
            .to_string_lossy()
            .into_owned();
        create_zip_archive(&output_files, &zip_path)?;
        Some(zip_path)
    } else {
        None
    };

    let _unused: ColorType = ColorType::Rgb8;
    Ok(QrBatchResult {
        generated_count: output_files.len(),
        output_files,
        zip_file_path,
    })
}
