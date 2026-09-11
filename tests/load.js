// Loads a QML `.pragma library` JS file into a fresh VM context so node can
// test it. `.import "x.js" as Name` lines are resolved the way QML does.
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function loadFile(file) {
  const context = vm.createContext({});
  const source = fs
    .readFileSync(file, "utf8")
    .replace(/^\.pragma library\s*$/m, "")
    .replace(/^\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/gm, (_, dependency, name) => {
      context[name] = loadFile(path.join(path.dirname(file), dependency));
      return "";
    });
  vm.runInContext(source, context, { filename: file });
  return context;
}

module.exports = function load(relativePath) {
  return loadFile(path.join(__dirname, "..", relativePath));
};
