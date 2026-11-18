use std::fs;
use std::io::Cursor;
use std::path::Path;

use image::imageops::FilterType;
use image::{DynamicImage, ImageFormat, Rgba, RgbaImage};
use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct GeneratedIconsResult {
    pub ico_path: String,
    pub png_path: String,
    pub sizes: Vec<u32>,
}

#[inline]
fn blend_pixel(dst: &mut Rgba<u8>, src: Rgba<u8>) {
    let sa = src.0[3] as f32 / 255.0;
    if sa <= 0.0 {
        return;
    }
    if sa >= 1.0 || dst.0[3] == 0 {
        *dst = src;
        return;
    }
    let da = dst.0[3] as f32 / 255.0;
    let out_a = sa + da * (1.0 - sa);
    if out_a <= 0.0 {
        return;
    }
    for c in 0..3 {
        let s = src.0[c] as f32;
        let d = dst.0[c] as f32;
        dst.0[c] = ((s * sa + d * da * (1.0 - sa)) / out_a)
            .round()
            .clamp(0.0, 255.0) as u8;
    }
    dst.0[3] = (out_a * 255.0).round().clamp(0.0, 255.0) as u8;
}

fn signed_rounded_rect_dist(x: f32, y: f32, x0: f32, y0: f32, x1: f32, y1: f32, r: f32) -> f32 {
    let cx = (x0 + x1) * 0.5;
    let cy = (y0 + y1) * 0.5;
    let hx = (x1 - x0) * 0.5 - r;
    let hy = (y1 - y0) * 0.5 - r;
    let dx = (x - cx).abs() - hx;
    let dy = (y - cy).abs() - hy;
    let out = (dx.max(0.0).powi(2) + dy.max(0.0).powi(2)).sqrt();
    let inside = dx.max(dy).min(0.0);
    out + inside - r
}

fn fill_aa_rounded_rect(
    img: &mut RgbaImage,
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
    r: f32,
    color_fn: impl Fn(f32, f32) -> Rgba<u8>,
) {
    let (w, h) = img.dimensions();
    let min_x = (x0.floor() as i32 - 2).max(0) as u32;
    let max_x = (x1.ceil() as i32 + 2).min(w as i32 - 1) as u32;
    let min_y = (y0.floor() as i32 - 2).max(0) as u32;
    let max_y = (y1.ceil() as i32 + 2).min(h as i32 - 1) as u32;

    for y in min_y..=max_y {
        for x in min_x..=max_x {
            let d = signed_rounded_rect_dist(x as f32 + 0.5, y as f32 + 0.5, x0, y0, x1, y1, r);
            if d < 1.0 {
                let coverage = (0.5 - d).clamp(0.0, 1.0);
                if coverage > 0.0 {
                    let mut c = color_fn(x as f32 + 0.5, y as f32 + 0.5);
                    c.0[3] = ((c.0[3] as f32) * coverage).round() as u8;
                    blend_pixel(img.get_pixel_mut(x, y), c);
                }
            }
        }
    }
}

fn point_to_segment_dist(px: f32, py: f32, ax: f32, ay: f32, bx: f32, by: f32) -> f32 {
    let vx = bx - ax;
    let vy = by - ay;
    let wx = px - ax;
    let wy = py - ay;
    let len_sq = vx * vx + vy * vy;
    let t = if len_sq > 1e-6 {
        ((wx * vx + wy * vy) / len_sq).clamp(0.0, 1.0)
    } else {
        0.0
    };
    let dx = px - (ax + t * vx);
    let dy = py - (ay + t * vy);
    (dx * dx + dy * dy).sqrt()
}

fn draw_aa_capsule(
    img: &mut RgbaImage,
    ax: f32,
    ay: f32,
    bx: f32,
    by: f32,
    radius: f32,
    color: Rgba<u8>,
) {
    let (w, h) = img.dimensions();
    let pad = radius + 2.0;
    let min_x = ((ax.min(bx) - pad).floor() as i32).max(0) as u32;
    let max_x = ((ax.max(bx) + pad).ceil() as i32).min(w as i32 - 1) as u32;
    let min_y = ((ay.min(by) - pad).floor() as i32).max(0) as u32;
    let max_y = ((ay.max(by) + pad).ceil() as i32).min(h as i32 - 1) as u32;

    for y in min_y..=max_y {
        for x in min_x..=max_x {
            let d = point_to_segment_dist(x as f32 + 0.5, y as f32 + 0.5, ax, ay, bx, by) - radius;
            if d < 1.0 {
                let coverage = (0.5 - d).clamp(0.0, 1.0);
                if coverage > 0.0 {
                    let mut c = color;
                    c.0[3] = ((c.0[3] as f32) * coverage).round() as u8;
                    blend_pixel(img.get_pixel_mut(x, y), c);
                }
            }
        }
    }
}

