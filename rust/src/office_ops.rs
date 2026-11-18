use std::collections::BTreeMap;
use std::fs;
use std::io::{BufWriter, Cursor, Read};
use std::path::Path;

use calamine::{open_workbook_auto, Data, Reader};
use printpdf::{Color, Mm, PdfDocument, Rgb};
use quick_xml::events::Event;
use quick_xml::Reader as XmlReader;
use serde::Serialize;
use zip::ZipArchive;

use crate::pdf_gen::{fill_rect, markdown_to_pdf, measure_text_mm, pt_to_mm, wrap_text_lines};

#[derive(Debug, Serialize)]
pub struct SpreadsheetInspectResult {
    pub sheet_names: Vec<String>,
    pub active_sheet: String,
    pub row_count: usize,
    pub col_count: usize,
    pub headers: Vec<String>,
    pub preview_rows: Vec<Vec<String>>,
}

#[derive(Debug, Serialize)]
pub struct SpreadsheetConvertResult {
    pub output_path: String,
    pub sheet_name: String,
    pub row_count: usize,
    pub col_count: usize,
    pub output_bytes: usize,
}

#[derive(Debug, Serialize)]
pub struct DocxInspectResult {
    pub paragraph_count: usize,
    pub table_count: usize,
    pub preview_markdown: String,
}

#[derive(Debug, Serialize)]
pub struct DocxConvertResult {
    pub output_path: String,
    pub paragraph_count: usize,
    pub table_count: usize,
    pub output_bytes: usize,
}

fn cell_to_string(cell: &Data) -> String {
    match cell {
        Data::Empty => String::new(),
        Data::String(s) => s.clone(),
        Data::Int(v) => v.to_string(),
        Data::Float(v) => {
            if v.fract() == 0.0 && *v >= -9.0e15 && *v <= 9.0e15 {
                format!("{:.0}", v)
            } else {
                let s = format!("{:.6}", v);
                s.trim_end_matches('0').trim_end_matches('.').to_string()
            }
        }
        Data::Bool(b) => if *b { "true" } else { "false" }.to_string(),
        Data::DateTime(dt) => dt.to_string(),
        Data::DateTimeIso(s) | Data::DurationIso(s) => s.clone(),
        Data::Error(e) => format!("#ERR:{:?}", e),
    }
}

fn read_sheet_rows(
    file_path: &str,
    requested_sheet: Option<&str>,
) -> Result<(Vec<String>, String, Vec<Vec<String>>), String> {
    if !Path::new(file_path).exists() {
        return Err(format!("El archivo de hoja de cálculo no existe: {}", file_path));
    }

    let mut workbook = open_workbook_auto(file_path)
        .map_err(|e| format!("No se pudo abrir la hoja '{}': {}", file_path, e))?;

    let sheet_names = workbook.sheet_names();
    if sheet_names.is_empty() {
        return Err("El libro no contiene hojas de cálculo.".to_string());
    }

    let active_sheet = requested_sheet
        .and_then(|req| sheet_names.iter().find(|s| s.as_str() == req).cloned())
        .unwrap_or_else(|| sheet_names[0].clone());

    let range = workbook
        .worksheet_range(&active_sheet)
        .map_err(|e| format!("Error leyendo la hoja '{}': {}", active_sheet, e))?;

    let mut rows: Vec<Vec<String>> = Vec::with_capacity(range.height());
    let width = range.width();

    for row in range.rows() {
        let mut cells: Vec<String> = row.iter().map(cell_to_string).collect();
        while cells.len() < width {
            cells.push(String::new());
        }
        rows.push(cells);
    }

    // Recortar filas totalmente vacías al final
    while rows
        .last()
        .map(|r| r.iter().all(|c| c.trim().is_empty()))
        .unwrap_or(false)
    {
        rows.pop();
    }

    Ok((sheet_names, active_sheet, rows))
}

pub fn inspect_spreadsheet(
    file_path: &str,
    sheet_name: Option<&str>,
) -> Result<SpreadsheetInspectResult, String> {
    let (sheet_names, active_sheet, rows) = read_sheet_rows(file_path, sheet_name)?;
    let row_count = rows.len();
    let col_count = rows.iter().map(|r| r.len()).max().unwrap_or(0);
    let headers = rows.first().cloned().unwrap_or_default();
    let preview_rows = rows.iter().take(12).cloned().collect();

    Ok(SpreadsheetInspectResult {
        sheet_names,
        active_sheet,
        row_count,
        col_count,
        headers,
        preview_rows,
    })
}

