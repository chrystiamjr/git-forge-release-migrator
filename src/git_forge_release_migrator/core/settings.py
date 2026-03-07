from __future__ import annotations

import json
import os
import re
import tempfile
from pathlib import Path
from typing import Any

try:
    import yaml
except Exception:  # noqa: BLE001
    yaml = None  # type: ignore[assignment]

_SUPPORTED_PROVIDERS = {"github", "gitlab", "bitbucket"}
_PROVIDER_ENV_ALIASES: dict[str, list[str]] = {
    "github": ["GITHUB_TOKEN", "GH_TOKEN", "GH_PERSONAL_TOKEN"],
    "gitlab": ["GITLAB_TOKEN", "GL_TOKEN"],
    "bitbucket": ["BITBUCKET_TOKEN", "BB_TOKEN"],
}


def default_global_settings_path() -> Path:
    xdg = os.getenv("XDG_CONFIG_HOME", "").strip()
    if xdg:
        base = Path(xdg)
    else:
        base = Path.home() / ".config"
    return base / "gfrm" / "settings.yaml"


def default_local_settings_path(cwd: Path | None = None) -> Path:
    base = cwd or Path.cwd()
    return base / ".gfrm" / "settings.yaml"


def _read_yaml_or_json(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    if not text.strip():
        return {}

    if yaml is not None:
        payload = yaml.safe_load(text)
        if payload is None:
            return {}
        if not isinstance(payload, dict):
            raise ValueError(f"Invalid settings payload in {path}: expected mapping")
        return payload

    # Fallback for environments without PyYAML: support JSON-in-YAML files.
    payload = json.loads(text)
    if not isinstance(payload, dict):
        raise ValueError(f"Invalid settings payload in {path}: expected object")
    return payload


def _dump_yaml_or_json(payload: dict[str, Any]) -> str:
    if yaml is not None:
        return yaml.safe_dump(payload, sort_keys=False, allow_unicode=False)
    return json.dumps(payload, ensure_ascii=True, indent=2) + "\n"


def _deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    merged: dict[str, Any] = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge(merged[key], value)  # type: ignore[index]
        else:
            merged[key] = value
    return merged


def load_settings_file(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    payload = _read_yaml_or_json(path)
    return payload if isinstance(payload, dict) else {}


def load_effective_settings(cwd: Path | None = None) -> dict[str, Any]:
    global_data = load_settings_file(default_global_settings_path())
    local_data = load_settings_file(default_local_settings_path(cwd=cwd))
    return _deep_merge(global_data, local_data)


def read_scope_settings(*, local: bool, cwd: Path | None = None) -> tuple[Path, dict[str, Any]]:
    path = default_local_settings_path(cwd=cwd) if local else default_global_settings_path()
    return path, load_settings_file(path)


def resolve_profile_name(settings: dict[str, Any], requested_profile: str = "") -> str:
    explicit = (requested_profile or "").strip()
    if explicit:
        return explicit

    defaults = settings.get("defaults", {}) if isinstance(settings.get("defaults"), dict) else {}
    profile = str(defaults.get("profile", "")).strip()
    return profile or "default"


def _provider_block(settings: dict[str, Any], profile: str, provider: str) -> dict[str, Any]:
    if provider not in _SUPPORTED_PROVIDERS:
        return {}
    profiles = settings.get("profiles", {}) if isinstance(settings.get("profiles"), dict) else {}
    profile_data = profiles.get(profile, {}) if isinstance(profiles.get(profile), dict) else {}
    providers = profile_data.get("providers", {}) if isinstance(profile_data.get("providers"), dict) else {}
    provider_data = providers.get(provider, {}) if isinstance(providers.get(provider), dict) else {}
    return provider_data


def token_from_settings(settings: dict[str, Any], profile: str, provider: str) -> str:
    block = _provider_block(settings, profile, provider)
    token_env = str(block.get("token_env", "")).strip()
    if token_env:
        from_env = os.getenv(token_env, "")
        if from_env:
            return from_env

    token_plain = str(block.get("token_plain", ""))
    if token_plain:
        return token_plain

    return ""


def token_env_name_from_settings(settings: dict[str, Any], profile: str, provider: str) -> str:
    block = _provider_block(settings, profile, provider)
    return str(block.get("token_env", "")).strip()


def env_aliases(provider: str, *, side_env_name: str = "") -> list[str]:
    names: list[str] = []
    if side_env_name:
        names.append(side_env_name)

    if side_env_name != "GFRM_SOURCE_TOKEN":
        names.append("GFRM_SOURCE_TOKEN")
    if side_env_name != "GFRM_TARGET_TOKEN":
        names.append("GFRM_TARGET_TOKEN")

    names.extend(_PROVIDER_ENV_ALIASES.get(provider, []))

    deduped: list[str] = []
    seen: set[str] = set()
    for name in names:
        if not name or name in seen:
            continue
        deduped.append(name)
        seen.add(name)
    return deduped


def token_from_env_aliases(provider: str, *, side_env_name: str = "") -> str:
    for name in env_aliases(provider, side_env_name=side_env_name):
        value = os.getenv(name, "")
        if value:
            return value
    return ""


def default_shell_profile_paths() -> list[Path]:
    home = Path.home()
    return [
        home / ".zshrc",
        home / ".zprofile",
        home / ".bashrc",
        home / ".bash_profile",
    ]


def scan_shell_export_names(paths: list[Path] | None = None) -> set[str]:
    candidates = paths or default_shell_profile_paths()
    names: set[str] = set()

    export_re = re.compile(r"^\s*export\s+([A-Za-z_][A-Za-z0-9_]*)\s*=.*$")
    assign_re = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=.*$")

    for path in candidates:
        if not path.exists() or not path.is_file():
            continue
        try:
            content = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue

        for line in content.splitlines():
            text = line.strip()
            if not text or text.startswith("#"):
                continue

            m = export_re.match(text)
            if m:
                names.add(m.group(1))
                continue

            m = assign_re.match(text)
            if m:
                names.add(m.group(1))

    return names


def suggest_env_name(provider: str, known_names: set[str]) -> str:
    for name in _PROVIDER_ENV_ALIASES.get(provider, []):
        if name in known_names:
            return name
    return ""


def _ensure_file_security(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(path.parent, 0o700)
    except OSError:
        pass


def write_settings_file(path: Path, payload: dict[str, Any]) -> None:
    _ensure_file_security(path)

    fd, tmp_path = tempfile.mkstemp(prefix="gfrm-settings-", suffix=".yaml", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(_dump_yaml_or_json(payload))
        os.chmod(tmp_path, 0o600)
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


def _ensure_profile_provider(settings: dict[str, Any], profile: str, provider: str) -> dict[str, Any]:
    settings.setdefault("version", 1)

    defaults = settings.setdefault("defaults", {})
    if not isinstance(defaults, dict):
        settings["defaults"] = {}
        defaults = settings["defaults"]
    defaults.setdefault("profile", profile)

    profiles = settings.setdefault("profiles", {})
    if not isinstance(profiles, dict):
        settings["profiles"] = {}
        profiles = settings["profiles"]

    if profile not in profiles or not isinstance(profiles.get(profile), dict):
        profiles[profile] = {}
    profile_data = profiles[profile]

    providers = profile_data.setdefault("providers", {})
    if not isinstance(providers, dict):
        profile_data["providers"] = {}
        providers = profile_data["providers"]

    if provider not in providers or not isinstance(providers.get(provider), dict):
        providers[provider] = {}

    return providers[provider]


def set_provider_token_env(settings: dict[str, Any], *, profile: str, provider: str, env_name: str) -> dict[str, Any]:
    provider_block = _ensure_profile_provider(settings, profile, provider)
    provider_block["token_env"] = env_name.strip()
    provider_block.pop("token_plain", None)
    return settings


def set_provider_token_plain(settings: dict[str, Any], *, profile: str, provider: str, token: str) -> dict[str, Any]:
    provider_block = _ensure_profile_provider(settings, profile, provider)
    provider_block["token_plain"] = token
    provider_block.pop("token_env", None)
    return settings


def unset_provider_token(settings: dict[str, Any], *, profile: str, provider: str) -> dict[str, Any]:
    profiles = settings.get("profiles", {}) if isinstance(settings.get("profiles"), dict) else {}
    profile_data = profiles.get(profile, {}) if isinstance(profiles.get(profile), dict) else {}
    providers = profile_data.get("providers", {}) if isinstance(profile_data.get("providers"), dict) else {}
    provider_data = providers.get(provider, {}) if isinstance(providers.get(provider), dict) else {}

    provider_data.pop("token_env", None)
    provider_data.pop("token_plain", None)

    if not provider_data and provider in providers:
        providers.pop(provider, None)

    if not providers and "providers" in profile_data:
        profile_data.pop("providers", None)

    if not profile_data and profile in profiles:
        profiles.pop(profile, None)

    return settings
