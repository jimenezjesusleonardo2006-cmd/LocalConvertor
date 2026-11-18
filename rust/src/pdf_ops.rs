use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::Cursor;
use std::path::Path;

use lopdf::{Dictionary, Document, Object, ObjectId};
use rayon::prelude::*;
use serde::Deserialize;
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipWriter};

#[derive(Debug, Deserialize)]
pub struct SplitSegmentInput {
    pub label: String,
    pub pages: Vec<u32>,
}

fn load_and_prepare_pdf(path: &str) -> Result<Document, String> {
    let mut doc = Document::load(path)
        .map_err(|e| format!("No se pudo leer el PDF '{}': {}", path, e))?;

    if doc.is_encrypted() {
        doc.decrypt("")
            .map_err(|e| format!("El PDF '{}' está protegido con contraseña ({}).", path, e))?;
    }

    materialize_inherited_page_attributes(&mut doc);
    Ok(doc)
}

/// Copia en cada diccionario `/Page` los atributos heredables (`/Resources`,
/// `/MediaBox`, `/CropBox`, `/Rotate`) provenientes de sus ancestros `/Pages`
/// antes de aplanar o reordenar el árbol de páginas.
fn materialize_inherited_page_attributes(doc: &mut Document) {
    let page_ids: Vec<ObjectId> = doc.get_pages().into_values().collect();
    const INHERITABLE_KEYS: [&[u8]; 4] = [b"Resources", b"MediaBox", b"CropBox", b"Rotate"];

    for page_id in page_ids {
        let mut ancestors: Vec<ObjectId> = Vec::new();
        let mut visited: HashSet<ObjectId> = HashSet::new();
        visited.insert(page_id);

        let mut cursor = page_id;
        while let Ok(dict) = doc.get_dictionary(cursor) {
            match dict.get(b"Parent").and_then(Object::as_reference) {
                Ok(parent_id) if visited.insert(parent_id) => {
                    ancestors.push(parent_id);
                    cursor = parent_id;
                }
                _ => break,
            }
        }

        let mut resolved: Vec<(&[u8], Object)> = Vec::new();
        if let Ok(page_dict) = doc.get_dictionary(page_id) {
            for &key in &INHERITABLE_KEYS {
                if page_dict.has(key) {
                    continue;
                }
                for &ancestor_id in &ancestors {
                    if let Ok(anc_dict) = doc.get_dictionary(ancestor_id) {
                        if let Ok(val) = anc_dict.get(key) {
                            resolved.push((key, val.clone()));
                            break;
                        }
                    }
                }
            }
        }

        if !resolved.is_empty() {
            if let Ok(page_dict_mut) = doc.get_dictionary_mut(page_id) {
                for (key, val) in resolved {
                    page_dict_mut.set(key, val);
                }
            }
        }
    }
}

/// Fusiona múltiples PDFs conservando el árbol estructural de objetos, texto
/// seleccionable, fuentes y vectores sin rasterizar páginas.
pub fn merge_pdfs(
    input_paths: &[String],
    output_pdf_path: &str,
    _quality_preset: &str,
) -> Result<usize, String> {
    if input_paths.is_empty() {
        return Err("No se proporcionaron documentos PDF para unir.".to_string());
    }

    let mut target_doc = Document::with_version("1.5");
    let mut next_id: u32 = 1;
    let mut ordered_pages: Vec<(ObjectId, Dictionary)> = Vec::new();

    for path in input_paths {
        if !Path::new(path).exists() {
            return Err(format!("El documento PDF no fue encontrado: {}", path));
        }

        let mut src = load_and_prepare_pdf(path)?;
        src.renumber_objects_with(next_id);
        next_id = src.max_id.saturating_add(1);

        let src_pages = src.get_pages();
        for (_, page_id) in src_pages {
            if let Ok(page_dict) = src.get_dictionary(page_id) {
                ordered_pages.push((page_id, page_dict.clone()));
            }
        }

        for (obj_id, obj) in src.objects {
            match obj.type_name().unwrap_or("") {
                "Catalog" | "Pages" | "Page" | "Outlines" | "Outline" => {}
                _ => {
                    target_doc.objects.insert(obj_id, obj);
                }
            }
        }
    }

    let total_pages = ordered_pages.len();
    if total_pages == 0 {
        return Err("Los documentos seleccionados no contienen páginas válidas.".to_string());
    }

    target_doc.max_id = next_id.saturating_sub(1);
    let pages_id = target_doc.new_object_id();
    let catalog_id = target_doc.new_object_id();

    let mut kids: Vec<Object> = Vec::with_capacity(total_pages);
    for (page_id, mut page_dict) in ordered_pages {
        page_dict.set("Parent", Object::Reference(pages_id));
        page_dict.remove(b"B");
        target_doc
            .objects
            .insert(page_id, Object::Dictionary(page_dict));
        kids.push(Object::Reference(page_id));
    }

    let mut pages_dict = Dictionary::new();
    pages_dict.set("Type", Object::Name(b"Pages".to_vec()));
    pages_dict.set("Count", Object::Integer(total_pages as i64));
    pages_dict.set("Kids", Object::Array(kids));
    target_doc
        .objects
        .insert(pages_id, Object::Dictionary(pages_dict));

    let mut catalog_dict = Dictionary::new();
    catalog_dict.set("Type", Object::Name(b"Catalog".to_vec()));
    catalog_dict.set("Pages", Object::Reference(pages_id));
    catalog_dict.set("PageLayout", Object::Name(b"OneColumn".to_vec()));
    target_doc
        .objects
        .insert(catalog_id, Object::Dictionary(catalog_dict));

    target_doc.trailer.set("Root", Object::Reference(catalog_id));
    target_doc.prune_objects();
    target_doc.renumber_objects();
    let _ = target_doc.compress();

    if let Some(parent) = Path::new(output_pdf_path).parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("No se pudo crear la carpeta de salida: {}", e))?;
    }

    target_doc
        .save(output_pdf_path)
        .map_err(|e| format!("Error al guardar PDF combinado: {}", e))?;

    Ok(total_pages)
}

