use anyhow::{bail, Context, Result};
use serde_json::json;
use std::ffi::OsString;
use std::fs;
use std::path::PathBuf;

#[cfg(all(target_arch = "aarch64", target_os = "macos"))]
const TARGET_TRIPLE: &str = "aarch64-apple-darwin";
#[cfg(all(target_arch = "x86_64", target_os = "macos"))]
const TARGET_TRIPLE: &str = "x86_64-apple-darwin";
#[cfg(not(any(
    all(target_arch = "aarch64", target_os = "macos"),
    all(target_arch = "x86_64", target_os = "macos"),
)))]
compile_error!("tauri_acl_prep only supports macOS x86_64 and aarch64 exec targets");

struct Args {
    config: PathBuf,
    dep_out_dirs: Vec<PathBuf>,
    frontend_dist: PathBuf,
    out_dir: PathBuf,
}

fn main() -> Result<()> {
    let args = parse_args()?;

    let invocation_dir = std::env::current_dir().context("failed to determine current directory")?;
    let config = absolutize(&invocation_dir, args.config);
    let dep_out_dirs = args
        .dep_out_dirs
        .into_iter()
        .map(|path| absolutize(&invocation_dir, path))
        .collect::<Vec<_>>();
    let frontend_dist = absolutize(&invocation_dir, args.frontend_dist);
    let out_dir = absolutize(&invocation_dir, args.out_dir);
    let config_dir = config
        .parent()
        .context("`--config` must include a parent directory")?
        .to_path_buf();

    fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create OUT_DIR {}", out_dir.display()))?;

    std::env::set_current_dir(&config_dir)
        .with_context(|| format!("failed to chdir to {}", config_dir.display()))?;
    std::env::set_var("OUT_DIR", &out_dir);
    apply_dep_out_dirs(&dep_out_dirs)?;
    std::env::set_var("DEP_TAURI_DEV", "false");
    std::env::set_var("TARGET", TARGET_TRIPLE);
    std::env::set_var("CARGO_CFG_TARGET_OS", std::env::consts::OS);
    std::env::set_var("CARGO_CFG_TARGET_ARCH", std::env::consts::ARCH);
    std::env::set_var(
        "TAURI_CONFIG",
        json!({
            "build": {
                "devUrl": serde_json::Value::Null,
                "frontendDist": frontend_dist,
            },
        })
        .to_string(),
    );

    tauri_build::try_build(tauri_build::Attributes::new())
        .context("failed to prepare Tauri ACL outputs")?;

    for output_name in ["acl-manifests.json", "capabilities.json"] {
        let output_path = out_dir.join(output_name);
        if !output_path.is_file() {
            bail!("expected {} to exist", output_path.display());
        }
    }

    Ok(())
}

fn absolutize(cwd: &std::path::Path, path: PathBuf) -> PathBuf {
    if path.is_absolute() {
        path
    } else {
        cwd.join(path)
    }
}

fn parse_args() -> Result<Args> {
    let mut config = None;
    let mut dep_out_dirs = Vec::new();
    let mut frontend_dist = None;
    let mut out_dir = None;
    let mut args = std::env::args_os();
    let _program = args.next();

    while let Some(flag) = args.next() {
        match flag.to_str() {
            Some("--config") => config = Some(next_path("--config", &mut args)?),
            Some("--dep-out-dir") => dep_out_dirs.push(next_path("--dep-out-dir", &mut args)?),
            Some("--frontend-dist") => frontend_dist = Some(next_path("--frontend-dist", &mut args)?),
            Some("--out-dir") => out_dir = Some(next_path("--out-dir", &mut args)?),
            Some(other) => bail!("unknown argument `{other}`"),
            None => bail!("non-utf8 argument is not supported"),
        }
    }

    Ok(Args {
        config: config.context("missing required `--config`")?,
        dep_out_dirs,
        frontend_dist: frontend_dist.context("missing required `--frontend-dist`")?,
        out_dir: out_dir.context("missing required `--out-dir`")?,
    })
}

fn apply_dep_out_dirs(paths: &[PathBuf]) -> Result<()> {
    for path in paths {
        for entry in fs::read_dir(path)
            .with_context(|| format!("failed to read dependency out dir {}", path.display()))?
        {
            let entry = entry
                .with_context(|| format!("failed to read entry from {}", path.display()))?;
            let name = entry.file_name();
            let Some(name) = name.to_str() else {
                continue;
            };
            if !name.ends_with("-permission-files") {
                continue;
            }

            let env_name = permission_env_var(name)?;
            std::env::set_var(env_name, entry.path());
        }
    }

    Ok(())
}

fn permission_env_var(file_name: &str) -> Result<String> {
    if file_name == "tauri-core-permission-files" {
        return Ok("DEP_TAURI_CORE__CORE_PLUGIN___PERMISSION_FILES_PATH".to_string());
    }

    if let Some(segment) = file_name
        .strip_prefix("tauri-core-")
        .and_then(|value| value.strip_suffix("-permission-files"))
    {
        return Ok(format!(
            "DEP_TAURI_CORE:{}__CORE_PLUGIN___PERMISSION_FILES_PATH",
            segment.replace('-', "_").to_ascii_uppercase()
        ));
    }

    if let Some(plugin) = file_name
        .strip_prefix("tauri-")
        .and_then(|value| value.strip_suffix("-permission-files"))
    {
        return Ok(format!(
            "DEP_{}_PERMISSION_FILES_PATH",
            plugin.replace('-', "_").to_ascii_uppercase()
        ));
    }

    bail!("unsupported permission sidecar `{file_name}`")
}

fn next_path(flag: &str, args: &mut impl Iterator<Item = OsString>) -> Result<PathBuf> {
    let value = args
        .next()
        .with_context(|| format!("missing value for `{flag}`"))?;
    Ok(PathBuf::from(value))
}
