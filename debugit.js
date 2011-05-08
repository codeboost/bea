(function() {
  exports.debugIt = function(fn) {
    var tty;
    console.log('Press c to continue or any key to quit');
    tty = require('tty');
    tty.setRawMode(true);
    process.stdin.resume();
    return process.stdin.on("keypress", function(char, key) {
      if (key && key.name === 'c') {
        return fn();
      } else {
        console.log('aborted');
        return process.exit(0);
      }
    });
  };
}).call(this);
