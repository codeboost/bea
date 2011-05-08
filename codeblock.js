(function() {
  var ClassBlock, Code, CodeBlock, FunctionBlock, NamespaceBlock, beautils, test, _;
  var __hasProp = Object.prototype.hasOwnProperty, __extends = function(child, parent) {
    for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; }
    function ctor() { this.constructor = child; }
    ctor.prototype = parent.prototype;
    child.prototype = new ctor;
    child.__super__ = parent.prototype;
    return child;
  };
  _ = require('./lib/underscore');
  beautils = require('./beautils').u;
  Code = (function() {
    function Code(declaration) {
      this.declaration = declaration;
    }
    Code.prototype.render = function() {
      return this.declaration;
    };
    return Code;
  })();
  CodeBlock = (function() {
    __extends(CodeBlock, Code);
    function CodeBlock(declaration, braced) {
      this.declaration = declaration;
      this.braced = braced != null ? braced : true;
      this.children = [];
    }
    CodeBlock.prototype.empty = function() {
      return this.children.length === 0;
    };
    CodeBlock.prototype.render = function() {
      var content;
      content = _.map(this.children, function(childBlock) {
        return childBlock.render();
      }).join('\n');
      if (this.declaration && this.declaration.length) {
        if (this.braced) {
          return "" + this.declaration + " {\n" + (beautils.tabify(content, 1)) + "\n}";
        } else {
          return "" + this.declaration + "\n" + (beautils.tabify(content, 1));
        }
      } else {
        return "" + content;
      }
    };
    CodeBlock.prototype.add = function(childBlock) {
      var lastblock;
      if (childBlock === void 0) {
        throw "Invalid block";
      }
      if (_.isArray(childBlock)) {
        lastblock = null;
        _.each(childBlock, function(child) {
          if (_.isArray(child)) {
            return lastblock = lastblock != null ? lastblock.add(child) : void 0;
          } else {
            return lastblock = this.add(child);
          }
        }, this);
        return lastblock;
      }
      if (typeof childBlock === "string") {
        childBlock = new Code(childBlock);
      }
      this.children.push(childBlock);
      return childBlock;
    };
    return CodeBlock;
  })();
  NamespaceBlock = (function() {
    __extends(NamespaceBlock, CodeBlock);
    function NamespaceBlock(namespace) {
      NamespaceBlock.__super__.constructor.call(this, "namespace " + namespace);
    }
    NamespaceBlock.prototype.render = function() {
      return NamespaceBlock.__super__.render.call(this) + "\n";
    };
    return NamespaceBlock;
  })();
  ClassBlock = (function() {
    __extends(ClassBlock, CodeBlock);
    function ClassBlock(declaration) {
      ClassBlock.__super__.constructor.call(this, declaration);
    }
    ClassBlock.prototype.render = function() {
      return ClassBlock.__super__.render.call(this) + ";\n";
    };
    return ClassBlock;
  })();
  FunctionBlock = (function() {
    __extends(FunctionBlock, CodeBlock);
    function FunctionBlock(declaration) {
      FunctionBlock.__super__.constructor.call(this, declaration);
    }
    FunctionBlock.prototype.render = function() {
      return FunctionBlock.__super__.render.call(this) + "\n";
    };
    return FunctionBlock;
  })();
  test = function() {
    return _.delay(function() {
      var namespace;
      namespace = new NamespaceBlock("jocT", ["class MyClass", ['void doSomething()', ["int k = 0;", "for (k = 0; k < 100; k++)", ["cout << k << endl;"]], 'std::vector<int> somethingElse(int k, char* value)', ["char* name = new char [k + 1];", "std::vector<int> ret;", "for (int i = 0; i < k; i++)", ["ret.push_back(i)"], "return ret"]]]);
      return console.log(namespace.render());
    }, 10000);
  };
  exports.CodeBlock = {
    Code: Code,
    CodeBlock: CodeBlock,
    NamespaceBlock: NamespaceBlock,
    ClassBlock: ClassBlock,
    FunctionBlock: FunctionBlock
  };
}).call(this);
