use std::fs;
use std::io::{BufWriter, Cursor};
use std::path::Path;

use image::codecs::jpeg::JpegEncoder;
use image::GenericImageView;
use lopdf::Object;
use printpdf::path::{PaintMode, WindingOrder};
use printpdf::{
    Color, ColorBits, ColorSpace, Image, ImageFilter, ImageTransform, ImageXObject, IndirectFontRef,
    Mm, PdfDocument, Polygon, Px, Rgb,
};
use rayon::prelude::*;
use ttf_parser::Face;

use crate::image_ops::{cap_max_dimension, decode_with_exif_orientation, flatten_rgba_on_white};

const PT_TO_MM: f32 = 25.4 / 72.0;

#[inline]
pub(crate) fn pt_to_mm(pt: f32) -> f32 {
    pt * PT_TO_MM
}

struct PreparedPdfImage {
    width: u32,
    height: u32,
    jpeg_bytes: Vec<u8>,
}

/// Convierte un lote de imágenes en un documento PDF multipágina usando `image` + `rayon` + `printpdf`.
pub fn images_to_pdf(
    image_paths: &[String],
    output_file_path: &str,
    page_size: &str,
    orientation: &str,
    margin_points: f32,
    jpeg_quality: u8,
    max_dimension_px: u32,
) -> Result<usize, String> {
    if image_paths.is_empty() {
        return Err("No se seleccionaron imágenes para convertir.".to_string());
    }

    let prepared: Result<Vec<PreparedPdfImage>, String> = image_paths
        .par_iter()
        .map(|path| {
            let raw = fs::read(path)
                .map_err(|e| format!("No se pudo leer la imagen '{}': {}", path, e))?;
            let oriented = decode_with_exif_orientation(&raw)?;
            let bounded = cap_max_dimension(oriented, max_dimension_px);
            let (w, h) = bounded.dimensions();

            let rgb = if bounded.color().has_alpha() {
                flatten_rgba_on_white(&bounded.to_rgba8())
            } else {
                bounded.to_rgb8()
            };

            let mut jpeg_bytes = Vec::new();
            let enc = JpegEncoder::new_with_quality(&mut jpeg_bytes, jpeg_quality.clamp(1, 100));
            rgb.write_with_encoder(enc)
                .map_err(|e| format!("Error comprimiendo JPEG de '{}': {}", path, e))?;

            Ok(PreparedPdfImage {
                width: w,
                height: h,
                jpeg_bytes,
            })
        })
        .collect();

    let items = prepared?;
    let margin_mm = pt_to_mm(margin_points.max(0.0));

    let resolve_page_dims_mm = |img_w: u32, img_h: u32| -> (f32, f32) {
        match page_size {
            "fitToImage" => (
                pt_to_mm(img_w as f32) + margin_mm * 2.0,
                pt_to_mm(img_h as f32) + margin_mm * 2.0,
            ),
            "letter" => {
                if orientation == "landscape" {
                    (279.4, 215.9)
                } else {
                    (215.9, 279.4)
                }
            }
            _ => {
                if orientation == "landscape" {
                    (297.0, 210.0)
                } else {
                    (210.0, 297.0)
                }
            }
        }
    };

    let (first_w_mm, first_h_mm) = resolve_page_dims_mm(items[0].width, items[0].height);
    let (doc, first_page, first_layer) = PdfDocument::new(
        "LocalConvert Document",
        Mm(first_w_mm),
        Mm(first_h_mm),
        "Layer 1",
    );
    let doc = doc
        .with_producer("LocalConvert Native Rust Engine")
        .with_creator("LocalConvert");

    for (idx, item) in items.into_iter().enumerate() {
        let (page_w_mm, page_h_mm) = resolve_page_dims_mm(item.width, item.height);
        let (page_idx, layer_idx) = if idx == 0 {
            (first_page, first_layer)
        } else {
            doc.add_page(Mm(page_w_mm), Mm(page_h_mm), "Layer 1")
        };

        let layer = doc.get_page(page_idx).get_layer(layer_idx);
        let avail_w_mm = (page_w_mm - margin_mm * 2.0).max(1.0);
        let avail_h_mm = (page_h_mm - margin_mm * 2.0).max(1.0);

        let img_base_w_mm = pt_to_mm(item.width as f32).max(0.1);
        let img_base_h_mm = pt_to_mm(item.height as f32).max(0.1);
        let scale = (avail_w_mm / img_base_w_mm).min(avail_h_mm / img_base_h_mm);
        let draw_w_mm = img_base_w_mm * scale;
        let draw_h_mm = img_base_h_mm * scale;

        let tx_mm = margin_mm + (avail_w_mm - draw_w_mm) / 2.0;
        let ty_mm = margin_mm + (avail_h_mm - draw_h_mm) / 2.0;

        let xobject = ImageXObject {
            width: Px(item.width as usize),
            height: Px(item.height as usize),
            color_space: ColorSpace::Rgb,
            bits_per_component: ColorBits::Bit8,
            interpolate: true,
            image_data: item.jpeg_bytes,
            image_filter: Some(ImageFilter::DCT),
            smask: None,
            clipping_bbox: None,
        };

        let pdf_img = Image::from(xobject);
        pdf_img.add_to_layer(
            layer,
            ImageTransform {
                translate_x: Some(Mm(tx_mm)),
                translate_y: Some(Mm(ty_mm)),
                rotate: None,
                scale_x: Some(scale),
                scale_y: Some(scale),
                dpi: Some(72.0),
            },
        );
    }

    let raw_pdf_bytes = doc
        .save_to_bytes()
        .map_err(|e| format!("Error al serializar PDF con printpdf: {:?}", e))?;

    // Quitar DecodeParams (ColorTransform 0) que printpdf agrega por defecto en DCT,
    // para que PDFium interprete correctamente streams JFIF YCbCr estándar.
    let mut lo_doc = lopdf::Document::load_mem(&raw_pdf_bytes)
        .map_err(|e| format!("Error optimizando PDF generado: {}", e))?;
    for object in lo_doc.objects.values_mut() {
        if let Object::Stream(ref mut stream) = object {
            let is_dct_image = stream
                .dict
                .get(b"Subtype")
                .and_then(Object::as_name)
                .map(|n| n == b"Image")
                .unwrap_or(false)
                && stream.dict.has(b"Filter");
            if is_dct_image {
                stream.dict.remove(b"DecodeParams");
            }
        }
    }
    let _ = lo_doc.compress();

    if let Some(parent) = Path::new(output_file_path).parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("No se pudo crear directorio de salida: {}", e))?;
    }

    lo_doc
        .save(output_file_path)
        .map_err(|e| format!("No se pudo guardar el PDF '{}': {}", output_file_path, e))?;

    Ok(Path::new(output_file_path)
        .metadata()
        .map(|m| m.len() as usize)
        .unwrap_or(0))
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum TextStyleKind {
    Regular,
    Bold,
    Italic,
    Mono,
}

