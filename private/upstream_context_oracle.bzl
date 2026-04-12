load("@rules_rust//cargo:defs.bzl", "cargo_build_script")

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

def _tauri_context_rust_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".rs")
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
    args.add("--out", out.path)

    ctx.actions.run(
        executable = ctx.executable._tool,
        inputs = inputs,
        outputs = [out],
        arguments = [args],
        mnemonic = "TauriContextCodegen",
        progress_message = "Generating Tauri context for %s" % ctx.label.name,
    )

    return [DefaultInfo(files = depset([out]))]

_tauri_context_rust = rule(
    implementation = _tauri_context_rust_impl,
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

def _is_acl_fixture(rundir):
    return rundir == "test/fixtures/tauri_codegen/src-tauri"

def tauri_upstream_context_oracle(
        *,
        upstream_name,
        full_context_name,
        cargo_srcs,
        tauri_build_data,
        build_script_src,
        build_contract_src,
        pkg_name,
        version,
        rundir,
        aliases,
        build_deps,
        build_proc_macro_deps,
        link_deps,
        frontend_dist,
        embedded_assets_rust,
        acl_dep_env_targets = None):
    if acl_dep_env_targets == None:
        acl_dep_env_targets = []

    acl_prep_name = "_" + upstream_name + "_acl_prep"
    acl_compare_name = "_" + upstream_name + "_acl_prep_matches_oracle"
    support_name = full_context_name + "_support"

    _tauri_acl_prep_dir(
        name = acl_prep_name,
        cargo_srcs = cargo_srcs,
        dep_env_targets = acl_dep_env_targets,
        frontend_dist = frontend_dist,
        tauri_build_data = tauri_build_data,
    )

    if _is_acl_fixture(rundir):
        cargo_build_script(
            name = upstream_name,
            srcs = [
                build_script_src,
                build_contract_src,
            ],
            crate_root = build_script_src,
            crate_name = upstream_name + "_build",
            edition = "2021",
            pkg_name = pkg_name,
            version = version,
            rundir = rundir,
            aliases = aliases,
            deps = build_deps,
            link_deps = link_deps,
            proc_macro_deps = build_proc_macro_deps,
            data = [
                cargo_srcs,
                tauri_build_data,
                frontend_dist,
            ],
            compile_data = [
                cargo_srcs,
                tauri_build_data,
                frontend_dist,
            ],
            build_script_env = {
                "DEP_TAURI_DEV": "false",
                "RULES_TAURI_FRONTEND_DIST": "$(location %s)" % frontend_dist,
            },
        )

    acl_source = ":" + acl_prep_name

    _tauri_context_support_dir(
        name = support_name,
        acl_out_dir = acl_source,
        cargo_srcs = cargo_srcs,
        embedded_assets_rust = embedded_assets_rust,
        tauri_build_data = tauri_build_data,
        verification_targets = ([":" + acl_compare_name] if _is_acl_fixture(rundir) else []),
    )

    native.genrule(
        name = full_context_name,
        srcs = [":" + support_name],
        outs = [full_context_name + ".rs"],
        cmd = "cp $(location :%s)/full_context_rust.rs $@" % support_name,
    )

    if _is_acl_fixture(rundir):
        native.genrule(
            name = acl_compare_name,
            srcs = [
                ":" + acl_prep_name,
                ":" + upstream_name,
            ],
            outs = [acl_compare_name + ".ok"],
            cmd = """
set -eu
acl_dir="$(location :{acl_prep_name})"
oracle_dir="$(location :{upstream_name})"
for name in acl-manifests.json capabilities.json; do
  test -f "$$acl_dir/$$name"
  test -f "$$oracle_dir/$$name"
  if ! cmp -s "$$acl_dir/$$name" "$$oracle_dir/$$name"; then
    echo "{acl_compare_name}: mismatch for $$name" >&2
    diff -u "$$oracle_dir/$$name" "$$acl_dir/$$name" >&2 || true
    exit 1
  fi
done
echo ok > "$@"
""".format(
                acl_compare_name = acl_compare_name,
                acl_prep_name = acl_prep_name,
                upstream_name = upstream_name,
            ),
        )
