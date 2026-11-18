mod icon_gen;
mod image_ops;
mod office_ops;
mod pdf_gen;
mod pdf_ops;
mod qr_ops;

use std::ffi::CString;
use std::os::raw::c_char;
use std::slice;

use serde::{Deserialize, Serialize};

use icon_gen::generate_app_icons;
use image_ops::{
    compress_resize_batch, convert_image_batch, create_zip_archive, encode_rgba_buffer,
    estimate_single_image,
};
use office_ops::{convert_docx, convert_spreadsheet, inspect_docx, inspect_spreadsheet};
use pdf_gen::{images_to_pdf, markdown_to_pdf};
use pdf_ops::{merge_pdfs, split_pdf, SplitSegmentInput};
use qr_ops::{generate_qr_batch, generate_qr_preview};

#[derive(Debug, Deserialize)]
#[serde(tag = "action")]
enum RustRequest {
    #[serde(rename = "merge_pdfs")]
    MergePdfs {
        input_paths: Vec<String>,
        output_pdf_path: String,
        #[serde(default = "default_quality_preset")]
        quality_preset: String,
    },
    #[serde(rename = "split_pdf")]
    SplitPdf {
        source_pdf_path: String,
        output_mode: String,
        output_path: String,
        base_name: String,
        segments: Vec<SplitSegmentInput>,
    },
    #[serde(rename = "images_to_pdf")]
    ImagesToPdf {
        image_paths: Vec<String>,
        output_file_path: String,
        page_size: String,
        orientation: String,
        margin_points: f32,
        jpeg_quality: u8,
        max_dimension_px: u32,
    },
    #[serde(rename = "convert_image_batch")]
    ConvertImageBatch {
        input_paths: Vec<String>,
        session_dir_path: String,
        target_format: String,
        quality: u8,
        max_dimension_px: u32,
        package_as_zip: bool,
    },
    #[serde(rename = "estimate_single_image")]
    EstimateSingleImage {
        file_path: String,
        resize_mode: String,
        scale_percent: u32,
        target_width_px: Option<u32>,
        target_height_px: Option<u32>,
        maintain_aspect_ratio: bool,
        quality: u8,
        max_dimension_px: u32,
    },
    #[serde(rename = "compress_resize_batch")]
    CompressResizeBatch {
        input_paths: Vec<String>,
        session_dir_path: String,
        resize_mode: String,
        scale_percent: u32,
        target_width_px: Option<u32>,
        target_height_px: Option<u32>,
        maintain_aspect_ratio: bool,
        quality: u8,
        max_dimension_px: u32,
    },
    #[serde(rename = "markdown_to_pdf")]
    MarkdownToPdf {
        raw_content: String,
        document_title: String,
        is_markdown: bool,
        output_pdf_path: String,
        page_size: String,
        margin_points: f32,
        font_scale: f32,
        show_page_numbers: bool,
        regular_font_path: String,
        bold_font_path: String,
        italic_font_path: String,
        mono_font_path: String,
    },
    #[serde(rename = "create_zip")]
    CreateZip {
        input_paths: Vec<String>,
        output_zip_path: String,
    },
    #[serde(rename = "generate_app_icons")]
    GenerateAppIcons {
        ico_output_path: String,
        png_output_path: String,
    },
    #[serde(rename = "inspect_spreadsheet")]
    InspectSpreadsheet {
        file_path: String,
        sheet_name: Option<String>,
    },
    #[serde(rename = "convert_spreadsheet")]
    ConvertSpreadsheet {
        file_path: String,
        sheet_name: Option<String>,
        output_format: String,
        output_path: String,
        csv_delimiter: String,
        page_size: String,
        orientation: String,
        regular_font_path: String,
        bold_font_path: String,
    },
    #[serde(rename = "inspect_docx")]
    InspectDocx { file_path: String },
    #[serde(rename = "convert_docx")]
    ConvertDocx {
        file_path: String,
        output_format: String,
        output_path: String,
        page_size: String,
        margin_points: f32,
        font_scale: f32,
        show_page_numbers: bool,
        regular_font_path: String,
        bold_font_path: String,
        italic_font_path: String,
        mono_font_path: String,
    },
    #[serde(rename = "generate_qr_preview")]
    GenerateQrPreview {
        content: String,
        ec_level: String,
        size_px: u32,
        output_path: String,
    },
    #[serde(rename = "generate_qr_batch")]
    GenerateQrBatch {
        items: Vec<String>,
        session_dir_path: String,
        output_format: String,
        ec_level: String,
        size_px: u32,
        package_as_zip: bool,
        regular_font_path: String,
        bold_font_path: String,
    },
}