enum RenderBlock {
    Heading { level: u8, text: String },
    Paragraph { text: String },
    CodeBlock { lines: Vec<String> },
    Quote { text: String },
    ListItem { prefix: String, text: String },
    Divider,
    Spacer(f32),
}

pub(crate) fn measure_text_mm(font_bytes: &[u8], text: &str, font_size_pt: f32) -> f32 {
    if let Ok(face) = Face::parse(font_bytes, 0) {
        let upem = face.units_per_em().max(1) as f32;
        let mut total_units = 0f32;
        for ch in text.chars() {
            if let Some(gid) = face.glyph_index(ch) {
                if let Some(adv) = face.glyph_hor_advance(gid) {
                    total_units += adv as f32;
                    continue;
                }
            }
            total_units += upem * 0.52;
        }
        pt_to_mm((total_units / upem) * font_size_pt)
    } else {
        pt_to_mm(text.chars().count() as f32 * font_size_pt * 0.52)
    }
}

pub(crate) fn wrap_text_lines(
    text: &str,
    max_width_mm: f32,
    font_bytes: &[u8],
    font_size_pt: f32,
) -> Vec<String> {
    let mut result = Vec::new();
    let max_w = max_width_mm.max(15.0);

    for raw_line in text.split('\n') {
        let trimmed = raw_line.trim_end();
        if trimmed.is_empty() {
            result.push(String::new());
            continue;
        }

        let mut current = String::new();
        for word in trimmed.split_whitespace() {
            let candidate = if current.is_empty() {
                word.to_string()
            } else {
                format!("{} {}", current, word)
            };

            if measure_text_mm(font_bytes, &candidate, font_size_pt) <= max_w {
                current = candidate;
            } else {
                if !current.is_empty() {
                    result.push(current);
                }

                if measure_text_mm(font_bytes, word, font_size_pt) <= max_w {
                    current = word.to_string();
                } else {
                    let mut chunk = String::new();
                    for ch in word.chars() {
                        let next_chunk = format!("{}{}", chunk, ch);
                        if !chunk.is_empty()
                            && measure_text_mm(font_bytes, &next_chunk, font_size_pt) > max_w
                        {
                            result.push(chunk);
                            chunk = ch.to_string();
                        } else {
                            chunk = next_chunk;
                        }
                    }
                    current = chunk;
                }
            }
        }

        if !current.is_empty() {
            result.push(current);
        }
    }

    if result.is_empty() {
        result.push(String::new());
    }
    result
}