fn draw_aa_circle(img: &mut RgbaImage, cx: f32, cy: f32, radius: f32, color: Rgba<u8>) {
    let (w, h) = img.dimensions();
    let pad = radius + 2.0;
    let min_x = ((cx - pad).floor() as i32).max(0) as u32;
    let max_x = ((cx + pad).ceil() as i32).min(w as i32 - 1) as u32;
    let min_y = ((cy - pad).floor() as i32).max(0) as u32;
    let max_y = ((cy + pad).ceil() as i32).min(h as i32 - 1) as u32;

    for y in min_y..=max_y {
        for x in min_x..=max_x {
            let dx = x as f32 + 0.5 - cx;
            let dy = y as f32 + 0.5 - cy;
            let d = (dx * dx + dy * dy).sqrt() - radius;
            if d < 1.0 {
                let coverage = (0.5 - d).clamp(0.0, 1.0);
                if coverage > 0.0 {
                    let mut c = color;
                    c.0[3] = ((c.0[3] as f32) * coverage).round() as u8;
                    blend_pixel(img.get_pixel_mut(x, y), c);
                }
            }
        }
    }
}

/// Renderiza el ícono maestro de LocalConvert a 512x512 y lo escala con Lanczos3.
pub fn render_master_brand_icon(target_size: u32) -> DynamicImage {
    let size = 512u32;
    let mut canvas = RgbaImage::new(size, size);

    // 1. Squircle exterior con gradiente pizarra oscuro (#0F172A -> #1E293B) + acento sutil
    fill_aa_rounded_rect(&mut canvas, 20.0, 20.0, 492.0, 492.0, 112.0, |x, y| {
        let t = ((x + y) / 1024.0).clamp(0.0, 1.0);
        let r = (15.0 + t * 20.0).round() as u8;
        let g = (23.0 + t * 24.0).round() as u8;
        let b = (42.0 + t * 34.0).round() as u8;
        Rgba([r, g, b, 255])
    });

    // Borde luminoso interior discreto
    fill_aa_rounded_rect(&mut canvas, 26.0, 26.0, 486.0, 486.0, 106.0, |_, y| {
        let alpha = if y < 220.0 { 22 } else { 10 };
        Rgba([255, 255, 255, alpha])
    });
    fill_aa_rounded_rect(&mut canvas, 30.0, 30.0, 482.0, 482.0, 102.0, |x, y| {
        let t = ((x + y) / 1024.0).clamp(0.0, 1.0);
        let r = (15.0 + t * 18.0).round() as u8;
        let g = (23.0 + t * 22.0).round() as u8;
        let b = (42.0 + t * 32.0).round() as u8;
        Rgba([r, g, b, 255])
    });

    // 2. Tarjeta trasera desplazada (capa de conversión de archivos, tono coral #E5322D)
    fill_aa_rounded_rect(&mut canvas, 112.0, 96.0, 338.0, 366.0, 32.0, |_, y| {
        let t = ((y - 96.0) / 270.0).clamp(0.0, 1.0);
        let r = (239.0 - t * 20.0).round() as u8;
        let g = (68.0 - t * 18.0).round() as u8;
        let b = (68.0 - t * 20.0).round() as u8;
        Rgba([r, g, b, 255])
    });

    // 3. Documento principal blanco superpuesto (#F8FAFC)
    fill_aa_rounded_rect(&mut canvas, 152.0, 134.0, 396.0, 412.0, 32.0, |_, y| {
        let t = ((y - 134.0) / 278.0).clamp(0.0, 1.0);
        let v = (255.0 - t * 10.0).round() as u8;
        Rgba([v, v, (v as u16 + 3).min(255) as u8, 255])
    });

    // Esquina superior derecha doblada del documento (#CBD5E1)
    let fold_min = 328.0f32;
    for y in 134..206 {
        for x in 328..397 {
            let fx = x as f32 + 0.5;
            let fy = y as f32 + 0.5;
            // Triángulo inferior-izquierda de la esquina doblada
            if fx >= fold_min && fy <= 202.0 && (fx - fold_min) + (202.0 - fy) <= 72.0 {
                blend_pixel(canvas.get_pixel_mut(x, y), Rgba([203, 213, 225, 255]));
            }
        }
    }

    // 4. Líneas geométricas de contenido en la parte superior del documento
    draw_aa_capsule(&mut canvas, 194.0, 190.0, 294.0, 190.0, 9.0, Rgba([148, 163, 184, 255]));
    draw_aa_capsule(&mut canvas, 194.0, 226.0, 344.0, 226.0, 9.0, Rgba([203, 213, 225, 255]));

    // 5. Flechas bidireccionales de conversión (Coral -> derecha y Teal <- izquierda)
    let coral = Rgba([229, 50, 45, 255]);
    draw_aa_capsule(&mut canvas, 196.0, 286.0, 342.0, 286.0, 12.0, coral);
    draw_aa_capsule(&mut canvas, 312.0, 256.0, 346.0, 286.0, 11.0, coral);
    draw_aa_capsule(&mut canvas, 312.0, 316.0, 346.0, 286.0, 11.0, coral);

    let teal = Rgba([13, 148, 136, 255]);
    draw_aa_capsule(&mut canvas, 200.0, 352.0, 346.0, 352.0, 12.0, teal);
    draw_aa_capsule(&mut canvas, 230.0, 322.0, 196.0, 352.0, 11.0, teal);
    draw_aa_capsule(&mut canvas, 230.0, 382.0, 196.0, 352.0, 11.0, teal);

    // 6. Sello circular verde esmeralda de privacidad 100% offline (#10B981)
    draw_aa_circle(&mut canvas, 396.0, 392.0, 58.0, Rgba([15, 23, 42, 255]));
    draw_aa_circle(&mut canvas, 396.0, 392.0, 48.0, Rgba([16, 185, 129, 255]));
    let white = Rgba([255, 255, 255, 255]);
    draw_aa_capsule(&mut canvas, 374.0, 394.0, 391.0, 412.0, 7.5, white);
    draw_aa_capsule(&mut canvas, 391.0, 412.0, 421.0, 374.0, 7.5, white);

    let dyn_img = DynamicImage::ImageRgba8(canvas);
    if target_size == 512 {
        dyn_img
    } else {
        dyn_img.resize_exact(target_size, target_size, FilterType::Lanczos3)
    }
}

