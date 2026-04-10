"""Local host tool repositories for example builds."""

def _binary_repo_impl(repository_ctx):
    binary_name = repository_ctx.attr.binary_name
    binary = repository_ctx.which(binary_name)
    if binary == None:
        fail("required host binary %r was not found on PATH" % binary_name)

    repository_ctx.symlink(binary, binary_name)
    repository_ctx.file(
        "BUILD.bazel",
        content = """package(default_visibility = ["//visibility:public"])

exports_files(["{name}"])
""".format(name = binary_name),
    )

_binary_repo = repository_rule(
    implementation = _binary_repo_impl,
    attrs = {
        "binary_name": attr.string(mandatory = True),
    },
    local = True,
)

def _host_tools_impl(_module_ctx):
    _binary_repo(
        name = "rules_tauri_host_bun",
        binary_name = "bun",
    )

host_tools = module_extension(
    implementation = _host_tools_impl,
)
