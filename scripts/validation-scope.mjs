export function classifyChanges(files) {
  return {
    dart: files.some((path) => /^dart_cli\/(lib|bin)\//.test(path)),
    gui: files.some((path) => /^gui\//.test(path) || /^dart_cli\/lib\//.test(path)),
    visual: files.some((path) => (/^gui\/lib\/src\/(features|core\/widgets|theme|app)\//.test(path) || /^gui\/test\/(visual|goldens)\//.test(path))),
    docs: files.some((path) => /^(website\/|README.md$|package.json$|yarn.lock$)/.test(path)),
    tooling: files.some((path) => /^(scripts\/|\.github\/|\.husky\/|package.json$)/.test(path)),
    native: files.some((path) => /^gui\/(macos|windows|linux)\//.test(path)),
    live: files.some((path) => /^dart_cli\/lib\/src\/providers\/(github|gitlab|bitbucket)\.dart$/.test(path)),
  };
}