fn strip_inline_markdown(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let chars: Vec<char> = input.chars().collect();
    let mut i = 0;

    while i < chars.len() {
        if i + 1 < chars.len()
            && ((chars[i] == '*' && chars[i + 1] == '*')
                || (chars[i] == '_' && chars[i + 1] == '_'))
        {
            i += 2;
            continue;
        }
        if chars[i] == '`' {
            out.push(' ');
            i += 1;
            continue;
        }
        if chars[i] == '*' || chars[i] == '_' {
            // Quitar marcadores de énfasis sueltos cuando delimitan palabras
            let prev_space = i == 0 || chars[i - 1].is_whitespace();
            let next_space = i + 1 >= chars.len() || chars[i + 1].is_whitespace();
            if !(prev_space && next_space) {
                i += 1;
                continue;
            }
        }
        out.push(chars[i]);
        i += 1;
    }

    out.trim().to_string()
}

fn parse_markdown_blocks(raw_content: &str, is_markdown: bool, scale: f32) -> Vec<RenderBlock> {
    let normalized = raw_content.replace("\r\n", "\n");

    if !is_markdown {
        return normalized
            .split('\n')
            .map(|line| {
                if line.trim().is_empty() {
                    RenderBlock::Spacer(2.8 * scale)
                } else {
                    RenderBlock::Paragraph {
                        text: line.to_string(),
                    }
                }
            })
            .collect();
    }

    let mut blocks = Vec::new();
    let mut in_code_block = false;
    let mut code_lines: Vec<String> = Vec::new();
    let mut para_buf = String::new();

    let flush_para = |buf: &mut String, out: &mut Vec<RenderBlock>| {
        let trimmed = buf.trim();
        if !trimmed.is_empty() {
            out.push(RenderBlock::Paragraph {
                text: strip_inline_markdown(trimmed),
            });
        }
        buf.clear();
    };

    for line in normalized.split('\n') {
        let trimmed = line.trim();

        if trimmed.starts_with("```") {
            flush_para(&mut para_buf, &mut blocks);
            if in_code_block {
                blocks.push(RenderBlock::CodeBlock {
                    lines: std::mem::take(&mut code_lines),
                });
                in_code_block = false;
            } else {
                in_code_block = true;
            }
            continue;
        }

        if in_code_block {
            code_lines.push(line.to_string());
            continue;
        }

        if trimmed.is_empty() {
            flush_para(&mut para_buf, &mut blocks);
            continue;
        }

        if trimmed == "---" || trimmed == "***" || trimmed == "___" {
            flush_para(&mut para_buf, &mut blocks);
            blocks.push(RenderBlock::Divider);
            continue;
        }

        if let Some(rest) = trimmed.strip_prefix("### ") {
            flush_para(&mut para_buf, &mut blocks);
            blocks.push(RenderBlock::Heading {
                level: 3,
                text: strip_inline_markdown(rest),
            });
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("## ") {
            flush_para(&mut para_buf, &mut blocks);
            blocks.push(RenderBlock::Heading {
                level: 2,
                text: strip_inline_markdown(rest),
            });
            continue;
        }
        if let Some(rest) = trimmed.strip_prefix("# ") {
            flush_para(&mut para_buf, &mut blocks);
            blocks.push(RenderBlock::Heading {
                level: 1,
                text: strip_inline_markdown(rest),
            });
            continue;
        }

        if let Some(rest) = trimmed.strip_prefix("> ") {
            flush_para(&mut para_buf, &mut blocks);
            blocks.push(RenderBlock::Quote {
                text: strip_inline_markdown(rest),
            });
            continue;
        }

        if let Some(rest) = trimmed.strip_prefix("- ").or_else(|| trimmed.strip_prefix("* ")) {
            flush_para(&mut para_buf, &mut blocks);
            blocks.push(RenderBlock::ListItem {
                prefix: "•".to_string(),
                text: strip_inline_markdown(rest),
            });
            continue;
        }

        if let Some(dot_idx) = trimmed.find(". ") {
            let num_part = &trimmed[..dot_idx];
            if !num_part.is_empty() && num_part.chars().all(|c| c.is_ascii_digit()) {
                flush_para(&mut para_buf, &mut blocks);
                blocks.push(RenderBlock::ListItem {
                    prefix: format!("{}.", num_part),
                    text: strip_inline_markdown(&trimmed[dot_idx + 2..]),
                });
                continue;
            }
        }

        if !para_buf.is_empty() {
            para_buf.push(' ');
        }
        para_buf.push_str(trimmed);
    }

    flush_para(&mut para_buf, &mut blocks);
    if in_code_block && !code_lines.is_empty() {
        blocks.push(RenderBlock::CodeBlock { lines: code_lines });
    }

    blocks
}

struct LoadedFonts {
    regular_bytes: Vec<u8>,
    bold_bytes: Vec<u8>,
    italic_bytes: Vec<u8>,
    mono_bytes: Vec<u8>,
    regular_ref: IndirectFontRef,
    bold_ref: IndirectFontRef,
    italic_ref: IndirectFontRef,
    mono_ref: IndirectFontRef,
}

impl LoadedFonts {
    fn font_for(&self, kind: TextStyleKind) -> (&IndirectFontRef, &[u8]) {
        match kind {
            TextStyleKind::Regular => (&self.regular_ref, &self.regular_bytes),
            TextStyleKind::Bold => (&self.bold_ref, &self.bold_bytes),
            TextStyleKind::Italic => (&self.italic_ref, &self.italic_bytes),
            TextStyleKind::Mono => (&self.mono_ref, &self.mono_bytes),
        }
    }
}

pub(crate) fn fill_rect(
    layer: &printpdf::PdfLayerReference,
    x_mm: f32,
    y_bottom_mm: f32,
    w_mm: f32,
    h_mm: f32,
    color: Rgb,
) {
    let rect = Polygon {
        rings: vec![vec![
            (printpdf::Point::new(Mm(x_mm), Mm(y_bottom_mm)), false),
            (printpdf::Point::new(Mm(x_mm + w_mm), Mm(y_bottom_mm)), false),
            (
                printpdf::Point::new(Mm(x_mm + w_mm), Mm(y_bottom_mm + h_mm)),
                false,
            ),
            (printpdf::Point::new(Mm(x_mm), Mm(y_bottom_mm + h_mm)), false),
        ]],
        mode: PaintMode::Fill,
        winding_order: WindingOrder::NonZero,
    };
    layer.set_fill_color(Color::Rgb(color));
    layer.add_polygon(rect);
}

/// Compila texto plano o Markdown a un PDF multipágina con fuentes TTF Roboto locales y soporte Unicode completo.
#[allow(clippy::too_many_arguments)]
pub fn markdown_to_pdf(
    raw_content: &str,
    document_title: &str,
    is_markdown: bool,
    output_pdf_path: &str,
    page_size: &str,
    margin_points: f32,
    font_scale: f32,
    show_page_numbers: bool,
    regular_font_path: &str,
    bold_font_path: &str,
    italic_font_path: &str,
    mono_font_path: &str,
) -> Result<String, String> {
    let regular_bytes = fs::read(regular_font_path).map_err(|e| {
        format!(
            "No se pudo cargar la fuente Unicode '{}': {}",
            regular_font_path, e
        )
    })?;
    let bold_bytes = fs::read(bold_font_path).unwrap_or_else(|_| regular_bytes.clone());
    let italic_bytes = fs::read(italic_font_path).unwrap_or_else(|_| regular_bytes.clone());
    let mono_bytes = fs::read(mono_font_path).unwrap_or_else(|_| regular_bytes.clone());

    let (page_w_mm, page_h_mm) = if page_size == "letter" {
        (215.9f32, 279.4f32)
    } else {
        (210.0f32, 297.0f32)
    };

    let margin_mm = pt_to_mm(margin_points.max(12.0));
    let footer_reserve_mm = if show_page_numbers { 10.0 } else { 0.0 };
    let content_w_mm = (page_w_mm - margin_mm * 2.0).max(40.0);
    let scale = font_scale.clamp(0.6, 2.0);

    let (doc, page1, layer1) = PdfDocument::new(
        document_title,
        Mm(page_w_mm),
        Mm(page_h_mm),
        "Layer 1",
    );
    let doc = doc
        .with_producer("LocalConvert Rust Markdown Engine")
        .with_creator("LocalConvert");

    let regular_ref = doc
        .add_external_font(Cursor::new(regular_bytes.clone()))
        .map_err(|e| format!("Error cargando fuente Regular TTF: {:?}", e))?;
    let bold_ref = doc
        .add_external_font(Cursor::new(bold_bytes.clone()))
        .map_err(|e| format!("Error cargando fuente Bold TTF: {:?}", e))?;
    let italic_ref = doc
        .add_external_font(Cursor::new(italic_bytes.clone()))
        .map_err(|e| format!("Error cargando fuente Italic TTF: {:?}", e))?;
    let mono_ref = doc
        .add_external_font(Cursor::new(mono_bytes.clone()))
        .map_err(|e| format!("Error cargando fuente Mono TTF: {:?}", e))?;

    let fonts = LoadedFonts {
        regular_bytes,
        bold_bytes,
        italic_bytes,
        mono_bytes,
        regular_ref,
        bold_ref,
        italic_ref,
        mono_ref,
    };

    let mut page_refs = vec![(page1, layer1)];
    let mut cursor_y = page_h_mm - margin_mm;
    let bottom_limit = margin_mm + footer_reserve_mm;

    let ensure_space = |needed_mm: f32,
                        cursor_y: &mut f32,
                        page_refs: &mut Vec<(printpdf::PdfPageIndex, printpdf::PdfLayerIndex)>| {
        if *cursor_y - needed_mm < bottom_limit {
            let new_page = doc.add_page(Mm(page_w_mm), Mm(page_h_mm), "Layer 1");
            page_refs.push(new_page);
            *cursor_y = page_h_mm - margin_mm;
        }
    };

    let blocks = parse_markdown_blocks(raw_content, is_markdown, scale);

    for block in blocks {
        match block {
            RenderBlock::Spacer(h) => {
                cursor_y -= h;
            }
            RenderBlock::Divider => {
                ensure_space(6.0 * scale, &mut cursor_y, &mut page_refs);
                cursor_y -= 2.5 * scale;
                let &(p_idx, l_idx) = page_refs.last().unwrap();
                let layer = doc.get_page(p_idx).get_layer(l_idx);
                fill_rect(
                    &layer,
                    margin_mm,
                    cursor_y,
                    content_w_mm,
                    0.35,
                    Rgb::new(0.82, 0.84, 0.87, None),
                );
                cursor_y -= 3.5 * scale;
            }
            RenderBlock::Heading { level, text } => {
                let font_pt = match level {
                    1 => 21.0 * scale,
                    2 => 16.5 * scale,
                    _ => 13.0 * scale,
                };
                let line_h_mm = pt_to_mm(font_pt) * 1.35;
                let (font_ref, f_bytes) = fonts.font_for(TextStyleKind::Bold);
                let wrapped = wrap_text_lines(&text, content_w_mm, f_bytes, font_pt);

                cursor_y -= if level == 1 { 3.5 * scale } else { 2.5 * scale };
                for line in wrapped {
                    ensure_space(line_h_mm + 2.0, &mut cursor_y, &mut page_refs);
                    let &(p_idx, l_idx) = page_refs.last().unwrap();
                    let layer = doc.get_page(p_idx).get_layer(l_idx);
                    layer.set_fill_color(Color::Rgb(Rgb::new(0.08, 0.11, 0.16, None)));
                    layer.use_text(
                        line,
                        font_pt,
                        Mm(margin_mm),
                        Mm(cursor_y - pt_to_mm(font_pt)),
                        font_ref,
                    );
                    cursor_y -= line_h_mm;
                }
                if level <= 2 {
                    let &(p_idx, l_idx) = page_refs.last().unwrap();
                    let layer = doc.get_page(p_idx).get_layer(l_idx);
                    fill_rect(
                        &layer,
                        margin_mm,
                        cursor_y - 0.8,
                        content_w_mm,
                        0.3,
                        Rgb::new(0.84, 0.86, 0.90, None),
                    );
                    cursor_y -= 2.5 * scale;
                } else {
                    cursor_y -= 1.5 * scale;
                }
            }
            RenderBlock::Paragraph { text } => {
                let font_pt = 11.0 * scale;
                let line_h_mm = pt_to_mm(font_pt) * 1.45;
                let (font_ref, f_bytes) = fonts.font_for(TextStyleKind::Regular);
                let wrapped = wrap_text_lines(&text, content_w_mm, f_bytes, font_pt);

                for line in wrapped {
                    ensure_space(line_h_mm, &mut cursor_y, &mut page_refs);
                    let &(p_idx, l_idx) = page_refs.last().unwrap();
                    let layer = doc.get_page(p_idx).get_layer(l_idx);
                    layer.set_fill_color(Color::Rgb(Rgb::new(0.12, 0.14, 0.18, None)));
                    layer.use_text(
                        line,
                        font_pt,
                        Mm(margin_mm),
                        Mm(cursor_y - pt_to_mm(font_pt)),
                        font_ref,
                    );
                    cursor_y -= line_h_mm;
                }
                cursor_y -= 2.2 * scale;
            }
            RenderBlock::Quote { text } => {
                let font_pt = 10.8 * scale;
                let line_h_mm = pt_to_mm(font_pt) * 1.45;
                let indent_mm = 5.0;
                let (font_ref, f_bytes) = fonts.font_for(TextStyleKind::Italic);
                let wrapped = wrap_text_lines(&text, content_w_mm - indent_mm - 3.0, f_bytes, font_pt);

                for line in wrapped {
                    ensure_space(line_h_mm + 1.0, &mut cursor_y, &mut page_refs);
                    let &(p_idx, l_idx) = page_refs.last().unwrap();
                    let layer = doc.get_page(p_idx).get_layer(l_idx);
                    fill_rect(
                        &layer,
                        margin_mm,
                        cursor_y - line_h_mm,
                        content_w_mm,
                        line_h_mm,
                        Rgb::new(0.95, 0.96, 0.97, None),
                    );
                    fill_rect(
                        &layer,
                        margin_mm,
                        cursor_y - line_h_mm,
                        1.1,
                        line_h_mm,
                        Rgb::new(0.05, 0.58, 0.53, None),
                    );
                    layer.set_fill_color(Color::Rgb(Rgb::new(0.20, 0.24, 0.30, None)));
                    layer.use_text(
                        line,
                        font_pt,
                        Mm(margin_mm + indent_mm),
                        Mm(cursor_y - pt_to_mm(font_pt) - 0.6),
                        font_ref,
                    );
                    cursor_y -= line_h_mm;
                }
                cursor_y -= 2.5 * scale;
            }
            RenderBlock::CodeBlock { lines } => {
                let font_pt = 9.5 * scale;
                let line_h_mm = pt_to_mm(font_pt) * 1.42;
                let pad_x = 3.5;
                let (font_ref, f_bytes) = fonts.font_for(TextStyleKind::Mono);

                let mut wrapped_lines = Vec::new();
                for code_line in lines {
                    wrapped_lines.extend(wrap_text_lines(
                        &code_line,
                        content_w_mm - pad_x * 2.0,
                        f_bytes,
                        font_pt,
                    ));
                }

                for line in wrapped_lines {
                    ensure_space(line_h_mm + 1.0, &mut cursor_y, &mut page_refs);
                    let &(p_idx, l_idx) = page_refs.last().unwrap();
                    let layer = doc.get_page(p_idx).get_layer(l_idx);
                    fill_rect(
                        &layer,
                        margin_mm,
                        cursor_y - line_h_mm,
                        content_w_mm,
                        line_h_mm,
                        Rgb::new(0.94, 0.95, 0.97, None),
                    );
                    layer.set_fill_color(Color::Rgb(Rgb::new(0.11, 0.13, 0.17, None)));
                    layer.use_text(
                        line,
                        font_pt,
                        Mm(margin_mm + pad_x),
                        Mm(cursor_y - pt_to_mm(font_pt) - 0.5),
                        font_ref,
                    );
                    cursor_y -= line_h_mm;
                }
                cursor_y -= 2.8 * scale;
            }
            RenderBlock::ListItem { prefix, text } => {
                let font_pt = 11.0 * scale;
                let line_h_mm = pt_to_mm(font_pt) * 1.42;
                let bullet_w = 6.5;
                let (bold_ref, _) = fonts.font_for(TextStyleKind::Bold);
                let (reg_ref, reg_bytes) = fonts.font_for(TextStyleKind::Regular);
                let wrapped = wrap_text_lines(&text, content_w_mm - bullet_w - 2.0, reg_bytes, font_pt);

                for (idx, line) in wrapped.into_iter().enumerate() {
                    ensure_space(line_h_mm, &mut cursor_y, &mut page_refs);
                    let &(p_idx, l_idx) = page_refs.last().unwrap();
                    let layer = doc.get_page(p_idx).get_layer(l_idx);
                    let baseline_y = cursor_y - pt_to_mm(font_pt);
                    layer.set_fill_color(Color::Rgb(Rgb::new(0.12, 0.14, 0.18, None)));

                    if idx == 0 {
                        layer.use_text(
                            prefix.clone(),
                            font_pt,
                            Mm(margin_mm + 1.5),
                            Mm(baseline_y),
                            bold_ref,
                        );
                    }
                    layer.use_text(line, font_pt, Mm(margin_mm + bullet_w), Mm(baseline_y), reg_ref);
                    cursor_y -= line_h_mm;
                }
                cursor_y -= 1.2 * scale;
            }
        }
    }

    if show_page_numbers {
        let total_pages = page_refs.len();
        let footer_pt = 9.0f32;
        let (reg_ref, reg_bytes) = fonts.font_for(TextStyleKind::Regular);
        for (idx, &(p_idx, l_idx)) in page_refs.iter().enumerate() {
            let label = format!("Página {} de {}", idx + 1, total_pages);
            let label_w = measure_text_mm(reg_bytes, &label, footer_pt);
            let x = (page_w_mm - margin_mm - label_w).max(margin_mm);
            let y = (margin_mm * 0.45).max(5.0);
            let layer = doc.get_page(p_idx).get_layer(l_idx);
            layer.set_fill_color(Color::Rgb(Rgb::new(0.45, 0.48, 0.54, None)));
            layer.use_text(label, footer_pt, Mm(x), Mm(y), reg_ref);
        }
    }

    if let Some(parent) = Path::new(output_pdf_path).parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("No se pudo crear el directorio de salida: {}", e))?;
    }

    let out_file = fs::File::create(output_pdf_path)
        .map_err(|e| format!("No se pudo crear '{}': {}", output_pdf_path, e))?;
    let mut writer = BufWriter::new(out_file);
    doc.save(&mut writer)
        .map_err(|e| format!("Error al guardar PDF de Markdown: {:?}", e))?;

    Ok(output_pdf_path.to_string())
}
