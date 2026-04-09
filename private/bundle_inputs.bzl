load("//private:manifest.bzl", "encode_manifest", "manifest_entry")
load("//private:paths.bzl", "normalize_bundle_relative_path", "normalize_resource_relpath", "strip_target_triple_suffix")
load("//private:plist.bzl", "default_plist_inputs")
load("//tauri:providers.bzl", "TauriBundleInfo")

def _files_from_target(target):
    return target[DefaultInfo].files.to_list()

def _files_from_targets(targets):
    files = []
    for target in targets:
        files.extend(_files_from_target(target))
    return files

def _single_file_from_target(target, attr_name):
    files = _files_from_target(target)
    if len(files) != 1:
        fail("%s must provide exactly one file, got %d" % (attr_name, len(files)))
    return files[0]

def _plist_fragment_paths(ctx):
    return [file.path for file in _files_from_targets(ctx.attr.info_plist_fragments)]

def _label_keyed_entries(label_dict, kind):
    entries = []
    inputs = []
    for target, destination in label_dict.items():
        file = _single_file_from_target(target, kind)
        entries.append((file, destination))
        inputs.append(file)
    return entries, inputs

def _label_keyed_tree_entries(label_dict):
    entries = []
    inputs = []
    for target, destination_prefix in label_dict.items():
        for file in _files_from_target(target):
            entries.append((file, destination_prefix))
            inputs.append(file)
    return entries, inputs

