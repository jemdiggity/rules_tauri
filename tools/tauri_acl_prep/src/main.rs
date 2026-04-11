use anyhow::{bail, Context, Result};
use serde_json::json;
use std::ffi::OsString;
use std::fs;
use std::path::Path;
use std::path::PathBuf;
use tauri_utils::{
    acl::{
        capability::Capability, manifest::Manifest, ACL_MANIFESTS_FILE_NAME, APP_ACL_KEY,
        CAPABILITIES_FILE_NAME,
    },
    config::{self, Config, FrontendDist},
    platform::Target,
};
use toml::Value;

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
    dep_env_files: Vec<PathBuf>,
    dep_out_dirs: Vec<PathBuf>,
    frontend_dist: PathBuf,
    out_dir: PathBuf,
}

fn main() -> Result<()> {
    let args = parse_args()?;

    let invocation_dir =
        std::env::current_dir().context("failed to determine current directory")?;
    let config = absolutize(&invocation_dir, args.config);
    let dep_env_files = args
        .dep_env_files
        .into_iter()
        .map(|path| absolutize(&invocation_dir, path))
        .collect::<Vec<_>>();
    let dep_out_dirs = args
        .dep_out_dirs
        .into_iter()
        .map(|path| absolutize(&invocation_dir, path))
        .collect::<Vec<_>>();
    let frontend_dist = absolutize(&invocation_dir, args.frontend_dist);
    let out_dir = absolutize(&invocation_dir, args.out_dir);
    let source_config_dir = config
        .parent()
        .context("`--config` must include a parent directory")?
        .to_path_buf();
    fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create OUT_DIR {}", out_dir.display()))?;
    let cargo_manifest = source_config_dir.join("Cargo.toml");
    let config_dir = stage_config_dir(&source_config_dir, &out_dir)?;

    std::env::set_current_dir(&config_dir)
        .with_context(|| format!("failed to chdir to {}", config_dir.display()))?;
    apply_package_metadata(&cargo_manifest)?;
    std::env::set_var("OUT_DIR", &out_dir);
    apply_dep_env_files(&dep_env_files, &invocation_dir)?;
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

    generate_acl_outputs(&config_dir, &frontend_dist, &out_dir)?;

    Ok(())
}

fn generate_acl_outputs(config_dir: &Path, frontend_dist: &Path, out_dir: &Path) -> Result<()> {
    let target = Target::from_triple(TARGET_TRIPLE);
    let (config_value, _config_paths) = config::parse::read_from(target, config_dir)
        .context("failed to read Tauri configuration")?;

    let mut config = serde_json::from_value::<Config>(config_value)
        .context("failed to deserialize Tauri configuration")?;
    config.build.dev_url = None;
    config.build.frontend_dist = Some(FrontendDist::Directory(frontend_dist.to_path_buf()));

    let permission_map =
        tauri_utils::acl::build::read_permissions().context("failed to read plugin permissions")?;
    let mut global_scope_map = tauri_utils::acl::build::read_global_scope_schemas()
        .context("failed to read global scope schemas")?;

    let mut acl_manifests = std::collections::BTreeMap::new();
    for (plugin_name, permission_files) in permission_map {
        let global_scope_schema = global_scope_map.remove(&plugin_name);
        let manifest = Manifest::new(permission_files, global_scope_schema);
        acl_manifests.insert(plugin_name, manifest);
    }

    let capabilities_from_files =
        tauri_utils::acl::build::parse_capabilities("./capabilities/**/*")
            .context("failed to parse capabilities")?;
    let capabilities = tauri_utils::acl::get_capabilities(&config, capabilities_from_files, None)
        .context("failed to resolve capabilities")?;

    validate_capabilities(&acl_manifests, &capabilities)?;

    write_json(out_dir.join(ACL_MANIFESTS_FILE_NAME), &acl_manifests)?;
    write_json(out_dir.join(CAPABILITIES_FILE_NAME), &capabilities)?;

    for output_name in [ACL_MANIFESTS_FILE_NAME, CAPABILITIES_FILE_NAME] {
        let output_path = out_dir.join(output_name);
        if !output_path.is_file() {
            bail!("expected {} to exist", output_path.display());
        }
    }

    Ok(())
}

