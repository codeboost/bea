(function() {
  var BeaNode, BeaParser, _;
  _ = require('./lib/underscore');
  BeaNode = (function() {
    function BeaNode(text, level, fileName, line) {
      this.text = text;
      this.level = level;
      this.fileName = fileName != null ? fileName : "";
      this.line = line != null ? line : 0;
      this.children = [];
      this.parent = null;
    }
    BeaNode.prototype.addChild = function(node) {
      node.parent = this;
      this.children.push(node);
      return node;
    };
    BeaNode.prototype.findChild = function(text) {
      return _.detect(this.children, function(node) {
        return node.text === text;
      });
    };
    BeaNode.prototype.type = function() {
      var tmp;
      if (this.text.match(/^\/\//)) {
        return "comment";
      }
      tmp = this.text.split(' ');
      return tmp[0];
    };
    BeaNode.prototype.toString = function(joinStr) {
      if (joinStr == null) {
        joinStr = '\n';
      }
      if (this.children.length === 0) {
        return "";
      }
      return _.compact(_.flatten(_.map(this.children, function(node) {
        return [node.text, node.toString(joinStr)];
      }))).join(joinStr);
    };
    BeaNode.prototype.childType = function(type) {
      return _.detect(this.children, function(node) {
        return node.type() === type;
      });
    };
    BeaNode.prototype.matchChildren = function(re) {
      return _.select(this.children, function(node) {
        return node.text.match(re) != null;
      });
    };
    return BeaNode;
  })();
  BeaParser = (function() {
    function BeaParser(fileName, preserveWhitespace) {
      this.fileName = fileName != null ? fileName : "";
      this.preserveWhitespace = preserveWhitespace != null ? preserveWhitespace : false;
      this.root = new BeaNode("", 0, this.fileName, 0);
      this.curNode = this.root;
    }
    BeaParser.prototype.parseLine = function(txt, linenumber) {
      var level, node, rawTxt, tmp, _ref;
      level = (_ref = txt.match(/(^\s+)/g)) != null ? _ref[0].length : void 0;
      level != null ? level : level = 0;
      level++;
      rawTxt = txt.replace(/^\s+|\s+$/g, '');
      if (!(rawTxt.length > 0)) {
        return null;
      }
      if (rawTxt[0] === '#') {
        return null;
      }
      if (rawTxt.length > 2 && rawTxt[0] === '\\' && rawTxt[1] === '#') {
        rawTxt = rawTxt.slice(1);
      }
      if (!this.preserveWhitespace) {
        txt = rawTxt;
      } else {
        txt = txt.replace(/\s+$/g, '');
      }
      node = new BeaNode(txt, level, this.fileName, linenumber + 1);
      if (level === this.curNode.level) {
        this.curNode.parent.addChild(node);
      } else if (level === this.curNode.level + 1) {
        this.curNode.addChild(node);
      } else if (level < this.curNode.level) {
        tmp = this.curNode;
        while (tmp.level > level) {
          tmp = tmp.parent;
        }
        tmp.parent.addChild(node);
      } else {
        throw "Invalid indent on line " + (linenumber + 1) + ": '" + txt + "'";
      }
      return this.curNode = node;
    };
    BeaParser.prototype.parse = function(txt) {
      return _.each(txt.split('\n'), this.parseLine, this);
    };
    return BeaParser;
  })();
  exports.BeaParser = BeaParser;
}).call(this);