fn escape_csv_cell(cell: &str, delimiter: char) -> String {
    if cell.contains(delimiter) || cell.contains('"') || cell.contains('\n') || cell.contains('\r') {
        format!("\"{}\"", cell.replace('"', "\"\""))
    } else {
        cell.to_string()
    }
}

fn normalize_headers(raw_headers: &[String], col_count: usize) -> Vec<String> {
    let mut used = BTreeMap::<String, usize>::new();
    let mut out = Vec::with_capacity(col_count);
    for idx in 0..col_count {
        let base = raw_headers
            .get(idx)
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string())
            .unwrap_or_else(|| format!("columna_{}", idx + 1));
        let count = used.entry(base.clone()).or_insert(0);
        *count += 1;
        if *count == 1 {
            out.push(base);
        } else {
            out.push(format!("{}_{}", base, *count));
        }
    }
    out
}

fn render_spreadsheet_pdf(
    rows: &[Vec<String>],
    sheet_title: &str,
    output_pdf_path: &str,
    page_size: &str,
    orientation: &str,
    regular_font_path: &str,
    bold_font_path: &str,
) -> Result<(), String> {
    let regular_bytes = fs::read(regular_font_path).map_err(|e| {
        format!(
            "No se pudo cargar fuente Regular '{}': {}",
            regular_font_path, e
        )
    })?;
    let bold_bytes = fs::read(bold_font_path).unwrap_or_else(|_| regular_bytes.clone());

    let (base_w, base_h) = if page_size == "letter" {
        (215.9f32, 279.4f32)
    } else {
        (210.0f32, 297.0f32)
    };
    let (page_w_mm, page_h_mm) = if orientation == "landscape" {
        (base_h, base_w)
    } else {
        (base_w, base_h)
    };

    let margin_mm = 14.0f32;
    let footer_mm = 9.0f32;
    let content_w = (page_w_mm - margin_mm * 2.0).max(40.0);

    let (doc, page1, layer1) = PdfDocument::new(sheet_title, Mm(page_w_mm), Mm(page_h_mm), "Layer 1");
    let doc = doc
        .with_producer("LocalConvert Rust Calamine Engine")
        .with_creator("LocalConvert");

    let reg_ref = doc
        .add_external_font(Cursor::new(regular_bytes.clone()))
        .map_err(|e| format!("Error fuente Regular TTF: {:?}", e))?;
    let bold_ref = doc
        .add_external_font(Cursor::new(bold_bytes.clone()))
        .map_err(|e| format!("Error fuente Bold TTF: {:?}", e))?;

    let mut pages = vec![(page1, layer1)];
    let mut cursor_y = page_h_mm - margin_mm;

    // Título de hoja
    {
        let layer = doc.get_page(page1).get_layer(layer1);
        layer.set_fill_color(Color::Rgb(Rgb::new(0.06, 0.09, 0.16, None)));
        layer.use_text(
            format!("Hoja: {}", sheet_title),
            13.5,
            Mm(margin_mm),
            Mm(cursor_y - pt_to_mm(13.5)),
            &bold_ref,
        );
    }
    cursor_y -= 9.0;

    let col_count = rows.iter().map(|r| r.len()).max().unwrap_or(1).max(1);
    let max_visible_cols = col_count.min(10);
    let col_w = content_w / (max_visible_cols as f32);
    let font_pt = if max_visible_cols >= 7 { 7.8 } else { 9.0 };
    let line_h_mm = pt_to_mm(font_pt) * 1.35;

    for (r_idx, row) in rows.iter().enumerate() {
        let is_header = r_idx == 0;
        let f_ref = if is_header { &bold_ref } else { &reg_ref };
        let f_bytes = if is_header { &bold_bytes } else { &regular_bytes };

        let mut cell_lines: Vec<Vec<String>> = Vec::with_capacity(max_visible_cols);
        let mut max_lines = 1usize;
        for c_idx in 0..max_visible_cols {
            let val = row.get(c_idx).map(|s| s.as_str()).unwrap_or("");
            let wrapped = wrap_text_lines(val, (col_w - 2.6).max(6.0), f_bytes, font_pt);
            let capped: Vec<String> = wrapped.into_iter().take(4).collect();
            max_lines = max_lines.max(capped.len().max(1));
            cell_lines.push(capped);
        }

        let row_h = (max_lines as f32) * line_h_mm + 2.6;
        if cursor_y - row_h < margin_mm + footer_mm {
            let next_p = doc.add_page(Mm(page_w_mm), Mm(page_h_mm), "Layer 1");
            pages.push(next_p);
            cursor_y = page_h_mm - margin_mm;
        }

        let &(p_idx, l_idx) = pages.last().unwrap();
        let layer = doc.get_page(p_idx).get_layer(l_idx);
        let row_bottom = cursor_y - row_h;

        let bg_color = if is_header {
            Rgb::new(0.06, 0.09, 0.16, None)
        } else if r_idx % 2 == 1 {
            Rgb::new(0.97, 0.98, 0.99, None)
        } else {
            Rgb::new(1.0, 1.0, 1.0, None)
        };
        fill_rect(&layer, margin_mm, row_bottom, content_w, row_h, bg_color);

        // Línea separadora inferior
        fill_rect(
            &layer,
            margin_mm,
            row_bottom,
            content_w,
            0.25,
            Rgb::new(0.84, 0.87, 0.91, None),
        );

        let txt_color = if is_header {
            Rgb::new(1.0, 1.0, 1.0, None)
        } else {
            Rgb::new(0.10, 0.13, 0.18, None)
        };

        for (c_idx, lines) in cell_lines.iter().enumerate() {
            let cx = margin_mm + (c_idx as f32) * col_w + 1.3;
            for (l_i, line_txt) in lines.iter().enumerate() {
                if line_txt.is_empty() {
                    continue;
                }
                let baseline = cursor_y - 1.4 - pt_to_mm(font_pt) - (l_i as f32) * line_h_mm;
                layer.set_fill_color(Color::Rgb(txt_color.clone()));
                layer.use_text(line_txt.clone(), font_pt, Mm(cx), Mm(baseline), f_ref);
            }
        }

        cursor_y = row_bottom;
    }

    let total_pages = pages.len();
    for (idx, &(p_idx, l_idx)) in pages.iter().enumerate() {
        let label = format!("Página {} de {}", idx + 1, total_pages);
        let lw = measure_text_mm(&regular_bytes, &label, 8.5);
        let layer = doc.get_page(p_idx).get_layer(l_idx);
        layer.set_fill_color(Color::Rgb(Rgb::new(0.45, 0.49, 0.56, None)));
        layer.use_text(
            label,
            8.5,
            Mm((page_w_mm - margin_mm - lw).max(margin_mm)),
            Mm(5.5),
            &reg_ref,
        );
    }

    if let Some(parent) = Path::new(output_pdf_path).parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Error creando directorio '{}': {}", parent.display(), e))?;
    }
    let out_file = fs::File::create(output_pdf_path)
        .map_err(|e| format!("No se pudo crear '{}': {}", output_pdf_path, e))?;
    let mut writer = BufWriter::new(out_file);
    doc.save(&mut writer)
        .map_err(|e| format!("Error guardando PDF de hoja: {:?}", e))?;
    Ok(())
}

