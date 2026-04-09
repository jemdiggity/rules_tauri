def _example_frontend_dist_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name)
    args = ctx.actions.args()
    args.add(ctx.attr.app_dir)
    args.add(out.path)

    ctx.actions.run(
        executable = ctx.executable._builder,
        inputs = depset(ctx.files.srcs),
        outputs = [out],
        arguments = [args],
        mnemonic = "BuildTauriExampleFrontendDist",
        progress_message = "Building Tauri example frontend dist for %s" % ctx.label.name,
        use_default_shell_env = True,
    )

    return [DefaultInfo(files = depset([out]))]

example_frontend_dist = rule(
    implementation = _example_frontend_dist_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True, mandatory = True),
        "app_dir": attr.string(mandatory = True),
        "_builder": attr.label(
            default = "//tools:build_tauri_example_frontend.sh",
            executable = True,
            allow_single_file = True,
            cfg = "exec",
        ),
    },
)
