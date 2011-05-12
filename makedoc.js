(function() {
  var BeaParser, CodeBlock, confluence, contents, debugIt, fs, getCode, parser, processChild, util, _;
  BeaParser = require('./beaparser').BeaParser;
  CodeBlock = require('./codeblock');
  _ = require('underscore');
  debugIt = require('./debugit').debugIt;
  util = require('util');
  fs = require('fs');
  if (process.argv.length < 3) {
    console.log('Cannot! You must specify a file');
    process.exit(-1);
  }
  getCode = function(node, lang) {
    var childBlock, title, _ref;
    title = (_ref = node.children[0].text.match(/\s*:\s*(.+)/)) != null ? _ref[1] : void 0;
    if (title) {
      title = '|title=' + title;
    }
    node.children[0].text = '';
    return childBlock = ("{newcode:" + lang + title + "}\n") + node.toString() + "{newcode}";
  };
  processChild = function(node) {
    var childBlock, nodeText, _ref;
    childBlock = "";
    if ((_ref = node.children) != null ? _ref.length : void 0) {
      if (/^\s*\/\/C\+\+/.test(node.children[0].text)) {
        childBlock = getCode(node, "CPP");
      } else if (node.children && /^\s*\/\/[J|j]ava[s|S]cript/.test(node.children[0].text)) {
        childBlock = getCode(node, "javascript");
      } else {
        childBlock = _.map(node.children, function(node) {
          return processChild(node);
        }).join('');
      }
    }
    if (node.level < 2) {
      nodeText = "\nh" + (node.level + 1) + "." + node.text;
    } else {
      nodeText = node.text;
    }
    return nodeText + "\n" + childBlock;
  };
  confluence = function(root) {
    var ret;
    ret = processChild(root);
    return console.log(ret);
  };
  parser = new BeaParser(process.argv[2], true, true);
  contents = fs.readFileSync(process.argv[2], 'ascii');
  parser.parse(contents);
  confluence(parser.root);
}).call(this);
