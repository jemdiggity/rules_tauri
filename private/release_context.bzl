def _single_output(target, attr_name):
    files = target[DefaultInfo].files.to_list()
    if len(files) != 1:
        fail("%s must provide exactly one output, got %d" % (attr_name, len(files)))
    return files[0]

def _find_named_file(files, basename, attr_name):
    matches = [file for file in files if file.basename == basename]
    if len(matches) != 1:
        fail("%s must provide exactly one %s, got %d" % (attr_name, basename, len(matches)))
    return matches[0]

def _target_files(targets):
    files = []
    for target in targets:
        files.extend(target[DefaultInfo].files.to_list())
    return files

def _tauri_acl_prep_dir_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name + ".out_dir")
    config = _find_named_file(ctx.files.cargo_srcs, "tauri.conf.json", "cargo_srcs")
    frontend_dist = _single_output(ctx.attr.frontend_dist, "frontend_dist")
    dep_target_files = _target_files(ctx.attr.dep_env_targets)
    dep_env_files = [file for file in dep_target_files if file.basename.endswith(".depenv")]
    dep_out_dirs = [file for file in dep_target_files if file.is_directory]
    inputs = depset(
        direct = ctx.files.cargo_srcs + ctx.files.tauri_build_data + [frontend_dist] + dep_target_files,
    )

    args = ctx.actions.args()
    args.add("--config", config.path)
    for dep_env_file in dep_env_files:
        args.add("--dep-env-file", dep_env_file.path)
    for dep_out_dir in dep_out_dirs:
        args.add("--dep-out-dir", dep_out_dir.path)
    args.add("--frontend-dist", frontend_dist.path)
    args.add("--out-dir", out.path)

    ctx.actions.run(
        executable = ctx.executable._tool,
        inputs = inputs,
        outputs = [out],
        arguments = [args],
        mnemonic = "TauriAclPrep",
        progress_message = "Preparing Tauri ACL outputs for %s" % ctx.label.name,
    )

    return [DefaultInfo(files = depset([out]))]

_tauri_acl_prep_dir = rule(
    implementation = _tauri_acl_prep_dir_impl,
    attrs = {
        "cargo_srcs": attr.label(mandatory = True),
        "dep_env_targets": attr.label_list(),
        "frontend_dist": attr.label(mandatory = True),
        "tauri_build_data": attr.label(mandatory = True),
        "_tool": attr.label(
            default = Label("//tools/tauri_acl_prep:tauri_acl_prep_exec"),
            cfg = "exec",
            executable = True,
        ),
    },
)

def _tauri_context_support_dir_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name)
    config = _find_named_file(ctx.files.cargo_srcs, "tauri.conf.json", "cargo_srcs")
    embedded_assets_rust = _single_output(ctx.attr.embedded_assets_rust, "embedded_assets_rust")
    acl_out_dir = _single_output(ctx.attr.acl_out_dir, "acl_out_dir")
    inputs = depset(
        direct = ctx.files.cargo_srcs + ctx.files.tauri_build_data + [embedded_assets_rust, acl_out_dir] + ctx.files.verification_targets,
    )

    args = ctx.actions.args()
    args.add("--config", config.path)
    args.add("--embedded-assets-rust", embedded_assets_rust.path)
    args.add("--acl-out-dir", acl_out_dir.path)
    args.add("--out", out.path + "/full_context_rust.rs")

    ctx.actions.run(
        executable = ctx.executable._tool,
        inputs = inputs,
        outputs = [out],
        arguments = [args],
        mnemonic = "TauriContextCodegenDir",
        progress_message = "Generating Tauri context support dir for %s" % ctx.label.name,
    )

    return [DefaultInfo(files = depset([out]))]

_tauri_context_support_dir = rule(
    implementation = _tauri_context_support_dir_impl,
    attrs = {
        "acl_out_dir": attr.label(mandatory = True),
        "cargo_srcs": attr.label(mandatory = True),
        "embedded_assets_rust": attr.label(mandatory = True),
        "tauri_build_data": attr.label(mandatory = True),
        "verification_targets": attr.label_list(allow_files = True),
        "_tool": attr.label(
            default = Label("//tools/tauri_context_codegen:tauri_context_codegen_exec"),
            cfg = "exec",
            executable = True,
        ),
    },
)

def tauri_release_context(
        *,
        name,
        cargo_srcs,
        tauri_build_data,
        frontend_dist,
        embedded_assets_rust,
        acl_dep_env_targets = None,
        verification_targets = None):
    if acl_dep_env_targets == None:
        acl_dep_env_targets = []
    if verification_targets == None:
        verification_targets = []

    acl_name = "_" + name + "_acl_prep"
    support_name = name + "_support"

    _tauri_acl_prep_dir(
        name = acl_name,
        cargo_srcs = cargo_srcs,
        dep_env_targets = acl_dep_env_targets,
        frontend_dist = frontend_dist,
        tauri_build_data = tauri_build_data,
    )

    _tauri_context_support_dir(
        name = support_name,
        acl_out_dir = ":" + acl_name,
        cargo_srcs = cargo_srcs,
        embedded_assets_rust = embedded_assets_rust,
        tauri_build_data = tauri_build_data,
        verification_targets = verification_targets,
    )

    native.genrule(
        name = name,
        srcs = [":" + support_name],
        outs = [name + ".rs"],
        cmd = "cp $(location :%s)/full_context_rust.rs $@" % support_name,
    )

def tauri_release_rust_library_src(
        *,
        name,
        src,
        release_context_support):
    native.genrule(
        name = name,
        srcs = [
            src,
            release_context_support,
        ],
        outs = [name + ".rs"],
        cmd = """
python3 - "$(location {src})" "$(location {support})" "$@" <<'PY'
import json
import pathlib
import re
import sys

source_path = pathlib.Path(sys.argv[1])
source = source_path.read_text(encoding="utf-8")
support_dir = pathlib.Path(sys.argv[2])
context = (support_dir / "full_context_rust.rs").read_text(encoding="utf-8")
context = re.sub(
    r'::\\s*std\\s*::\\s*env\\s*!\\s*\\(\\s*"OUT_DIR"\\s*\\)',
    json.dumps(support_dir.name),
    context,
)
rewritten = re.sub(
    r'tauri\\s*::\\s*tauri_build_context\\s*!\\s*\\(\\s*\\)',
    lambda _: context,
    source,
    count = 1,
)
if rewritten == source:
    raise SystemExit("expected source to contain tauri::tauri_build_context!()")
pathlib.Path(sys.argv[3]).write_text(rewritten, encoding="utf-8")
PY
""".format(
            src = src,
            support = release_context_support,
        ),
    )