/// Construye una entrada DIB clásica (BITMAPINFOHEADER de 40 bytes + píxeles BGRA
/// invertidos verticalmente + máscara AND a 1bpp) compatible con `rc.exe` y Explorer.
fn build_bmp_dib_frame(rgba: &RgbaImage) -> Vec<u8> {
    let (w, h) = rgba.dimensions();
    let and_row_bytes = (((w + 31) / 32) * 4) as usize;
    let and_mask_size = and_row_bytes * (h as usize);
    let xor_size = (w as usize) * (h as usize) * 4;
    let mut out = Vec::with_capacity(40 + xor_size + and_mask_size);

    // BITMAPINFOHEADER (40 bytes)
    out.extend_from_slice(&40u32.to_le_bytes()); // biSize
    out.extend_from_slice(&(w as i32).to_le_bytes()); // biWidth
    out.extend_from_slice(&((h * 2) as i32).to_le_bytes()); // biHeight (XOR + AND)
    out.extend_from_slice(&1u16.to_le_bytes()); // biPlanes
    out.extend_from_slice(&32u16.to_le_bytes()); // biBitCount (BGRA 32bpp)
    out.extend_from_slice(&0u32.to_le_bytes()); // biCompression = BI_RGB
    out.extend_from_slice(&(xor_size as u32).to_le_bytes()); // biSizeImage
    out.extend_from_slice(&0i32.to_le_bytes()); // biXPelsPerMeter
    out.extend_from_slice(&0i32.to_le_bytes()); // biYPelsPerMeter
    out.extend_from_slice(&0u32.to_le_bytes()); // biClrUsed
    out.extend_from_slice(&0u32.to_le_bytes()); // biClrImportant

    // Píxeles bottom-up en orden B, G, R, A
    for y in (0..h).rev() {
        for x in 0..w {
            let [r, g, b, a] = rgba.get_pixel(x, y).0;
            out.push(b);
            out.push(g);
            out.push(r);
            out.push(a);
        }
    }

    // Máscara AND (1 bit donde alfa == 0)
    for y in (0..h).rev() {
        for byte_idx in 0..and_row_bytes {
            let mut mask_byte = 0u8;
            for bit in 0..8 {
                let x = (byte_idx * 8 + bit) as u32;
                if x < w && rgba.get_pixel(x, y).0[3] < 16 {
                    mask_byte |= 1 << (7 - bit);
                }
            }
            out.push(mask_byte);
        }
    }

    out
}