fn validate_capabilities(
    acl_manifests: &std::collections::BTreeMap<String, Manifest>,
    capabilities: &std::collections::BTreeMap<String, Capability>,
) -> Result<()> {
    let target = Target::from_triple(&std::env::var("TARGET").unwrap());

    for capability in capabilities.values() {
        if !capability
            .platforms
            .as_ref()
            .map(|platforms| platforms.contains(&target))
            .unwrap_or(true)
        {
            continue;
        }

        for permission_entry in &capability.permissions {
            let permission_id = permission_entry.identifier();

            let key = permission_id.get_prefix().unwrap_or(APP_ACL_KEY);
            let permission_name = permission_id.get_base();

            let permission_exists = acl_manifests
                .get(key)
                .map(|manifest| {
                    permission_name == "default"
                        || manifest.permissions.contains_key(permission_name)
                        || manifest.permission_sets.contains_key(permission_name)
                })
                .unwrap_or(false);

            if !permission_exists {
                let mut available_permissions = Vec::new();
                for (key, manifest) in acl_manifests {
                    let prefix = if key == APP_ACL_KEY {
                        "".to_string()
                    } else {
                        format!("{key}:")
                    };
                    if manifest.default_permission.is_some() {
                        available_permissions.push(format!("{prefix}default"));
                    }
                    for p in manifest.permissions.keys() {
                        available_permissions.push(format!("{prefix}{p}"));
                    }
                    for p in manifest.permission_sets.keys() {
                        available_permissions.push(format!("{prefix}{p}"));
                    }
                }

                bail!(
                    "Permission {} not found, expected one of {}",
                    permission_id.get(),
                    available_permissions.join(", ")
                );
            }
        }
    }

    Ok(())
}

