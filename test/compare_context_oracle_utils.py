import re

BUILD_MARKER = "build : :: tauri :: utils :: config :: BuildConfig {"
CONFIG_PARENT_MARKER = "context . with_config_parent ("


def extract_balanced(text: str, start: int, open_ch: str, close_ch: str) -> str:
    depth = 0
    for idx in range(start, len(text)):
        ch = text[idx]
        if ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth == 0:
                return text[start:idx + 1]
    raise SystemExit("unterminated balanced block")


def extract_build_block(text: str) -> str:
    start = text.find(BUILD_MARKER)
    if start < 0:
        raise SystemExit("failed to locate BuildConfig block")
    brace_start = text.find("{", start)
    return extract_balanced(text, brace_start, "{", "}")


def extract_config_parent_call(text: str) -> str:
    start = text.find(CONFIG_PARENT_MARKER)
    if start < 0:
        raise SystemExit("failed to locate with_config_parent call")
    paren_start = text.find("(", start)
    return extract_balanced(text, paren_start, "(", ")")


def extract_config_parent_arg(text: str) -> str:
    call = extract_config_parent_call(text)
    return call[1:-1]


def normalize_paths(fragment: str) -> str:
    fragment = re.sub(r'"[^"]*/src-tauri"', '"$MANIFEST_DIR"', fragment)
    fragment = re.sub(r"\s+", " ", fragment).strip()
    return fragment