/// Exporta `windows/runner/resources/app_icon.ico` multicapa (`16`, `32`, `48`,
/// `64`, `128`, `256`) y `assets/icons/app_icon.png` (`256x256`).
pub fn generate_app_icons(
    ico_output_path: &str,
    png_output_path: &str,
) -> Result<GeneratedIconsResult, String> {
    let sizes = [16u32, 32, 48, 64, 128, 256];
    let mut frames_bytes: Vec<(u32, Vec<u8>)> = Vec::with_capacity(sizes.len());
    let mut png_256: Option<Vec<u8>> = None;

    for &sz in &sizes {
        let scaled = render_master_brand_icon(sz);
        if sz == 256 {
            let mut png_buf = Vec::new();
            scaled
                .write_to(&mut Cursor::new(&mut png_buf), ImageFormat::Png)
                .map_err(|e| format!("Error codificando app_icon.png 256x256: {}", e))?;
            png_256 = Some(png_buf.clone());
            frames_bytes.push((sz, png_buf));
        } else {
            frames_bytes.push((sz, build_bmp_dib_frame(&scaled.to_rgba8())));
        }
    }

    // Construir cabecera ICONDIR + ICONDIRENTRY
    let count = frames_bytes.len() as u16;
    let mut ico_bytes = Vec::new();
    ico_bytes.extend_from_slice(&0u16.to_le_bytes()); // Reserved
    ico_bytes.extend_from_slice(&1u16.to_le_bytes()); // Type 1 = ICO
    ico_bytes.extend_from_slice(&count.to_le_bytes());

    let mut offset = 6u32 + (count as u32) * 16u32;
    for (sz, data) in &frames_bytes {
        let dim_byte: u8 = if *sz >= 256 { 0 } else { *sz as u8 };
        ico_bytes.push(dim_byte); // bWidth
        ico_bytes.push(dim_byte); // bHeight
        ico_bytes.push(0); // bColorCount
        ico_bytes.push(0); // bReserved
        ico_bytes.extend_from_slice(&1u16.to_le_bytes()); // wPlanes
        ico_bytes.extend_from_slice(&32u16.to_le_bytes()); // wBitCount
        ico_bytes.extend_from_slice(&(data.len() as u32).to_le_bytes()); // dwBytesInRes
        ico_bytes.extend_from_slice(&offset.to_le_bytes()); // dwImageOffset
        offset += data.len() as u32;
    }

    for (_, data) in &frames_bytes {
        ico_bytes.extend_from_slice(data);
    }

    if let Some(parent) = Path::new(ico_output_path).parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Error creando carpeta de icono .ico: {}", e))?;
    }
    fs::write(ico_output_path, &ico_bytes)
        .map_err(|e| format!("Error escribiendo '{}': {}", ico_output_path, e))?;

    if let Some(parent) = Path::new(png_output_path).parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("Error creando carpeta de icono .png: {}", e))?;
    }
    if let Some(png_bytes) = png_256 {
        fs::write(png_output_path, &png_bytes)
            .map_err(|e| format!("Error escribiendo '{}': {}", png_output_path, e))?;
    }

    Ok(GeneratedIconsResult {
        ico_path: ico_output_path.to_string(),
        png_path: png_output_path.to_string(),
        sizes: sizes.to_vec(),
    })
}
