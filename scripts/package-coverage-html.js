#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const yazl = require('yazl');

function collectFiles(rootDir, currentDir = rootDir) {
  const entries = fs.readdirSync(currentDir, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const fullPath = path.join(currentDir, entry.name);
    if (entry.isDirectory()) {
      files.push(...collectFiles(rootDir, fullPath));
      continue;
    }

    if (entry.isFile()) {
      files.push(fullPath);
    }
  }

  return files;
}

function main() {
  const coverageDir = path.resolve(process.cwd(), 'coverage');
  const htmlDir = path.join(coverageDir, 'html');
  const zipPath = path.join(coverageDir, 'coverage_html.zip');

  if (!fs.existsSync(htmlDir)) {
    console.error(`Coverage HTML directory not found: ${htmlDir}`);
    process.exit(1);
  }

  fs.rmSync(zipPath, { force: true });

  const files = collectFiles(htmlDir);
  const zipFile = new yazl.ZipFile();

  for (const filePath of files) {
    const relativePath = path.relative(htmlDir, filePath).split(path.sep).join('/');
    zipFile.addFile(filePath, relativePath);
  }

  zipFile.end();
  zipFile.outputStream
    .on('error', (error) => {
      console.error(error);
      process.exit(1);
    })
    .pipe(fs.createWriteStream(zipPath))
    .on('close', () => {
      console.log(`Packaged coverage HTML report: ${zipPath}`);
    })
    .on('error', (error) => {
      console.error(error);
      process.exit(1);
    });
}

main();
