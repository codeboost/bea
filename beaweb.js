(function() {
  var BeaWeb;
  require.load([
    {
      id: 'underscore',
      url: 'lib/underscore.js'
    }, {
      id: 'fs',
      url: 'lib/web/fs.js'
    }, {
      id: 'util',
      url: 'lib/web/util.js'
    }, 'beaparser.js', 'codeblock.js', 'mgr.js', 'classconvert.js', 'beautils.js', 'bealoader.js', 'snippets.js'
  ]);
  BeaWeb = (function() {
    function BeaWeb() {
      this.bealoader = require('bealoader');
      this.beaSource = "Enter bea text here";
      this.fileSystem = require('fs').fsFiles;
      this.fileSystem['out_h'] = '';
      this.fileSystem['out_cpp'] = '';
    }
    BeaWeb.prototype.beaSourceChange = function() {
      return this.fileSystem['beaSource'] = this.beaSource;
    };
    BeaWeb.prototype.compile = function() {
      var bea;
      bea = new this.bealoader.BeaLoader('beaSource');
      bea.hFilename = 'out_h';
      bea.cppFilename = 'out_cpp';
      return this.bealoader.doConvert(bea, 'beaSource');
    };
    return BeaWeb;
  })();
  window.BeaWeb = BeaWeb;
}).call(this);