#[allow(clippy::too_many_arguments)]
pub fn convert_spreadsheet(
    file_path: &str,
    sheet_name: Option<&str>,
    output_format: &str,
    output_path: &str,
    csv_delimiter: &str,
    page_size: &str,
    orientation: &str,
    regular_font_path: &str,
    bold_font_path: &str,
) -> Result<SpreadsheetConvertResult, String> {
    let (_, active_sheet, rows) = read_sheet_rows(file_path, sheet_name)?;
    let row_count = rows.len();
    let col_count = rows.iter().map(|r| r.len()).max().unwrap_or(0);

    if let Some(parent) = Path::new(output_path).parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Error creando directorio de salida: {}", e))?;
    }

    let fmt = output_format.trim().to_ascii_lowercase();
    match fmt.as_str() {
        "csv" => {
            let delim = csv_delimiter.chars().next().unwrap_or(',');
            let mut out = String::new();
            for row in &rows {
                let line = row
                    .iter()
                    .map(|c| escape_csv_cell(c, delim))
                    .collect::<Vec<_>>()
                    .join(&delim.to_string());
                out.push_str(&line);
                out.push('\n');
            }
            fs::write(output_path, out.as_bytes())
                .map_err(|e| format!("Error escribiendo CSV '{}': {}", output_path, e))?;
        }
        "json" => {
            let val = if rows.is_empty() {
                serde_json::Value::Array(vec![])
            } else if rows.len() == 1 {
                let headers = normalize_headers(&rows[0], col_count);
                serde_json::json!([headers
                    .into_iter()
                    .enumerate()
                    .map(|(i, k)| (k, serde_json::Value::String(rows[0].get(i).cloned().unwrap_or_default())))
                    .collect::<serde_json::Map<String, serde_json::Value>>()])
            } else {
                let headers = normalize_headers(&rows[0], col_count);
                let arr: Vec<serde_json::Value> = rows[1..]
                    .iter()
                    .map(|row| {
                        let mut obj = serde_json::Map::new();
                        for (idx, key) in headers.iter().enumerate() {
                            let val = row.get(idx).cloned().unwrap_or_default();
                            obj.insert(key.clone(), serde_json::Value::String(val));
                        }
                        serde_json::Value::Object(obj)
                    })
                    .collect();
                serde_json::Value::Array(arr)
            };
            let pretty = serde_json::to_string_pretty(&val)
                .map_err(|e| format!("Error serializando JSON: {}", e))?;
            fs::write(output_path, pretty.as_bytes())
                .map_err(|e| format!("Error escribiendo JSON '{}': {}", output_path, e))?;
        }
        "pdf" => {
            render_spreadsheet_pdf(
                &rows,
                &active_sheet,
                output_path,
                page_size,
                orientation,
                regular_font_path,
                bold_font_path,
            )?;
        }
        other => {
            return Err(format!("Formato destino de hoja no soportado: {}", other));
        }
    }

    let output_bytes = Path::new(output_path)
        .metadata()
        .map(|m| m.len() as usize)
        .unwrap_or(0);

    Ok(SpreadsheetConvertResult {
        output_path: output_path.to_string(),
        sheet_name: active_sheet,
        row_count,
        col_count,
        output_bytes,
    })
}

