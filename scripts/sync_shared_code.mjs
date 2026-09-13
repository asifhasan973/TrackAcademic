import * as fs from "fs";
import * as path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, "..");
const backendSrc = path.join(rootDir, "backend", "src");
const functionsShared = path.join(rootDir, "functions", "src", "shared");

console.log("[SYNC] Synchronizing shared backend modules to functions/src/shared...");

if (!fs.existsSync(functionsShared)) {
  fs.mkdirSync(functionsShared, { recursive: true });
}

// Copy directory recursively
function copyDir(src, dest) {
  if (!fs.existsSync(dest)) {
    fs.mkdirSync(dest, { recursive: true });
  }

  const entries = fs.readdirSync(src, { withFileTypes: true });
  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);

    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else if (entry.isFile() && (entry.name.endsWith(".ts") || entry.name.endsWith(".js"))) {
      let content = fs.readFileSync(srcPath, "utf8");
      // Adjust relative imports from .js to .js or compatible
      fs.writeFileSync(destPath, content);
    }
  }
}

copyDir(path.join(backendSrc, "operations"), path.join(functionsShared, "operations"));
copyDir(path.join(backendSrc, "middleware"), path.join(functionsShared, "middleware"));
fs.copyFileSync(path.join(backendSrc, "types.ts"), path.join(functionsShared, "types.ts"));
fs.copyFileSync(path.join(backendSrc, "firebaseAdmin.ts"), path.join(functionsShared, "firebaseAdmin.ts"));

console.log("[SYNC] Synchronization complete.");