fn default_quality_preset() -> String {
    "balanced".to_string()
}

#[derive(Debug, Serialize)]
struct RustResponse {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<serde_json::Value>,
}

fn dispatch_json_request(raw_json: &str) -> RustResponse {
    let parsed: Result<RustRequest, _> = serde_json::from_str(raw_json);
    let req = match parsed {
        Ok(r) => r,
        Err(e) => {
            return RustResponse {
                ok: false,
                error: Some(format!("JSON inválido en petición Rust: {}", e)),
                data: None,
            };
        }
    };

    match execute_request(req) {
        Ok(val) => RustResponse {
            ok: true,
            error: None,
            data: Some(val),
        },
        Err(err) => RustResponse {
            ok: false,
            error: Some(err),
            data: None,
        },
    }
}

fn execute_request(req: RustRequest) -> Result<serde_json::Value, String> {
    match req {
        RustRequest::MergePdfs {
            input_paths,
            output_pdf_path,
            quality_preset,
        } => {
            let pages = merge_pdfs(&input_paths, &output_pdf_path, &quality_preset)?;
            Ok(serde_json::json!({
                "merged_pages": pages,
                "output_pdf_path": output_pdf_path,
            }))
        }
        RustRequest::SplitPdf {
            source_pdf_path,
            output_mode,
            output_path,
            base_name,
            segments,
        } => {
            let extracted_pages =
                split_pdf(&source_pdf_path, &output_mode, &output_path, &base_name, &segments)?;
            Ok(serde_json::json!({
                "extracted_pages": extracted_pages,
                "output_path": output_path,
            }))
        }
        RustRequest::ImagesToPdf {
            image_paths,
            output_file_path,
            page_size,
            orientation,
            margin_points,
            jpeg_quality,
            max_dimension_px,
        } => {
            let size_bytes = images_to_pdf(
                &image_paths,
                &output_file_path,
                &page_size,
                &orientation,
                margin_points,
                jpeg_quality,
                max_dimension_px,
            )?;
            Ok(serde_json::json!({
                "output_file_path": output_file_path,
                "output_size_bytes": size_bytes,
            }))
        }
        RustRequest::ConvertImageBatch {
            input_paths,
            session_dir_path,
            target_format,
            quality,
            max_dimension_px,
            package_as_zip,
        } => {
            let res = convert_image_batch(
                &input_paths,
                &session_dir_path,
                &target_format,
                quality,
                max_dimension_px,
                package_as_zip,
            )?;
            serde_json::to_value(res).map_err(|e| e.to_string())
        }
        RustRequest::EstimateSingleImage {
            file_path,
            resize_mode,
            scale_percent,
            target_width_px,
            target_height_px,
            maintain_aspect_ratio,
            quality,
            max_dimension_px,
        } => {
            let res = estimate_single_image(
                &file_path,
                &resize_mode,
                scale_percent,
                target_width_px,
                target_height_px,
                maintain_aspect_ratio,
                quality,
                max_dimension_px,
            )?;
            serde_json::to_value(res).map_err(|e| e.to_string())
        }
        RustRequest::CompressResizeBatch {
            input_paths,
            session_dir_path,
            resize_mode,
            scale_percent,
            target_width_px,
            target_height_px,
            maintain_aspect_ratio,
            quality,
            max_dimension_px,
        } => {
            let res = compress_resize_batch(
                &input_paths,
                &session_dir_path,
                &resize_mode,
                scale_percent,
                target_width_px,
                target_height_px,
                maintain_aspect_ratio,
                quality,
                max_dimension_px,
            )?;
            serde_json::to_value(res).map_err(|e| e.to_string())
        }
        RustRequest::MarkdownToPdf {
            raw_content,
            document_title,
            is_markdown,
            output_pdf_path,
            page_size,
            margin_points,
            font_scale,
            show_page_numbers,
            regular_font_path,
            bold_font_path,
            italic_font_path,
            mono_font_path,
        } => {
            let path = markdown_to_pdf(
                &raw_content,
                &document_title,
                is_markdown,
                &output_pdf_path,
                &page_size,
                margin_points,
                font_scale,
                show_page_numbers,
                &regular_font_path,
                &bold_font_path,
                &italic_font_path,
                &mono_font_path,
            )?;
            Ok(serde_json::json!({ "output_pdf_path": path }))
        }
        RustRequest::CreateZip {
            input_paths,
            output_zip_path,
        } => {
            let zip_path = create_zip_archive(&input_paths, &output_zip_path)?;
            Ok(serde_json::json!({ "zip_file_path": zip_path }))
        }
        RustRequest::GenerateAppIcons {
            ico_output_path,
            png_output_path,
        } => {
            let res = generate_app_icons(&ico_output_path, &png_output_path)?;
            serde_json::to_value(res).map_err(|e| e.to_string())
        }
        RustRequest::InspectSpreadsheet {
            file_path,
            sheet_name,
        } => {
            let res = inspect_spreadsheet(&file_path, sheet_name.as_deref())?;
            serde_json::to_value(res).map_err(|e| e.to_string())
        }
        RustRequest::ConvertSpreadsheet {
            file_path,
            sheet_name,
            output_format,
            output_path,
            csv_delimiter,
            page_size,
            orientation,
            regular_font_path,
            bold_font_path,
        } => {
            let res = convert_spreadsheet(
                &file_path,
                sheet_name.as_deref(),
                &output_format,
                &output_path,
                &csv_delimiter,
                &page_size,
                &orientation,
                &regular_font_path,
                &bold_font_path,
            )?;
            serde_json::to_value(res).map_err(|e| e.to_string())
        }
        RustRequest::InspectDocx { file_path } => {
            let res = inspect_docx(&file_path)?;
            serde_json::to_value(res).map_err(|e| e.to_string())
        }
        RustRequest::ConvertDocx {
            file_path,
            output_format,
            output_path,
            page_size,
            margin_points,
            font_scale,
            show_page_numbers,
            regular_font_path,
            bold_font_path,
            italic_font_path,
            mono_font_path,
        } => {
            let res = convert_docx(
                &file_path,
                &output_format,
                &output_path,
                &page_size,
                margin_points,
                font_scale,
                show_page_numbers,
                &regular_font_path,
                &bold_font_path,
                &italic_font_path,
                &mono_font_path,
            )?;
            serde_json::to_value(res).map_err(|e| e.to_string())
        }
        RustRequest::GenerateQrPreview {
            content,
            ec_level,
            size_px,
            output_path,
        } => {
            let res = generate_qr_preview(&content, &ec_level, size_px, &output_path)?;
            serde_json::to_value(res).map_err(|e| e.to_string())
        }
        RustRequest::GenerateQrBatch {
            items,
            session_dir_path,
            output_format,
            ec_level,
            size_px,
            package_as_zip,
            regular_font_path,
            bold_font_path,
        } => {
            let res = generate_qr_batch(
                &items,
                &session_dir_path,
                &output_format,
                &ec_level,
                size_px,
                package_as_zip,
                &regular_font_path,
                &bold_font_path,
            )?;
            serde_json::to_value(res).map_err(|e| e.to_string())
        }
    }
}