def tauri_bundle_inputs_impl(ctx):
    has_version = ctx.attr.version != ""
    has_version_file = ctx.file.version_file != None
    if has_version == has_version_file:
        fail("exactly one of version or version_file must be set")

    main_binary = ctx.file.main_binary
    main_binary_name = ctx.attr.main_binary_name if ctx.attr.main_binary_name else main_binary.basename
    version_value = ctx.attr.version if has_version else "<from VERSION file>"

    info_plist = ctx.actions.declare_file(ctx.label.name + "_Info.plist")
    bundle_manifest = ctx.actions.declare_file(ctx.label.name + "_bundle_manifest.json")
    bundle_inputs_dir = ctx.actions.declare_directory(ctx.label.name + "_bundle_inputs")
    spec_file = ctx.actions.declare_file(ctx.label.name + "_bundle_spec.json")

    frontend_files = _files_from_target(ctx.attr.frontend_dist) if ctx.attr.frontend_dist else []
    sidecar_files = _files_from_targets(ctx.attr.sidecars)
    resource_files = _files_from_targets(ctx.attr.resources)
    icon_files = _files_from_targets(ctx.attr.icons)
    capability_files = _files_from_targets(ctx.attr.capabilities)
    framework_files = _files_from_targets(ctx.attr.frameworks)
    plist_fragment_files = _files_from_targets(ctx.attr.info_plist_fragments)
    resource_map_entries, mapped_resource_inputs = _label_keyed_entries(ctx.attr.resource_map, "resource_map")
    resource_tree_entries, resource_tree_inputs = _label_keyed_tree_entries(ctx.attr.resource_trees)
    macos_file_entries, macos_file_inputs = _label_keyed_entries(ctx.attr.macos_files, "macos_files")

    plist_inputs = [ctx.executable._make_plist_tool]
    plist_arguments = ctx.actions.args()
    plist_arguments.add("--output", info_plist.path)
    plist_arguments.add("--bundle-id", ctx.attr.bundle_id)
    plist_arguments.add("--product-name", ctx.attr.product_name)
    plist_arguments.add("--main-binary-name", main_binary_name)
    if has_version:
        plist_arguments.add("--version", ctx.attr.version)
    else:
        plist_inputs.append(ctx.file.version_file)
        plist_arguments.add("--version-file", ctx.file.version_file.path)
    if ctx.file.tauri_config:
        plist_inputs.append(ctx.file.tauri_config)
        plist_arguments.add("--tauri-config", ctx.file.tauri_config.path)
    if icon_files:
        plist_arguments.add("--icon-name", icon_files[0].basename)
    for fragment in plist_fragment_files:
        plist_inputs.append(fragment)
        plist_arguments.add("--plist-fragment", fragment.path)

    ctx.actions.run(
        executable = ctx.executable._make_plist_tool,
        inputs = plist_inputs,
        outputs = [info_plist],
        arguments = [plist_arguments],
        mnemonic = "TauriMakePlist",
        progress_message = "Generating Info.plist for %s" % ctx.label.name,
    )

    entries = []
    manifest_inputs = [main_binary, info_plist]
    if ctx.file.tauri_config:
        manifest_inputs.append(ctx.file.tauri_config)
    if ctx.file.entitlements:
        manifest_inputs.append(ctx.file.entitlements)
        entries.append(manifest_entry(
            ctx.file.entitlements.path,
            "Contents/Resources/tauri/entitlements.plist",
            "entitlements",
        ))

    entries.append(manifest_entry(
        info_plist.path,
        "Contents/Info.plist",
        "info_plist",
    ))
    entries.append(manifest_entry(
        main_binary.path,
        "Contents/MacOS/%s" % main_binary_name,
        "main_binary",
    ))

    for file in resource_files:
        manifest_inputs.append(file)
        entries.append(manifest_entry(
            file.path,
            "Contents/Resources/resources/%s" % normalize_resource_relpath(file.short_path),
            "resource",
        ))

    for file, destination in resource_map_entries:
        manifest_inputs.append(file)
        entries.append(manifest_entry(
            file.path,
            "Contents/Resources/%s" % normalize_bundle_relative_path(destination),
            "mapped_resource",
        ))

    for file, destination_prefix in resource_tree_entries:
        manifest_inputs.append(file)
        destination = normalize_resource_relpath(file.short_path)
        if destination_prefix:
            destination = "%s/%s" % (
                normalize_bundle_relative_path(destination_prefix),
                destination,
            )
        entries.append(manifest_entry(
            file.path,
            "Contents/Resources/%s" % destination,
            "resource_tree",
        ))

    for file in icon_files:
        manifest_inputs.append(file)
        entries.append(manifest_entry(
            file.path,
            "Contents/Resources/%s" % file.basename,
            "icon",
        ))

    for file in framework_files:
        manifest_inputs.append(file)
        entries.append(manifest_entry(
            file.path,
            "Contents/Frameworks/%s" % file.basename,
            "framework",
        ))

    for file in sidecar_files:
        expected_suffix = "-%s" % ctx.attr.target_triple
        if not file.basename.endswith(expected_suffix):
            fail(
                "sidecar %s must end with %s" % (file.basename, expected_suffix),
            )
        manifest_inputs.append(file)
        entries.append(manifest_entry(
            file.path,
            "Contents/MacOS/%s" % strip_target_triple_suffix(file.path, ctx.attr.target_triple),
            "sidecar",
        ))

    for file, destination in macos_file_entries:
        manifest_inputs.append(file)
        entries.append(manifest_entry(
            file.path,
            "Contents/%s" % normalize_bundle_relative_path(destination),
            "macos_file",
        ))

    metadata = default_plist_inputs(
        bundle_id = ctx.attr.bundle_id,
        product_name = ctx.attr.product_name,
        version = version_value,
        main_binary_name = main_binary_name,
    )
    metadata["target_triple"] = ctx.attr.target_triple
    metadata["entry_count"] = len(entries)

    ctx.actions.write(
        output = spec_file,
        content = encode_manifest(entries, metadata),
    )

    manifest_run_inputs = depset(
        direct = manifest_inputs + mapped_resource_inputs + resource_tree_inputs + macos_file_inputs + [spec_file, ctx.executable._make_manifest_tool],
    )
    manifest_arguments = ctx.actions.args()
    manifest_arguments.add("--spec", spec_file.path)
    manifest_arguments.add("--output-dir", bundle_inputs_dir.path)
    manifest_arguments.add("--output-manifest", bundle_manifest.path)
    ctx.actions.run(
        executable = ctx.executable._make_manifest_tool,
        inputs = manifest_run_inputs,
        outputs = [bundle_inputs_dir, bundle_manifest],
        arguments = [manifest_arguments],
        mnemonic = "TauriStageBundleInputs",
        progress_message = "Staging Tauri bundle inputs for %s" % ctx.label.name,
    )

    return [
        DefaultInfo(files = depset([bundle_inputs_dir, bundle_manifest, info_plist])),
        TauriBundleInfo(
            bundle_inputs_dir = bundle_inputs_dir,
            bundle_manifest = bundle_manifest,
            main_binary = main_binary,
            sidecars = sidecar_files,
            bundle_id = ctx.attr.bundle_id,
            product_name = ctx.attr.product_name,
            version = version_value,
            target_triple = ctx.attr.target_triple,
            info_plist = info_plist,
            entitlements = ctx.file.entitlements,
            main_binary_name = main_binary_name,
        ),
    ]
