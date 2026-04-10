def _copy_tree_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name)
    args = ctx.actions.args()
    args.add(out.path)
    package_prefix = ctx.label.package + "/"
    strip_prefix = ctx.attr.strip_prefix
    for src in ctx.files.srcs:
        rel = src.short_path
        if package_prefix and rel.startswith(package_prefix):
            rel = rel[len(package_prefix):]
        if strip_prefix:
            if not rel.startswith(strip_prefix):
                fail("file %s does not start with strip_prefix %s" % (src.short_path, strip_prefix))
            rel = rel[len(strip_prefix):]
        args.add("%s=%s" % (src.path, rel))

    ctx.actions.run_shell(
        inputs = depset(ctx.files.srcs),
        outputs = [out],
        arguments = [args],
        command = """
set -eu
out="$1"
shift
mkdir -p "$out"
for entry in "$@"; do
  src="${entry%%=*}"
  rel="${entry#*=}"
  dest="$out/$rel"
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
done
""",
        mnemonic = "CopyFixtureTree",
        progress_message = "Copying fixture tree for %s" % ctx.label.name,
    )

    return [DefaultInfo(files = depset([out]))]

copy_tree = rule(
    implementation = _copy_tree_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True, mandatory = True),
        "strip_prefix": attr.string(default = ""),
    },
)
