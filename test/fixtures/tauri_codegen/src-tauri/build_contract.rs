pub fn is_dev_enabled(dep_tauri_dev: Option<&str>) -> bool {
    dep_tauri_dev == Some("true")
}

pub fn android_package_names(identifier: &str) -> (String, String) {
    let segments: Vec<_> = identifier.split('.').collect();
    let (app_name_segment, prefix_segments) = segments
        .split_last()
        .expect("identifier must contain at least one segment");

    let app_name = app_name_segment.replace('-', "_");
    let prefix = prefix_segments
        .iter()
        .map(|segment| segment.replace(['_', '-'], "_1"))
        .collect::<Vec<_>>()
        .join("_");

    (app_name, prefix)
}

#[cfg(test)]
mod tests {
    use super::{android_package_names, is_dev_enabled};

    #[test]
    fn dev_cfg_only_when_dep_tauri_dev_is_true() {
        assert!(is_dev_enabled(Some("true")));
        assert!(!is_dev_enabled(Some("false")));
        assert!(!is_dev_enabled(None));
    }

    #[test]
    fn android_package_names_follow_identifier_rules() {
        let (app_name, prefix) = android_package_names("com.example.tauri-codegen-fixture");
        assert_eq!(app_name, "tauri_codegen_fixture");
        assert_eq!(prefix, "com_example");
    }

    #[test]
    fn android_package_names_ignore_product_name_and_escape_identifier_segments() {
        let (app_name, prefix) = android_package_names("com.foo_bar-baz.actual-app");
        assert_eq!(app_name, "actual_app");
        assert_eq!(prefix, "com_foo_1bar_1baz");
    }
}
