def _common_dir_prefix(files):
    prefix = None
    for file in files:
        short_path = file.short_path
        directory = short_path.rsplit("/", 1)[0] if "/" in short_path else ""
        segments = directory.split("/") if directory else []
        if prefix == None:
            prefix = segments
            continue

        limit = min(len(prefix), len(segments))
        common_length = limit
        for index in range(limit):
            if prefix[index] != segments[index]:
                common_length = index
                break
        prefix = prefix[:common_length]

    return "/".join(prefix) if prefix else ""

def _tauri_frontend_dist_impl(ctx):
    files = sorted(ctx.attr.frontend_dist[DefaultInfo].files.to_list(), key = lambda file: file.short_path)
    if len(files) == 1 and files[0].is_directory:
        return [DefaultInfo(files = depset(files))]

    for file in files:
        if file.is_directory:
            fail("frontend_dist may not mix directory artifacts with file sets")

    out = ctx.actions.declare_directory(ctx.label.name)
    prefix = _common_dir_prefix(files)
    args = ctx.actions.args()
    args.add(out.path)

    for file in files:
        rel = file.short_path
        if prefix:
            prefix_with_sep = prefix + "/"
            if not rel.startswith(prefix_with_sep):
                fail("file %s does not share prefix %s" % (file.short_path, prefix))
            rel = rel[len(prefix_with_sep):]
        args.add(file.path)
        args.add(rel)

    ctx.actions.run_shell(
        inputs = depset(files),
        outputs = [out],
        arguments = [args],
        command = """
set -eu
out="$1"
shift
mkdir -p "$out"
while [ "$#" -gt 0 ]; do
  src="$1"
  rel="$2"
  shift 2
  dest="$out/$rel"
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
done
""",
        mnemonic = "NormalizeFrontendDist",
        progress_message = "Normalizing frontend_dist for %s" % ctx.label.name,
    )

    return [DefaultInfo(files = depset([out]))]

tauri_frontend_dist = rule(
    implementation = _tauri_frontend_dist_impl,
    attrs = {
        "frontend_dist": attr.label(allow_files = True, mandatory = True),
    },
    doc = "Normalizes a frontend target into a single deterministic directory artifact.",
)