fn write_json<T: serde::Serialize>(path: PathBuf, value: &T) -> Result<()> {
    let json = serde_json::to_string(value).context("failed to serialize ACL output")?;
    fs::write(&path, json).with_context(|| format!("failed to write {}", path.display()))?;
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
    let mut dep_env_files = Vec::new();
    let mut dep_out_dirs = Vec::new();
    let mut frontend_dist = None;
    let mut out_dir = None;
    let mut args = std::env::args_os();
    let _program = args.next();

    while let Some(flag) = args.next() {
        match flag.to_str() {
            Some("--config") => config = Some(next_path("--config", &mut args)?),
            Some("--dep-env-file") => dep_env_files.push(next_path("--dep-env-file", &mut args)?),
            Some("--dep-out-dir") => dep_out_dirs.push(next_path("--dep-out-dir", &mut args)?),
            Some("--frontend-dist") => {
                frontend_dist = Some(next_path("--frontend-dist", &mut args)?)
            }
            Some("--out-dir") => out_dir = Some(next_path("--out-dir", &mut args)?),
            Some(other) => bail!("unknown argument `{other}`"),
            None => bail!("non-utf8 argument is not supported"),
        }
    }

    Ok(Args {
        config: config.context("missing required `--config`")?,
        dep_env_files,
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
            let entry =
                entry.with_context(|| format!("failed to read entry from {}", path.display()))?;
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

fn apply_dep_env_files(paths: &[PathBuf], pwd: &std::path::Path) -> Result<()> {
    let pwd = pwd.display().to_string();

    for path in paths {
        let contents = fs::read_to_string(path)
            .with_context(|| format!("failed to read dependency env file {}", path.display()))?;
        for line in contents.lines() {
            let Some((name, value)) = line.split_once('=') else {
                continue;
            };
            let value = value.replace("${pwd}", &pwd);
            std::env::set_var(name, value);
        }
    }

    Ok(())
}

fn apply_package_metadata(path: &std::path::Path) -> Result<()> {
    let manifest = fs::read_to_string(path)
        .with_context(|| format!("failed to read cargo manifest {}", path.display()))?;
    let manifest: Value = manifest
        .parse()
        .with_context(|| format!("failed to parse cargo manifest {}", path.display()))?;
    let package = manifest
        .get("package")
        .and_then(Value::as_table)
        .context("cargo manifest missing [package] table")?;

    set_package_var(package, "name", "CARGO_PKG_NAME");
    set_package_var(package, "version", "CARGO_PKG_VERSION");
    set_package_var(package, "description", "CARGO_PKG_DESCRIPTION");
    set_package_authors(package);

    Ok(())
}

fn set_package_var(package: &toml::value::Table, key: &str, env_name: &str) {
    if let Some(value) = package.get(key).and_then(Value::as_str) {
        std::env::set_var(env_name, value);
    }
}

fn set_package_authors(package: &toml::value::Table) {
    let Some(authors) = package.get("authors").and_then(Value::as_array) else {
        return;
    };
    let authors = authors
        .iter()
        .filter_map(Value::as_str)
        .collect::<Vec<_>>()
        .join(":");
    std::env::set_var("CARGO_PKG_AUTHORS", authors);
}

fn stage_config_dir(source: &Path, out_dir: &Path) -> Result<PathBuf> {
    let staged = out_dir.join("_staged_config");
    if staged.exists() {
        fs::remove_dir_all(&staged)
            .with_context(|| format!("failed to clear {}", staged.display()))?;
    }
    fs::create_dir_all(&staged)
        .with_context(|| format!("failed to create {}", staged.display()))?;

    copy_file(&source.join("Cargo.toml"), &staged.join("Cargo.toml"))?;
    copy_file(
        &source.join("tauri.conf.json"),
        &staged.join("tauri.conf.json"),
    )?;
    if source.join("icons").is_dir() {
        copy_tree(&source.join("icons"), &staged.join("icons"))?;
    }
    if source.join("capabilities").is_dir() {
        copy_capabilities_dir(&source.join("capabilities"), &staged.join("capabilities"))?;
    }

    Ok(staged)
}

fn copy_capabilities_dir(source: &Path, destination: &Path) -> Result<()> {
    fs::create_dir_all(destination)
        .with_context(|| format!("failed to create {}", destination.display()))?;
    for entry in
        fs::read_dir(source).with_context(|| format!("failed to read {}", source.display()))?
    {
        let entry =
            entry.with_context(|| format!("failed to read entry from {}", source.display()))?;
        let source_path = entry.path();
        let destination_path = destination.join(entry.file_name());
        if source_path.is_dir() {
            copy_capabilities_dir(&source_path, &destination_path)?;
            continue;
        }
        if source_path.extension().and_then(|value| value.to_str()) == Some("json") {
            let content = fs::read_to_string(&source_path)
                .with_context(|| format!("failed to read {}", source_path.display()))?;
            let content = content.replace("\"opener:", "\"plugin-opener:");
            fs::write(&destination_path, content)
                .with_context(|| format!("failed to write {}", destination_path.display()))?;
            continue;
        }
        copy_file(&source_path, &destination_path)?;
    }
    Ok(())
}

fn copy_tree(source: &Path, destination: &Path) -> Result<()> {
    fs::create_dir_all(destination)
        .with_context(|| format!("failed to create {}", destination.display()))?;
    for entry in
        fs::read_dir(source).with_context(|| format!("failed to read {}", source.display()))?
    {
        let entry =
            entry.with_context(|| format!("failed to read entry from {}", source.display()))?;
        let source_path = entry.path();
        let destination_path = destination.join(entry.file_name());
        if source_path.is_dir() {
            copy_tree(&source_path, &destination_path)?;
        } else {
            copy_file(&source_path, &destination_path)?;
        }
    }
    Ok(())
}

fn copy_file(source: &Path, destination: &Path) -> Result<()> {
    if let Some(parent) = destination.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    fs::copy(source, destination).with_context(|| {
        format!(
            "failed to copy {} to {}",
            source.display(),
            destination.display()
        )
    })?;
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

#[cfg(test)]
mod tests {
    use super::stage_config_dir;
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    struct TempDir {
        path: PathBuf,
    }

    impl TempDir {
        fn new(prefix: &str) -> Self {
            let unique = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("time went backwards")
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "rules_tauri_{prefix}_{}_{}",
                std::process::id(),
                unique,
            ));
            fs::create_dir_all(&path).expect("failed to create temp dir");
            Self { path }
        }

        fn path(&self) -> &std::path::Path {
            &self.path
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    #[test]
    fn stage_config_dir_stages_cargo_manifest() {
        let source = TempDir::new("tauri_acl_prep_source");
        let out_dir = TempDir::new("tauri_acl_prep_out");
        fs::write(
            source.path().join("Cargo.toml"),
            "[package]\nname = \"fixture\"\nversion = \"0.1.0\"\n",
        )
        .expect("failed to write Cargo.toml");
        fs::write(source.path().join("tauri.conf.json"), "{}\n")
            .expect("failed to write tauri.conf.json");

        let staged =
            stage_config_dir(source.path(), out_dir.path()).expect("staging should succeed");

        assert!(
            staged.join("Cargo.toml").is_file(),
            "expected staged Cargo.toml to exist"
        );
    }
}
