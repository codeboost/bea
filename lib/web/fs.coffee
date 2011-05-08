exports.fsFiles = fsFiles = {}
exports.readFileSync = (fileName, encoding) -> fsFiles[fileName]
exports.realpathSync = (path) -> path
exports.writeFileSync = (fileName, contents) -> fsFiles[fileName] = contents