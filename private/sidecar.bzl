load("//tauri:providers.bzl", "TauriSidecarInfo")

def _single_output(target, attr_name):
    files = target[DefaultInfo].files.to_list()
    if len(files) != 1:
        fail("%s must provide exactly one output, got %d" % (attr_name, len(files)))
    return files[0]

def tauri_sidecar_impl(ctx):
    binary = _single_output(ctx.attr.binary, "binary")
    sidecar_name = ctx.attr.sidecar_name if ctx.attr.sidecar_name else binary.basename
    out = ctx.actions.declare_file("%s-%s" % (sidecar_name, ctx.attr.target_triple))

    ctx.actions.run_shell(
        inputs = [binary],
        outputs = [out],
        command = "set -eu\ncp \"$1\" \"$2\"\nchmod +x \"$2\"\n",
        arguments = [binary.path, out.path],
        mnemonic = "TauriStageSidecar",
        progress_message = "Staging Tauri sidecar for %s" % ctx.label.name,
    )

    return [
        DefaultInfo(files = depset([out])),
        TauriSidecarInfo(
            file = out,
            sidecar_name = sidecar_name,
            target_triple = ctx.attr.target_triple,
        ),
    ]
