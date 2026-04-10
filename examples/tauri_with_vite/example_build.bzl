def _target_platform_transition_impl(settings, attr):
    return {
        "//command_line_option:platforms": str(attr.platform),
    }

target_platform_transition = transition(
    implementation = _target_platform_transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _single_file_target_impl(ctx):
    if len(ctx.attr.target) != 1:
        fail("expected exactly one transitioned target, got %d" % len(ctx.attr.target))
    files = ctx.attr.target[0][DefaultInfo].files.to_list()
    if len(files) != 1:
        fail("target must provide exactly one file, got %d" % len(files))
    return [DefaultInfo(files = depset(files))]

single_file_target = rule(
    implementation = _single_file_target_impl,
    attrs = {
        "platform": attr.label(mandatory = True),
        "target": attr.label(mandatory = True, cfg = target_platform_transition),
    },
)

def _exec_target_impl(ctx):
    return [DefaultInfo(files = ctx.attr.target[DefaultInfo].files)]

exec_target = rule(
    implementation = _exec_target_impl,
    attrs = {
        "target": attr.label(mandatory = True, cfg = "exec"),
    },
)
