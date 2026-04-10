use brotli::enc::backward_references::BrotliEncoderParams;
use std::fs::File;
use std::io::{BufWriter, Cursor};
use std::path::PathBuf;

fn main() {
    let mut args = std::env::args().skip(1);
    let input = PathBuf::from(args.next().expect("missing input path"));
    let output = PathBuf::from(args.next().expect("missing output path"));
    let quality = args
        .next()
        .map(|value| value.parse::<i32>().expect("invalid Brotli quality"))
        .unwrap_or(2);
    assert!(
        args.next().is_none(),
        "expected arguments: <input> <output> [quality]"
    );

    let bytes = std::fs::read(&input)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", input.display()));
    if let Some(parent) = output.parent() {
        std::fs::create_dir_all(parent)
            .unwrap_or_else(|error| panic!("failed to create {}: {error}", parent.display()));
    }

    let mut params = BrotliEncoderParams::default();
    params.quality = quality;

    let file = File::create(&output)
        .unwrap_or_else(|error| panic!("failed to create {}: {error}", output.display()));
    let mut writer = BufWriter::new(file);
    let mut cursor = Cursor::new(bytes);
    brotli::BrotliCompress(&mut cursor, &mut writer, &params)
        .unwrap_or_else(|error| panic!("failed to write {}: {error}", output.display()));
}