fn extract_pages_document(
    source_doc: &Document,
    page_numbers_1based: &[u32],
) -> Result<Document, String> {
    if page_numbers_1based.is_empty() {
        return Err("El segmento no contiene páginas para extraer.".to_string());
    }

    let mut doc = source_doc.clone();
    let all_pages = doc.get_pages();
    let mut new_kids: Vec<Object> = Vec::with_capacity(page_numbers_1based.len());
    let mut used_ids: HashMap<ObjectId, usize> = HashMap::new();

    let pages_id = doc.new_object_id();
    let catalog_id = doc.new_object_id();

    for &page_num in page_numbers_1based {
        let orig_page_id = *all_pages.get(&page_num).ok_or_else(|| {
            format!("La página {} excede el total de páginas del PDF.", page_num)
        })?;

        let mut page_dict = doc
            .get_dictionary(orig_page_id)
            .map_err(|e| format!("Error leyendo diccionario de página {}: {}", page_num, e))?
            .clone();
        page_dict.set("Parent", Object::Reference(pages_id));
        page_dict.remove(b"B");

        let count = used_ids.entry(orig_page_id).or_insert(0);
        *count += 1;

        let target_page_id = if *count == 1 {
            orig_page_id
        } else {
            doc.new_object_id()
        };

        doc.objects
            .insert(target_page_id, Object::Dictionary(page_dict));
        new_kids.push(Object::Reference(target_page_id));
    }

    let mut pages_dict = Dictionary::new();
    pages_dict.set("Type", Object::Name(b"Pages".to_vec()));
    pages_dict.set("Count", Object::Integer(new_kids.len() as i64));
    pages_dict.set("Kids", Object::Array(new_kids));
    doc.objects.insert(pages_id, Object::Dictionary(pages_dict));

    let mut catalog_dict = Dictionary::new();
    catalog_dict.set("Type", Object::Name(b"Catalog".to_vec()));
    catalog_dict.set("Pages", Object::Reference(pages_id));
    catalog_dict.set("PageLayout", Object::Name(b"OneColumn".to_vec()));
    doc.objects
        .insert(catalog_id, Object::Dictionary(catalog_dict));

    doc.trailer.set("Root", Object::Reference(catalog_id));
    doc.prune_objects();
    doc.renumber_objects();
    let _ = doc.compress();

    Ok(doc)
}

/// Extrae páginas o rangos conservando texto y vectores originales mediante `lopdf`.
pub fn split_pdf(
    source_pdf_path: &str,
    output_mode: &str,
    output_path: &str,
    base_name: &str,
    segments: &[SplitSegmentInput],
) -> Result<usize, String> {
    if !Path::new(source_pdf_path).exists() {
        return Err(format!("El archivo PDF de origen no existe: {}", source_pdf_path));
    }
    if segments.is_empty() {
        return Err("No se especificaron rangos válidos para dividir.".to_string());
    }

    let source_doc = load_and_prepare_pdf(source_pdf_path)?;
    if let Some(parent) = Path::new(output_path).parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("No se pudo crear el directorio de salida: {}", e))?;
    }

    if output_mode == "single_combined_pdf" {
        let mut flat_pages: Vec<u32> = Vec::new();
        for seg in segments {
            flat_pages.extend(seg.pages.iter().copied());
        }
        let mut out_doc = extract_pages_document(&source_doc, &flat_pages)?;
        out_doc
            .save(output_path)
            .map_err(|e| format!("Error al guardar PDF dividido: {}", e))?;
        Ok(flat_pages.len())
    } else {
        let rendered_segments: Result<Vec<(String, Vec<u8>, usize)>, String> = segments
            .par_iter()
            .map(|seg| {
                let mut seg_doc = extract_pages_document(&source_doc, &seg.pages)?;
                let mut cursor = Cursor::new(Vec::new());
                seg_doc
                    .save_to(&mut cursor)
                    .map_err(|e| format!("Error serializando segmento {}: {}", seg.label, e))?;
                let entry_name = format!("{}_{}.pdf", base_name, seg.label);
                Ok((entry_name, cursor.into_inner(), seg.pages.len()))
            })
            .collect();

        let rendered = rendered_segments?;
        let zip_file = fs::File::create(output_path)
            .map_err(|e| format!("Error al crear ZIP '{}': {}", output_path, e))?;
        let mut zip = ZipWriter::new(zip_file);
        let options = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);

        let mut total_pages = 0usize;
        for (entry_name, pdf_bytes, page_count) in rendered {
            total_pages += page_count;
            zip.start_file(&entry_name, options)
                .map_err(|e| format!("Error añadiendo {} al ZIP: {}", entry_name, e))?;
            std::io::Write::write_all(&mut zip, &pdf_bytes)
                .map_err(|e| format!("Error escribiendo {} en el ZIP: {}", entry_name, e))?;
        }

        zip.finish()
            .map_err(|e| format!("Error finalizando archivo ZIP: {}", e))?;
        Ok(total_pages)
    }
}
