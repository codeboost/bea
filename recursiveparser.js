(function() {
  var BeaParser, RecursiveParser, fs, _;
  var __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };
  fs = require('fs');
  BeaParser = require('./beaparser').BeaParser;
  _ = require('underscore');
  RecursiveParser = (function() {
    function RecursiveParser() {
      this.includes = [];
    }
    RecursiveParser.prototype.parseFile = function(fileName) {
      var contents, parser, ret;
      contents = fs.readFileSync(fileName, "ascii");
      if (!contents) {
        this.error("Cannot read file '" + fileName + "'.");
        return false;
      }
      this.includes.push(fileName);
      parser = new BeaParser(fileName);
      parser.parse(contents);
      ret = this.processIncludes(parser.root);
      return ret;
    };
    RecursiveParser.prototype.error = function(msg) {
      return console.log(msg);
    };
    RecursiveParser.prototype.warn = function(msg, node) {
      var fileName, line, _ref, _ref2;
      fileName = (_ref = (node != null ? node.fileName : void 0)) != null ? _ref : "";
      line = (_ref2 = (node != null ? node.line : void 0)) != null ? _ref2 : 0;
      if (line > 0) {
        line = "(" + line + ")";
      } else {
        line = "";
      }
      return console.log("" + fileName + "(" + line + "): warning: " + msg);
    };
    RecursiveParser.prototype.include = function(node) {
      var fileName, _ref;
      fileName = (_ref = node.text.match(/^@include\s+\"(.+)\"/, "")) != null ? _ref[1] : void 0;
      if (!fileName) {
        return this.warn("Invalid include directive", node);
      }
      fileName = fs.realpathSync(fileName);
      if (_.any(this.includes, function(nf) {
        return nf === fileName;
      })) {
        return this.warn("File " + fileName + " already included!", node);
      }
      console.log('Included file ' + fileName);
      return this.parseFile(fileName);
    };
    RecursiveParser.prototype.processIncludes = function(root) {
      var children, gr;
      children = root.children;
      gr = 0;
      _.each(root.children, __bind(function(node, i) {
        var ret, retc, _ref;
        if (node.type() === '@include') {
          ret = this.include(node);
          retc = (_ref = ret != null ? ret.children : void 0) != null ? _ref : [];
          children = children.slice(0, i + gr).concat(retc, children.slice(i + gr + 1));
          if (retc.length) {
            return gr = gr + retc.length - 1;
          }
        }
      }, this));
      root.children = children;
      return root;
    };
    return RecursiveParser;
  })();
  exports.RecursiveParser = RecursiveParser;
}).call(this);
