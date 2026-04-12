def _copy_tree_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name)
    strip_prefix = ctx.attr.strip_prefix

    lines = [
        "set -eu",
        'out="$1"',
        "mkdir -p \"$out\"",
    ]

    for index, file in enumerate(ctx.files.srcs):
        short_path = file.short_path
        if not short_path.startswith(strip_prefix):
            fail("%s does not start with strip_prefix %s" % (short_path, strip_prefix))
        relative = short_path[len(strip_prefix):]
        if not relative:
            fail("empty relative path for %s" % short_path)
        lines.extend([
            'src%d="$%d"' % (index, index + 2),
            'dst%d="$out/%s"' % (index, relative),
            'mkdir -p "$(dirname "$dst%d")"' % index,
            'cp "$src%d" "$dst%d"' % (index, index),
        ])

    ctx.actions.run_shell(
        inputs = ctx.files.srcs,
        outputs = [out],
        arguments = [out.path] + [file.path for file in ctx.files.srcs],
        command = "\n".join(lines),
        mnemonic = "CopyTree",
        progress_message = "Copying tree for %s" % ctx.label.name,
    )

    return [DefaultInfo(files = depset([out]))]

copy_tree = rule(
    implementation = _copy_tree_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True, mandatory = True),
        "strip_prefix": attr.string(mandatory = True),
    },
)