fn leak_vec_to_ffi(mut bytes: Vec<u8>, out_len: *mut usize) -> *mut u8 {
    if bytes.is_empty() {
        if !out_len.is_null() {
            unsafe { *out_len = 0 };
        }
        return std::ptr::null_mut();
    }
    bytes.shrink_to_fit();
    let len = bytes.len();
    let ptr = bytes.as_mut_ptr();
    std::mem::forget(bytes);
    if !out_len.is_null() {
        unsafe { *out_len = len };
    }
    ptr
}

/// Reserva un buffer contiguo en el heap de Rust (para entrada desde Dart FFI).
#[no_mangle]
pub extern "C" fn rust_alloc_buffer(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut vec = vec![0u8; size];
    let ptr = vec.as_mut_ptr();
    std::mem::forget(vec);
    ptr
}

/// Libera un buffer previamente asignado o devuelto por Rust (`rust_alloc_buffer`,
/// `rust_execute_json`, `rust_encode_rgba_buffer`).
///
/// # Safety
/// `ptr` debe provenir del asignador de Rust y `size` debe coincidir con su longitud exacta.
#[no_mangle]
pub unsafe extern "C" fn rust_free_buffer(ptr: *mut u8, size: usize) {
    if !ptr.is_null() && size > 0 {
        drop(Vec::from_raw_parts(ptr, size, size));
    }
}

