(function() {
  var fsFiles;
  exports.fsFiles = fsFiles = {};
  exports.readFileSync = function(fileName, encoding) {
    return fsFiles[fileName];
  };
  exports.realpathSync = function(path) {
    return path;
  };
  exports.writeFileSync = function(fileName, contents) {
    return fsFiles[fileName] = contents;
  };
}).call(this);
