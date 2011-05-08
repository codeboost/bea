(function() {
  var BeaLoader, BeaParser, ClassConverter, CodeBlock, MessageLogger, RecursiveParser, beautils, doConvert, fs, mgr, util, _;
  var __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; }, __hasProp = Object.prototype.hasOwnProperty, __extends = function(child, parent) {
    for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; }
    function ctor() { this.constructor = child; }
    ctor.prototype = parent.prototype;
    child.prototype = new ctor;
    child.__super__ = parent.prototype;
    return child;
  };
  _ = require('./lib/underscore');
  BeaParser = require('./beaparser').BeaParser;
  CodeBlock = require('./codeblock').CodeBlock;
  mgr = require('./mgr');
  ClassConverter = require('./classconvert').ClassConverter;
  beautils = require('./beautils');
  fs = require('fs');
  util = require('util');
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
      return this.parseFile(fileName);
    };
    RecursiveParser.prototype.processIncludes = function(root) {
      var children;
      children = root.children;
      _.each(root.children, __bind(function(node, i) {
        var ret, retc, _ref;
        if (node.type() === '@include') {
          ret = this.include(node);
          retc = (_ref = ret != null ? ret.children : void 0) != null ? _ref : [];
          return children = children.slice(0, i).concat(retc, children.slice(i + 1));
        }
      }, this));
      root.children = children;
      return root;
    };
    return RecursiveParser;
  })();
  MessageLogger = (function() {
    function MessageLogger() {
      this.warnings = 0;
    }
    MessageLogger.prototype.warn = function(msg, node) {
      var fileName, line, _ref, _ref2, _ref3;
      _ref3 = [(_ref = (node != null ? node.fileName : void 0)) != null ? _ref : "", (_ref2 = (node != null ? node.line : void 0)) != null ? _ref2 : 0], fileName = _ref3[0], line = _ref3[1];
      console.log("" + fileName + "(" + line + "): warning: " + msg);
      return this.warnings++;
    };
    MessageLogger.prototype.info = function(msg, node) {
      var fileName, line, _ref, _ref2, _ref3;
      _ref3 = [(_ref = (node != null ? node.fileName : void 0)) != null ? _ref : "", (_ref2 = (node != null ? node.line : void 0)) != null ? _ref2 : 0], fileName = _ref3[0], line = _ref3[1];
      if (this.verbose) {
        return console.log(("" + fileName + "(" + line + ") : ") + msg);
      }
    };
    MessageLogger.prototype.error = function(msg, node) {
      var fileName, line, _ref, _ref2, _ref3;
      _ref3 = [(_ref = (node != null ? node.fileName : void 0)) != null ? _ref : "", (_ref2 = (node != null ? node.line : void 0)) != null ? _ref2 : 0], fileName = _ref3[0], line = _ref3[1];
      console.log("" + fileName + "(" + line + "): warning: " + msg);
      return process.exit(-1);
    };
    return MessageLogger;
  })();
  BeaLoader = (function() {
    __extends(BeaLoader, MessageLogger);
    function BeaLoader(curFileName) {
      this.curFileName = curFileName;
      this.classes = [];
      this.namespaces = {};
      this.typeMgr = new mgr.TypeManager(this, this.namespaces);
      this.constants = [];
      this.verbose = true;
      this.hFilename = "";
      this.cppFilename = "";
      this.targetNamespace = "";
      this.options = {
        manual: false,
        typeManager: this.typeMgr,
        logger: this,
        mtypes: false
      };
      this.stats = {
        classes: 0,
        converted: 0,
        ignored: 0,
        manual: 0,
        declared: 0,
        accessors: 0,
        failed: 0,
        constants: 0,
        typesConverted: 0,
        typesIgnored: 0
      };
    }
    BeaLoader.prototype.setTargetNamespace = function(node) {
      this.targetNamespace = node.text.replace(/^@targetNamespace\s+/, '');
      return this.targetNamespace = this.targetNamespace.replace(/\"|\'/g);
    };
    BeaLoader.prototype.addClass = function(classNode, namespace) {
      this.classes.push({
        namespace: namespace,
        node: classNode
      });
      if (!classNode.text.match(/^@static\s+/)) {
        return this.typeMgr.addWrapped(classNode, namespace);
      }
    };
    BeaLoader.prototype.addConst = function(node) {
      return _.each(node.children, __bind(function(con) {
        return this.constants.push(con.text);
      }, this));
    };
    BeaLoader.prototype.namespace = function(nsNode) {
      var nsname;
      nsname = nsNode.text.replace(/^@namespace\s+/, '');
      return _.each(nsNode.children, __bind(function(node) {
        switch (node.type()) {
          case "@class":
            return this.addClass(node, nsname);
          case "@static":
            return this.addClass(node, nsname);
          case "@type":
            return this.typeMgr.add(node, nsname);
          default:
            return this.warn("Unexpected '" + (node.type()) + "' within namespace " + nsname, node);
        }
      }, this));
    };
    BeaLoader.prototype.setHFileName = function(node) {
      var filename;
      if (this.hFilename !== "") {
        return this.warn("h file name already set.", node);
      }
      filename = node.text.replace(/^@hfilename\s+/, "");
      filename = filename.replace(/\"|\'/g, "");
      return this.hFilename = filename;
    };
    BeaLoader.prototype.setCPPFileName = function(node) {
      var filename;
      if (this.cppFilename !== "") {
        return this.warn("cpp file name already set.", node);
      }
      filename = node.text.replace(/^@cppfilename\s+/, "");
      filename = filename.replace(/\"|\'/g, "");
      return this.cppFilename = filename;
    };
    BeaLoader.prototype.addHeader = function(hNode) {
      return this.header = hNode.toString('\n');
    };
    BeaLoader.prototype.addCpp = function(cppNode) {
      return this.cpp = cppNode.toString('\n');
    };
    BeaLoader.prototype.convertConstants = function() {
      var fn;
      fn = new CodeBlock.FunctionBlock("void ExposeConstants(v8::Handle<v8::Object> target)");
      _.each(this.constants, __bind(function(constant) {
        fn.add("BEA_DEFINE_CONSTANT(target, " + constant + ");");
        return this.stats.constants++;
      }, this));
      return fn;
    };
    BeaLoader.prototype.createBeaExposer = function(exposed) {
      var declaClass, declaNS, fn, implNS, ret;
      if (!_.isArray(exposed)) {
        return false;
      }
      declaNS = new CodeBlock.NamespaceBlock(this.targetNamespace);
      declaClass = declaNS.add(new CodeBlock.ClassBlock("class Project"));
      declaClass.add(new CodeBlock.CodeBlock("public:", false)).add("static void expose(v8::Handle<v8::Object> target);");
      implNS = new CodeBlock.NamespaceBlock(this.targetNamespace);
      fn = implNS.add(new CodeBlock.FunctionBlock("void Project::expose(v8::Handle<v8::Object> target)"));
      _.each(exposed, function(clExposed) {
        return fn.add(clExposed + "::_InitJSObject(target);");
      });
      fn.add("ExposeConstants(target);");
      ret = {
        h: declaNS,
        cpp: implNS
      };
      return ret;
    };
    BeaLoader.prototype.ifdefH = function(header, fileName) {
      var cond, hFile;
      hFile = new CodeBlock.CodeBlock;
      cond = fileName.replace(/\./, '_').toUpperCase();
      hFile.add("#ifndef " + cond);
      hFile.add("#define " + cond);
      hFile.add(header);
      hFile.add("#endif //#ifndef " + cond);
      return hFile;
    };
    BeaLoader.prototype.convertFull = function() {
      var convClasses, cppFile, hFile, nsBea, nsCPP, nsH, ret;
      cppFile = new CodeBlock.CodeBlock;
      hFile = new CodeBlock.CodeBlock;
      cppFile.add(this.cpp);
      hFile.add(this.header);
      nsBea = cppFile.add(new CodeBlock.NamespaceBlock("bea"));
      nsBea.add(this.typeMgr.createConversions());
      convClasses = [];
      _.each(this.classes, __bind(function(cl) {
        var cv, ret;
        this.stats.classes++;
        cv = new ClassConverter(this.options);
        ret = cv.processClass(cl, this.targetNamespace);
        if (!ret.global.empty()) {
          cppFile.add(ret.global);
        }
        if (!ret.impl.empty()) {
          cppFile.add(ret.impl);
        }
        convClasses.push(ret.eClassName);
        return hFile.add(ret.decla);
      }, this));
      nsCPP = cppFile.add(new CodeBlock.NamespaceBlock(this.targetNamespace));
      nsH = hFile.add(new CodeBlock.NamespaceBlock(this.targetNamespace));
      nsCPP.add(this.convertConstants());
      nsH.add("static void ExposeConstants(v8::Handle<v8::Object> target);");
      ret = this.createBeaExposer(convClasses);
      if (ret.h) {
        hFile.add(ret.h);
      }
      if (ret.cpp) {
        cppFile.add(ret.cpp);
      }
      hFile = this.ifdefH(hFile, this.hFilename);
      fs.writeFileSync(this.cppFilename, cppFile.render(), 'ascii');
      return fs.writeFileSync(this.hFilename, hFile.render(), 'ascii');
    };
    BeaLoader.prototype.convertManual = function() {
      var cppFile, nsBea, res;
      res = fs.statSync(this.cppFilename);
      if (res && res.size > 0 && !this.options.force) {
        this.error("" + this.cppFilename + " already exists. Use -f switch to overwrite.");
        return false;
      }
      cppFile = new CodeBlock.CodeBlock;
      cppFile.add(this.cpp);
      cppFile.add("using namespace bea;");
      nsBea = new CodeBlock.NamespaceBlock("bea");
      nsBea.add(this.typeMgr.createConversions(this.options.manual));
      if (!nsBea.empty()) {
        cppFile.add(nsBea);
      }
      _.each(this.classes, __bind(function(cl) {
        var cv, ret;
        this.stats.classes++;
        cv = new ClassConverter(this.options);
        ret = cv.processClass(cl, this.targetNamespace);
        if (!ret.global.empty()) {
          cppFile.add(ret.global);
        }
        if (!ret.impl.empty()) {
          return cppFile.add(ret.impl);
        }
      }, this));
      return fs.writeFileSync(this.cppFilename, cppFile.render(), 'ascii');
    };
    BeaLoader.prototype.CONVERT = function() {
      if (this.options.manual) {
        return this.convertManual();
      } else {
        return this.convertFull();
      }
    };
    BeaLoader.prototype.load = function(curFileName) {
      var parser, root;
      this.curFileName = curFileName;
      parser = new RecursiveParser;
      root = parser.parseFile(this.curFileName);
      if (!root) {
        return false;
      }
      _.each(root.children, __bind(function(node, i) {
        switch (node.type()) {
          case "@targetNamespace":
            return this.setTargetNamespace(node);
          case "@namespace":
            return this.namespace(node);
          case "@header":
            return this.addHeader(node);
          case "@cpp":
            return this.addCpp(node);
          case "@hfilename":
            return this.setHFileName(node);
          case "@cppfilename":
            return this.setCPPFileName(node);
          case "@const":
            return this.addConst(node);
          case "@comment":
            return "";
          default:
            return this.warn("Unknown directive: " + (node.type()), node);
        }
      }, this));
      if (_.isEmpty(this.targetNamespace)) {
        this.warn("@targetNamespace not defined. ", parser.root);
        this.targetNamespace = 'targetNamespace';
      }
      return true;
    };
    return BeaLoader;
  })();
  doConvert = function(bea, beaFile) {
    var start;
    start = Date.now();
    if (bea.load(beaFile)) {
      console.log("Successfully loaded and parsed " + beaFile);
    } else {
      console.log("Fatal error: Could not parse " + beaFile);
      process.exit(-2);
    }
    if (!bea.options.manual) {
      console.log("Output header file: " + bea.hFilename);
    } else {
      console.log("*** -manual switch present. Only producing manual conversions.");
    }
    console.log("Output cpp file: " + bea.cppFilename);
    console.log("Converting...");
    bea.CONVERT();
    console.log("Conversion finished in " + (Date.now() - start) + " ms.");
    console.log("Conversion results:");
    console.log(util.inspect(bea.stats));
    if (bea.stats.manual > 0 && !bea.options.manual) {
      console.log("***");
      console.log("Note: There are " + bea.stats.manual + " manual functions which have not been converted. You must implement these manually.");
      return console.log("Tip: You can generate the empty methods with the -manual switch (must output to different .cpp file).");
    }
  };
  exports.doConvert = doConvert;
  exports.BeaLoader = BeaLoader;
}).call(this);