/// Libera un `CString` devuelto por Rust si se usa vía punteros de texto C.
///
/// # Safety
/// `ptr` debe haber sido creado mediante `CString::into_raw`.
#[no_mangle]
pub unsafe extern "C" fn rust_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

/// Punto de entrada principal FFI por JSON UTF-8.
///
/// # Safety
/// `req_ptr` debe ser válido por `req_len` bytes y `out_len` debe ser escribible.
#[no_mangle]
pub unsafe extern "C" fn rust_execute_json(
    req_ptr: *const u8,
    req_len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let response = if req_ptr.is_null() || req_len == 0 {
        RustResponse {
            ok: false,
            error: Some("Petición FFI vacía.".to_string()),
            data: None,
        }
    } else {
        let slice = slice::from_raw_parts(req_ptr, req_len);
        match std::str::from_utf8(slice) {
            Ok(json_str) => dispatch_json_request(json_str),
            Err(e) => RustResponse {
                ok: false,
                error: Some(format!("UTF-8 inválido en petición FFI: {}", e)),
                data: None,
            },
        }
    };

    let bytes = serde_json::to_vec(&response)
        .unwrap_or_else(|_| br#"{"ok":false,"error":"Serialization failure"}"#.to_vec());
    leak_vec_to_ffi(bytes, out_len)
}

/// Codifica un buffer crudo RGBA en memoria hacia PNG/JPG/WEBP/BMP/TIFF/ICO/GIF/TGA.
///
/// # Safety
/// `rgba_ptr` (`rgba_len`), `format_ptr` (`format_len`) y `out_len` deben ser punteros válidos.
#[no_mangle]
pub unsafe extern "C" fn rust_encode_rgba_buffer(
    rgba_ptr: *const u8,
    rgba_len: usize,
    width: u32,
    height: u32,
    format_ptr: *const u8,
    format_len: usize,
    quality: u8,
    out_len: *mut usize,
) -> *mut u8 {
    if rgba_ptr.is_null() || format_ptr.is_null() || width == 0 || height == 0 {
        if !out_len.is_null() {
            *out_len = 0;
        }
        return std::ptr::null_mut();
    }

    let rgba_slice = slice::from_raw_parts(rgba_ptr, rgba_len);
    let fmt_slice = slice::from_raw_parts(format_ptr, format_len);
    let Ok(format_str) = std::str::from_utf8(fmt_slice) else {
        if !out_len.is_null() {
            *out_len = 0;
        }
        return std::ptr::null_mut();
    };

    match encode_rgba_buffer(rgba_slice, width, height, format_str, quality) {
        Ok(encoded) => leak_vec_to_ffi(encoded, out_len),
        Err(_) => {
            if !out_len.is_null() {
                *out_len = 0;
            }
            std::ptr::null_mut()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{DynamicImage, Rgba, RgbaImage};
    use lopdf::content::{Content, Operation};
    use lopdf::{dictionary, Document, Object, Stream};
    use std::path::PathBuf;

    fn temp_test_dir(prefix: &str) -> PathBuf {
        let mut dir = std::env::temp_dir();
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        dir.push(format!("{}_{}", prefix, unique));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn create_sample_vector_pdf(path: &PathBuf, text: &str) {
        let mut doc = Document::with_version("1.5");
        let pages_id = doc.new_object_id();
        let font_id = doc.add_object(dictionary! {
            "Type" => "Font",
            "Subtype" => "Type1",
            "BaseFont" => "Helvetica",
        });
        let resources_id = doc.add_object(dictionary! {
            "Font" => dictionary! {
                "F1" => font_id,
            },
        });
        let content = Content {
            operations: vec![
                Operation::new("BT", vec![]),
                Operation::new("Tf", vec!["F1".into(), 14.into()]),
                Operation::new("Td", vec![50.into(), 700.into()]),
                Operation::new("Tj", vec![Object::string_literal(text)]),
                Operation::new("ET", vec![]),
            ],
        };
        let content_id = doc.add_object(Stream::new(dictionary! {}, content.encode().unwrap()));
        let page_id = doc.add_object(dictionary! {
            "Type" => "Page",
            "Parent" => pages_id,
            "Contents" => content_id,
            "Resources" => resources_id,
            "MediaBox" => vec![0.into(), 0.into(), 595.into(), 842.into()],
        });
        let pages_dict = dictionary! {
            "Type" => "Pages",
            "Count" => 1,
            "Kids" => vec![page_id.into()],
        };
        doc.objects.insert(pages_id, Object::Dictionary(pages_dict));
        let catalog_id = doc.add_object(dictionary! {
            "Type" => "Catalog",
            "Pages" => pages_id,
        });
        doc.trailer.set("Root", catalog_id);
        doc.compress();
        doc.save(path).unwrap();
    }

    #[test]
    fn test_merge_and_split_vector_pdfs() {
        let dir = temp_test_dir("lc_rust_pdf");
        let pdf1 = dir.join("one.pdf");
        let pdf2 = dir.join("two.pdf");
        let merged = dir.join("merged.pdf");
        let split_single = dir.join("split.pdf");

        create_sample_vector_pdf(&pdf1, "Texto Vectorial Uno");
        create_sample_vector_pdf(&pdf2, "Texto Vectorial Dos");

        let count = merge_pdfs(
            &[
                pdf1.to_string_lossy().into_owned(),
                pdf2.to_string_lossy().into_owned(),
            ],
            &merged.to_string_lossy(),
            "balanced",
        )
        .unwrap();
        assert_eq!(count, 2);

        let merged_doc = Document::load(&merged).unwrap();
        assert_eq!(merged_doc.get_pages().len(), 2);
        let text_all = merged_doc.extract_text(&[1, 2]).unwrap();
        assert!(text_all.contains("Texto Vectorial Uno"));
        assert!(text_all.contains("Texto Vectorial Dos"));

        let extracted = split_pdf(
            &merged.to_string_lossy(),
            "single_combined_pdf",
            &split_single.to_string_lossy(),
            "merged",
            &[SplitSegmentInput {
                label: "pág_2".to_string(),
                pages: vec![2],
            }],
        )
        .unwrap();
        assert_eq!(extracted, 1);

        let split_doc = Document::load(&split_single).unwrap();
        assert_eq!(split_doc.get_pages().len(), 1);
        let split_text = split_doc.extract_text(&[1]).unwrap();
        assert!(split_text.contains("Texto Vectorial Dos"));
        assert!(!split_text.contains("Texto Vectorial Uno"));

        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn test_encode_four_core_formats_and_compression() {
        let mut rgba = RgbaImage::new(32, 24);
        for px in rgba.pixels_mut() {
            *px = Rgba([229, 50, 45, 200]);
        }
        let raw = rgba.as_raw();

        let png = encode_rgba_buffer(raw, 32, 24, "png", 90).unwrap();
        assert_eq!(&png[0..4], &[0x89, 0x50, 0x4E, 0x47]);

        let jpg = encode_rgba_buffer(raw, 32, 24, "jpg", 85).unwrap();
        assert_eq!(&jpg[0..2], &[0xFF, 0xD8]);

        let bmp = encode_rgba_buffer(raw, 32, 24, "bmp", 90).unwrap();
        assert_eq!(&bmp[0..2], &[0x42, 0x4D]);

        let webp = encode_rgba_buffer(raw, 32, 24, "webp", 85).unwrap();
        assert_eq!(&webp[0..4], b"RIFF");
        assert_eq!(&webp[8..12], b"WEBP");

        let dir = temp_test_dir("lc_rust_comp");
        let src_png = dir.join("sample.png");
        DynamicImage::ImageRgba8(rgba).save(&src_png).unwrap();

        let est = estimate_single_image(
            &src_png.to_string_lossy(),
            "percentage",
            50,
            None,
            None,
            true,
            70,
            4096,
        )
        .unwrap();
        assert_eq!(est.original_width, 32);
        assert_eq!(est.target_width, 16);
        assert_eq!(est.target_height, 12);
        assert!(est.estimated_bytes > 0);

        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn test_images_to_pdf_and_markdown_to_pdf_unicode() {
        let dir = temp_test_dir("lc_rust_pdfgen");
        let img_path = dir.join("dot.png");
        let mut rgba = RgbaImage::new(20, 16);
        for px in rgba.pixels_mut() {
            *px = Rgba([37, 99, 235, 180]);
        }
        DynamicImage::ImageRgba8(rgba).save(&img_path).unwrap();

        let img_pdf = dir.join("img.pdf");
        images_to_pdf(
            &[img_path.to_string_lossy().into_owned()],
            &img_pdf.to_string_lossy(),
            "fitToImage",
            "portrait",
            16.0,
            88,
            2560,
        )
        .unwrap();
        let img_bytes = std::fs::read(&img_pdf).unwrap();
        assert!(img_bytes.starts_with(b"%PDF-1."));

        // Resolver ruta de fuentes Roboto del repo para verificar Unicode en PDF Markdown
        let fonts_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("assets")
            .join("fonts");
        let reg = fonts_dir.join("Roboto-Regular.ttf");
        if reg.exists() {
            let md_pdf = dir.join("md.pdf");
            markdown_to_pdf(
                "# Título Ñ € • —\n\nTexto **negrita** y *cursiva*.\n\n- Ítem 1",
                "Test Markdown",
                true,
                &md_pdf.to_string_lossy(),
                "a4",
                42.0,
                1.0,
                true,
                &reg.to_string_lossy(),
                &fonts_dir.join("Roboto-Bold.ttf").to_string_lossy(),
                &fonts_dir.join("Roboto-Italic.ttf").to_string_lossy(),
                &fonts_dir.join("RobotoMono-Regular.ttf").to_string_lossy(),
            )
            .unwrap();
            let md_bytes = std::fs::read(&md_pdf).unwrap();
            assert!(md_bytes.starts_with(b"%PDF-1."));
        }

        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn test_generate_brand_icons_multilayer_ico_and_png() {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .to_path_buf();
        let ico_path = root.join("windows").join("runner").join("resources").join("app_icon.ico");
        let png_path = root.join("assets").join("icons").join("app_icon.png");

        let res = generate_app_icons(
            &ico_path.to_string_lossy(),
            &png_path.to_string_lossy(),
        )
        .unwrap();
        assert_eq!(res.sizes, vec![16, 32, 48, 64, 128, 256]);

        let ico_bytes = std::fs::read(&ico_path).unwrap();
        assert_eq!(&ico_bytes[0..6], &[0, 0, 1, 0, 6, 0]);
        let png_bytes = std::fs::read(&png_path).unwrap();
        assert_eq!(&png_bytes[0..4], &[0x89, 0x50, 0x4E, 0x47]);
        let decoded_png = image::load_from_memory(&png_bytes).unwrap();
        assert_eq!(decoded_png.width(), 256);
        assert_eq!(decoded_png.height(), 256);
    }

    fn write_zip_entries(path: &PathBuf, entries: &[(&str, &[u8])]) {
        use std::io::Write;
        use zip::write::SimpleFileOptions;
        let file = std::fs::File::create(path).unwrap();
        let mut zip = zip::ZipWriter::new(file);
        let opt = SimpleFileOptions::default();
        for (name, content) in entries {
            zip.start_file(*name, opt).unwrap();
            zip.write_all(content).unwrap();
        }
        zip.finish().unwrap();
    }

    #[test]
    fn test_spreadsheet_docx_and_qr_engines() {
        let dir = temp_test_dir("lc_rust_office_qr");
        let fonts_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .unwrap()
            .join("assets")
            .join("fonts");
        let reg_font = fonts_dir.join("Roboto-Regular.ttf");
        let bold_font = fonts_dir.join("Roboto-Bold.ttf");
        let italic_font = fonts_dir.join("Roboto-Italic.ttf");
        let mono_font = fonts_dir.join("RobotoMono-Regular.ttf");

        // 1. XLSX mínimo válido para calamine -> CSV, JSON y PDF
        let xlsx_path = dir.join("datos.xlsx");
        write_zip_entries(
            &xlsx_path,
            &[
                (
                    "[Content_Types].xml",
                    br#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>"#,
                ),
                (
                    "_rels/.rels",
                    br#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>"#,
                ),
                (
                    "xl/workbook.xml",
                    br#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Ventas" sheetId="1" r:id="rId1"/></sheets>
</workbook>"#,
                ),
                (
                    "xl/_rels/workbook.xml.rels",
                    br#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>"#,
                ),
                (
                    "xl/worksheets/sheet1.xml",
                    br#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="inlineStr"><is><t>Producto</t></is></c><c r="B1"><v>100</v></c></row>
    <row r="2"><c r="A2" t="inlineStr"><is><t>Licencia Pro</t></is></c><c r="B2"><v>250</v></c></row>
  </sheetData>
</worksheet>"#,
                ),
            ],
        );

        let inspected = inspect_spreadsheet(&xlsx_path.to_string_lossy(), None).unwrap();
        assert_eq!(inspected.sheet_names, vec!["Ventas".to_string()]);
        assert_eq!(inspected.row_count, 2);

        let csv_out = dir.join("out.csv");
        convert_spreadsheet(
            &xlsx_path.to_string_lossy(),
            Some("Ventas"),
            "csv",
            &csv_out.to_string_lossy(),
            ",",
            "a4",
            "portrait",
            &reg_font.to_string_lossy(),
            &bold_font.to_string_lossy(),
        )
        .unwrap();
        assert!(std::fs::read_to_string(&csv_out).unwrap().contains("Licencia Pro,250"));

        let pdf_sheet = dir.join("sheet.pdf");
        convert_spreadsheet(
            &xlsx_path.to_string_lossy(),
            None,
            "pdf",
            &pdf_sheet.to_string_lossy(),
            ",",
            "a4",
            "landscape",
            &reg_font.to_string_lossy(),
            &bold_font.to_string_lossy(),
        )
        .unwrap();
        assert!(std::fs::read(&pdf_sheet).unwrap().starts_with(b"%PDF-1."));

        // 2. DOCX mínimo válido -> MD, TXT y PDF
        let docx_path = dir.join("contrato.docx");
        write_zip_entries(
            &docx_path,
            &[
                (
                    "[Content_Types].xml",
                    br#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>"#,
                ),
                (
                    "_rels/.rels",
                    br#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>"#,
                ),
                (
                    "word/document.xml",
                    br#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Resumen Anual</w:t></w:r></w:p>
    <w:p><w:r><w:b/><w:t>LocalConvert</w:t></w:r><w:r><w:t> funciona offline.</w:t></w:r></w:p>
  </w:body>
</w:document>"#,
                ),
            ],
        );

        let docx_info = inspect_docx(&docx_path.to_string_lossy()).unwrap();
        assert!(docx_info.preview_markdown.contains("# Resumen Anual"));

        let docx_md = dir.join("doc.md");
        convert_docx(
            &docx_path.to_string_lossy(),
            "md",
            &docx_md.to_string_lossy(),
            "a4",
            42.0,
            1.0,
            true,
            &reg_font.to_string_lossy(),
            &bold_font.to_string_lossy(),
            &italic_font.to_string_lossy(),
            &mono_font.to_string_lossy(),
        )
        .unwrap();
        assert!(std::fs::read_to_string(&docx_md).unwrap().contains("**LocalConvert** funciona offline."));

        let docx_pdf = dir.join("doc.pdf");
        convert_docx(
            &docx_path.to_string_lossy(),
            "pdf",
            &docx_pdf.to_string_lossy(),
            "a4",
            42.0,
            1.0,
            true,
            &reg_font.to_string_lossy(),
            &bold_font.to_string_lossy(),
            &italic_font.to_string_lossy(),
            &mono_font.to_string_lossy(),
        )
        .unwrap();
        assert!(std::fs::read(&docx_pdf).unwrap().starts_with(b"%PDF-1."));

        // 3. Estudio QR -> PNG, SVG y PDF imprimible
        let qr_dir = dir.join("qr_out");
        let qr_png = generate_qr_batch(
            &["https://localconvert.app".to_string(), "Wifi:LocalConvert".to_string()],
            &qr_dir.to_string_lossy(),
            "png",
            "M",
            256,
            true,
            &reg_font.to_string_lossy(),
            &bold_font.to_string_lossy(),
        )
        .unwrap();
        assert_eq!(qr_png.generated_count, 2);
        assert!(qr_png.zip_file_path.is_some());

        let qr_svg = generate_qr_batch(
            &["SoloSVG".to_string()],
            &qr_dir.to_string_lossy(),
            "svg",
            "H",
            256,
            false,
            &reg_font.to_string_lossy(),
            &bold_font.to_string_lossy(),
        )
        .unwrap();
        assert!(std::fs::read_to_string(&qr_svg.output_files[0]).unwrap().contains("<svg"));

        let qr_pdf = generate_qr_batch(
            &["Item PDF 1".to_string(), "Item PDF 2".to_string()],
            &qr_dir.to_string_lossy(),
            "pdf",
            "M",
            256,
            false,
            &reg_font.to_string_lossy(),
            &bold_font.to_string_lossy(),
        )
        .unwrap();
        assert!(std::fs::read(&qr_pdf.output_files[0]).unwrap().starts_with(b"%PDF-1."));

        let _ = std::fs::remove_dir_all(dir);
    }
}
