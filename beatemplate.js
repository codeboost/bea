(function() {
  var BeaParser, TemplateManager, debugIt, fs, _;
  _ = require('./lib/underscore');
  BeaParser = require('./beaparser').BeaParser;
  fs = require('fs');
  debugIt = require('./debugIt').debugIt;
  TemplateManager = (function() {
    function TemplateManager(fileName) {
      var str;
      if (fileName == null) {
        fileName = 'code-templates.bea';
      }
      str = fs.readFileSync(fileName, 'ascii');
      if (str.length === 0) {
        throw 'Template load failed: #{fileName}';
      }
      this.parser = new BeaParser(true);
      try {
        this.parser.parse(str);
      } catch (e) {
        throw 'Template load failed #{fileName}: ' + e;
      }
    }
    TemplateManager.prototype.getTemplate = function(name) {
      var childNode;
      childNode = this.parser.root.findChild(name);
      if (childNode) {
        return childNode.toString();
      }
      return "";
    };
    TemplateManager.prototype.render = function(name, obj) {
      var str;
      if (name.match(/^template\s+/) === null) {
        name = 'template ' + name;
      }
      str = this.getTemplate(name);
      if (!(str.length > 0)) {
        return "";
      }
      _.each(obj, function(val, key) {
        if (_.isArray(val)) {
          val = val.join('\n');
        }
        return str = str.split('$' + key).join(val);
      });
      return str;
    };
    return TemplateManager;
  })();
  exports.TemplateManager = TemplateManager;
}).call(this);