struct ParsedDocx {
    markdown: String,
    plain_text: String,
    paragraph_count: usize,
    table_count: usize,
}

fn parse_docx_file(file_path: &str) -> Result<ParsedDocx, String> {
    if !Path::new(file_path).exists() {
        return Err(format!("El archivo DOCX no existe: {}", file_path));
    }
    let file = fs::File::open(file_path)
        .map_err(|e| format!("No se pudo abrir '{}': {}", file_path, e))?;
    let mut archive = ZipArchive::new(file)
        .map_err(|e| format!("El archivo no es un contenedor DOCX válido: {}", e))?;

    let mut doc_xml = String::new();
    {
        let mut entry = archive
            .by_name("word/document.xml")
            .map_err(|_| "El archivo .docx no contiene 'word/document.xml'.".to_string())?;
        entry
            .read_to_string(&mut doc_xml)
            .map_err(|e| format!("Error leyendo 'word/document.xml': {}", e))?;
    }

    let mut reader = XmlReader::from_str(&doc_xml);
    reader.trim_text(false);

    let mut md_lines: Vec<String> = Vec::new();
    let mut txt_lines: Vec<String> = Vec::new();
    let mut paragraph_count = 0usize;
    let mut table_count = 0usize;

    let mut in_paragraph = false;
    let mut in_run = false;
    let mut in_text = false;
    let mut in_table = false;
    let mut in_row = false;
    let mut in_cell = false;

    let mut p_style = String::new();
    let mut is_list = false;
    let mut run_bold = false;
    let mut run_italic = false;

    let mut current_para_md = String::new();
    let mut current_para_txt = String::new();
    let mut current_run_text = String::new();
    let mut current_cell_text = String::new();
    let mut current_row_cells: Vec<String> = Vec::new();
    let mut current_table_rows: Vec<Vec<String>> = Vec::new();

    let flush_run = |run_text: &mut String,
                     bold: bool,
                     italic: bool,
                     in_tbl: bool,
                     para_md: &mut String,
                     para_txt: &mut String| {
        if run_text.is_empty() {
            return;
        }
        para_txt.push_str(run_text);
        if in_tbl {
            para_md.push_str(run_text);
        } else if bold && italic {
            para_md.push_str(&format!("***{}***", run_text.trim()));
            if run_text.ends_with(' ') {
                para_md.push(' ');
            }
        } else if bold {
            para_md.push_str(&format!("**{}**", run_text.trim()));
            if run_text.ends_with(' ') {
                para_md.push(' ');
            }
        } else if italic {
            para_md.push_str(&format!("*{}*", run_text.trim()));
            if run_text.ends_with(' ') {
                para_md.push(' ');
            }
        } else {
            para_md.push_str(run_text);
        }
        run_text.clear();
    };

    let mut buf = Vec::new();
    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(e)) => {
                let local = String::from_utf8_lossy(e.local_name().as_ref()).into_owned();
                match local.as_str() {
                    "tbl" => {
                        in_table = true;
                        current_table_rows.clear();
                    }
                    "tr" if in_table => {
                        in_row = true;
                        current_row_cells.clear();
                    }
                    "tc" if in_row => {
                        in_cell = true;
                        current_cell_text.clear();
                    }
                    "p" => {
                        in_paragraph = true;
                        p_style.clear();
                        is_list = false;
                        current_para_md.clear();
                        current_para_txt.clear();
                    }
                    "r" if in_paragraph => {
                        in_run = true;
                        run_bold = false;
                        run_italic = false;
                        current_run_text.clear();
                    }
                    "t" | "delText" if in_run => {
                        in_text = true;
                    }
                    "numPr" if in_paragraph => {
                        is_list = true;
                    }
                    _ => {}
                }
            }
            Ok(Event::Empty(e)) => {
                let local = String::from_utf8_lossy(e.local_name().as_ref()).into_owned();
                match local.as_str() {
                    "pStyle" if in_paragraph => {
                        for attr in e.attributes().flatten() {
                            let k = String::from_utf8_lossy(attr.key.local_name().as_ref()).into_owned();
                            if k == "val" {
                                p_style = String::from_utf8_lossy(&attr.value).into_owned();
                            }
                        }
                    }
                    "numPr" if in_paragraph => {
                        is_list = true;
                    }
                    "b" if in_run => {
                        let disabled = e.attributes().flatten().any(|a| {
                            a.key.local_name().as_ref() == b"val"
                                && (a.value.as_ref() == b"0" || a.value.as_ref() == b"false")
                        });
                        if !disabled {
                            run_bold = true;
                        }
                    }
                    "i" if in_run => {
                        let disabled = e.attributes().flatten().any(|a| {
                            a.key.local_name().as_ref() == b"val"
                                && (a.value.as_ref() == b"0" || a.value.as_ref() == b"false")
                        });
                        if !disabled {
                            run_italic = true;
                        }
                    }
                    "br" if in_run => {
                        current_run_text.push('\n');
                    }
                    "tab" if in_run => {
                        current_run_text.push('\t');
                    }
                    _ => {}
                }
            }
            Ok(Event::Text(e)) if in_text => {
                if let Ok(decoded) = e.unescape() {
                    current_run_text.push_str(&decoded);
                }
            }
            Ok(Event::End(e)) => {
                let local = String::from_utf8_lossy(e.local_name().as_ref()).into_owned();
                match local.as_str() {
                    "t" | "delText" => {
                        in_text = false;
                    }
                    "r" if in_run => {
                        flush_run(
                            &mut current_run_text,
                            run_bold,
                            run_italic,
                            in_table,
                            &mut current_para_md,
                            &mut current_para_txt,
                        );
                        in_run = false;
                    }
                    "p" if in_paragraph => {
                        let md_trimmed = current_para_md.trim().to_string();
                        let txt_trimmed = current_para_txt.trim().to_string();

                        if !txt_trimmed.is_empty() {
                            if in_cell {
                                if !current_cell_text.is_empty() {
                                    current_cell_text.push(' ');
                                }
                                current_cell_text.push_str(&txt_trimmed);
                            } else {
                                paragraph_count += 1;
                                let style_lower = p_style.to_ascii_lowercase();
                                let md_formatted = if style_lower == "title"
                                    || style_lower.starts_with("heading1")
                                    || style_lower == "título1"
                                {
                                    format!("# {}", txt_trimmed)
                                } else if style_lower == "subtitle"
                                    || style_lower.starts_with("heading2")
                                    || style_lower == "título2"
                                {
                                    format!("## {}", txt_trimmed)
                                } else if style_lower.starts_with("heading") {
                                    format!("### {}", txt_trimmed)
                                } else if style_lower.contains("quote") {
                                    format!("> {}", md_trimmed)
                                } else if is_list || style_lower.contains("list") {
                                    format!("- {}", md_trimmed)
                                } else {
                                    md_trimmed
                                };
                                md_lines.push(md_formatted);
                                md_lines.push(String::new());
                                txt_lines.push(txt_trimmed);
                                txt_lines.push(String::new());
                            }
                        }
                        in_paragraph = false;
                    }
                    "tc" if in_cell => {
                        current_row_cells.push(current_cell_text.trim().replace('|', "\\|"));
                        in_cell = false;
                    }
                    "tr" if in_row => {
                        if !current_row_cells.is_empty() {
                            current_table_rows.push(current_row_cells.clone());
                        }
                        in_row = false;
                    }
                    "tbl" if in_table => {
                        if !current_table_rows.is_empty() {
                            table_count += 1;
                            let cols = current_table_rows.iter().map(|r| r.len()).max().unwrap_or(1);
                            for (r_i, row) in current_table_rows.iter().enumerate() {
                                let mut padded = row.clone();
                                while padded.len() < cols {
                                    padded.push(String::new());
                                }
                                md_lines.push(format!("| {} |", padded.join(" | ")));
                                txt_lines.push(padded.join(" | "));
                                if r_i == 0 {
                                    md_lines.push(format!("| {} |", vec!["---"; cols].join(" | ")));
                                }
                            }
                            md_lines.push(String::new());
                            txt_lines.push(String::new());
                        }
                        in_table = false;
                    }
                    _ => {}
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => return Err(format!("Error XML en DOCX: {}", e)),
            _ => {}
        }
        buf.clear();
    }

    let markdown = md_lines.join("\n").trim().to_string();
    let plain_text = txt_lines.join("\n").trim().to_string();

    Ok(ParsedDocx {
        markdown,
        plain_text,
        paragraph_count,
        table_count,
    })
}

