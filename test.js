(function() {
  var debugIt, util;
  util = require('util');
  debugIt = require('./debugit').debugIt;
  exports.some = 1;
  console.log(exports);
  console.log(module.exports);
}).call(this);