pub fn inspect_docx(file_path: &str) -> Result<DocxInspectResult, String> {
    let parsed = parse_docx_file(file_path)?;
    let preview = parsed.markdown.chars().take(1800).collect::<String>();
    Ok(DocxInspectResult {
        paragraph_count: parsed.paragraph_count,
        table_count: parsed.table_count,
        preview_markdown: preview,
    })
}

#[allow(clippy::too_many_arguments)]
pub fn convert_docx(
    file_path: &str,
    output_format: &str,
    output_path: &str,
    page_size: &str,
    margin_points: f32,
    font_scale: f32,
    show_page_numbers: bool,
    regular_font_path: &str,
    bold_font_path: &str,
    italic_font_path: &str,
    mono_font_path: &str,
) -> Result<DocxConvertResult, String> {
    let parsed = parse_docx_file(file_path)?;
    if parsed.markdown.trim().is_empty() {
        return Err("El documento .docx no contiene texto extraíble.".to_string());
    }

    if let Some(parent) = Path::new(output_path).parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Error creando directorio de salida: {}", e))?;
    }

    let fmt = output_format.trim().to_ascii_lowercase();
    match fmt.as_str() {
        "md" | "markdown" => {
            fs::write(output_path, parsed.markdown.as_bytes())
                .map_err(|e| format!("Error guardando Markdown '{}': {}", output_path, e))?;
        }
        "txt" | "text" => {
            fs::write(output_path, parsed.plain_text.as_bytes())
                .map_err(|e| format!("Error guardando TXT '{}': {}", output_path, e))?;
        }
        "pdf" => {
            let doc_title = Path::new(file_path)
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("Documento DOCX");
            markdown_to_pdf(
                &parsed.markdown,
                doc_title,
                true,
                output_path,
                page_size,
                margin_points,
                font_scale,
                show_page_numbers,
                regular_font_path,
                bold_font_path,
                italic_font_path,
                mono_font_path,
            )?;
        }
        other => {
            return Err(format!("Formato destino DOCX no soportado: {}", other));
        }
    }

    let output_bytes = Path::new(output_path)
        .metadata()
        .map(|m| m.len() as usize)
        .unwrap_or(0);

    Ok(DocxConvertResult {
        output_path: output_path.to_string(),
        paragraph_count: parsed.paragraph_count,
        table_count: parsed.table_count,
        output_bytes,
    })
}
