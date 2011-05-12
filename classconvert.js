(function() {
  var ClassConverter, CodeBlock, FnCall, beautils, snippets, _;
  var __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };
  _ = require('underscore');
  beautils = require('./beautils').u;
  CodeBlock = require('./codeblock').CodeBlock;
  snippets = require('./snippets');
  /*
  TODO:
  	- Warn if class does not define a constructor/insert default constructor

  */
  FnCall = (function() {
    function FnCall(retVal, name, argList) {
      this.retVal = retVal;
      this.name = name;
      this.argList = argList;
    }
    FnCall.prototype.render = function(term) {
      var cl;
      if (term == null) {
        term = ';';
      }
      cl = this.name + '(' + this.argList + ')' + term;
      if (this.retVal.length) {
        return this.retVal + ' = ' + cl;
      }
      return cl;
    };
    return FnCall;
  })();
  ClassConverter = (function() {
    function ClassConverter(options) {
      this.options = options;
      this.classFns = {};
      this.className = "";
      this.nativeClassName = "";
      this.exposed = true;
      this.namespace = '';
      this.nsBlock = null;
      this.accessors = {};
      this.hasPostAllocator = false;
      this.destructorNode = null;
      this.typeManager = this.options.typeManager;
      this.logger = this.options.logger;
    }
    ClassConverter.prototype.warn = function(msg, node) {
      this.logger.warn(msg, node);
      return false;
    };
    ClassConverter.prototype.processClass = function(cl, targetNamespace) {
      var declaNs, ret, _ref;
      this.namespace = cl.namespace;
      if (/^@static\s+/.test(cl.node.text)) {
        this.isStatic = true;
      } else {
        this.isStatic = false;
      }
      _ref = beautils.parseClassDirective(cl.node), this.className = _ref[0], this.exposedName = _ref[1];
      this.nativeClassName = this.className;
      this.className = 'J' + this.nativeClassName;
      this.classType = (new beautils.Type(this.nativeClassName, this.namespace)).fullType();
      this.nsBlock = new CodeBlock.NamespaceBlock(targetNamespace);
      _.each(cl.node.children, __bind(function(child) {
        return this.processFunNode(child);
      }, this));
      this.globalBlock = new CodeBlock.CodeBlock;
      if (!this.options.manual) {
        if (!this.isStatic) {
          this.globalBlock.add("DECLARE_EXPOSED_CLASS(" + this.classType + ");");
          if (!this.classFns["__constructor"]) {
            this.warn("No constructor defined for " + this.className + "!", cl.node);
          }
        } else {
          this.globalBlock.add("DECLARE_STATIC(" + targetNamespace + "::" + this.className + ");");
        }
      }
      if (!this.options.manual && this.destructorNode) {
        this.nsBlock.add(this.createDestructor());
      }
      _.each(this.classFns, __bind(function(fn, name) {
        var ret;
        ret = this.createConversion(name, fn.type, fn);
        if (ret) {
          return this.nsBlock.add(ret);
        }
      }, this));
      if (!this.options.manual) {
        _.each(this.accessors, __bind(function(accessor, name) {
          return this.nsBlock.add(this.createAccessor(accessor, name));
        }, this));
      }
      if (!this.options.manual) {
        this.nsBlock.add(this.createInitFn());
      }
      if (!this.options.manual) {
        declaNs = new CodeBlock.NamespaceBlock(targetNamespace);
        declaNs.add(this.createDeclaration());
      }
      ret = {
        global: this.globalBlock,
        impl: this.nsBlock,
        decla: declaNs,
        tests: this.testBlock,
        eClassName: this.className,
        tClassName: this.nativeClassName
      };
      return ret;
    };
    ClassConverter.prototype.processFunNode = function(node) {
      var callNode, fn, isManual, isPostAllocator, nodeText, str;
      if (/^@noexpose/.test(node.text)) {
        this.exposed = false;
        return false;
      }
      isManual = /^@manual\s+/.test(node.text);
      if (isManual) {
        str = node.text.substring(7);
      } else {
        str = node.text;
      }
      if (/^\@accessor\s+/.test(node.text)) {
        return this.parseAccessor(node);
      }
      isPostAllocator = false;
      if (/^\@postAllocator/.test(node.text)) {
        if (this.isStatic) {
          return this.warn("Postallocator for static class ignored");
        }
        str = "void __postAllocator()";
        this.hasPostAllocator = true;
      }
      if (/^\@destructor/.test(node.text)) {
        if (this.isStatic) {
          return this.warn("Destructor for static class ignored");
        }
        this.destructorNode = node;
        return true;
      }
      fn = beautils.parseDeclaration(str, this.namespace);
      if (!fn) {
        return this.warn("Cannot parse method declaration: '" + str + "'. Ignoring.", node);
      }
      if (fn.type.rawType === this.nativeClassName && fn.name === "") {
        fn.name = '__constructor';
      }
      if (isManual) {
        this.logger.stats.manual++;
      }
      fn.org = str;
      fn.manual = isManual;
      fn.requiredArgs = this.requiredArgs(fn.args);
      fn.sublines = node.children;
      fn.node = node;
      callNode = _.detect(fn.sublines, function(subline) {
        return /^\@call/.test(subline.text);
      });
      if (callNode) {
        nodeText = callNode.text.replace(/^\@call\s*/, "");
        fn.callText = _.compact([nodeText, callNode.toString()]).join('\n');
        fn.sublines = _.without(fn.sublines, callNode);
      }
      if (this.classFns[fn.name]) {
        if (!beautils.hasOverload(this.classFns[fn.name], fn)) {
          this.classFns[fn.name].push(fn);
        }
      } else {
        this.classFns[fn.name] = [fn];
        this.classFns[fn.name].name = fn.name;
        this.classFns[fn.name].type = fn.type;
      }
      return true;
    };
    ClassConverter.prototype.parseAccessor = function(node) {
      var accessor, parts, read, write, _ref, _ref2;
      parts = node.text.match(/^\@accessor\s+(\w+)\s+(\w+)/);
      if (!(parts && parts.length > 1)) {
        return this.warn("Invalid accessor definition. Ignored.", node);
      }
      accessor = {
        name: parts[1],
        type: parts[2]
      };
      if (this.accessors[accessor.name]) {
        return this.warn("Accessor: '" + accessor.name + "': accessor already defined. Second definition ignored", node);
      }
      if (!accessor.type) {
        accessor.type = 'int';
        this.warn("Accessor '" + accessor.name + "' : type not defined, int assumed", node);
      }
      read = node.childType("@get");
      write = node.childType("@set");
      if (!read) {
        this.warn("Accessor '" + accessor.name + "': get not defined", node);
      }
      if (!write) {
        this.warn("Accessor '" + accessor.name + "': set not defined", node);
      }
      accessor.type = new beautils.Type(accessor.type, this.namespace);
      accessor.read = (_ref = read != null ? read.text.replace(/^@get\s*/, '') : void 0) != null ? _ref : "";
      accessor.write = (_ref2 = write != null ? write.text.replace(/^@set\s*/, '') : void 0) != null ? _ref2 : "";
      accessor.node = node;
      return this.accessors[accessor.name] = accessor;
    };
    ClassConverter.prototype.createDeclaration = function() {
      var block, decBlock;
      if (!!this.options.manual) {
        return false;
      }
      decBlock = new CodeBlock.ClassBlock("class " + this.className);
      block = decBlock.add(new CodeBlock.CodeBlock("protected:", false)).add(new CodeBlock.CodeBlock);
      if (this.destructorNode) {
        block.add("//Destructor");
        block.add(snippets.decl.destructor());
        this.logger.stats.declared++;
      }
      block.add("//Exported methods");
      _.each(this.classFns, __bind(function(fn, name) {
        block.add(snippets.decl.method(name));
        return this.logger.stats.declared++;
      }, this));
      if (_.size(this.accessors)) {
        block.add("//Accessors - Getters");
        _.each(this.accessors, __bind(function(acc, name) {
          block.add(snippets.decl.accessorGet(name));
          return this.logger.stats.declared++;
        }, this));
        block.add("//Accessors - Setters");
        _.each(this.accessors, __bind(function(acc, name) {
          block.add(snippets.decl.accessorSet(name));
          return this.logger.stats.declared++;
        }, this));
      }
      decBlock.add(new CodeBlock.CodeBlock("public:", false)).add("static void _InitJSObject(v8::Handle<v8::Object> target);");
      return decBlock;
    };
    ClassConverter.prototype.createInitFn = function() {
      var initFn;
      initFn = new CodeBlock.FunctionBlock(snippets.decl.InitJSObject(this.className));
      if (!this.isStatic) {
        initFn.add(snippets.impl.exposeClass(this.classType, this.exposedName));
      } else {
        initFn.add(snippets.impl.exposeObject(this.className, this.exposedName));
      }
      if (this.destructorNode) {
        initFn.add("//Destructor");
        initFn.add("obj->setDestructor(__destructor);");
      }
      initFn.add("//Exposed Methods");
      _.each(this.classFns, __bind(function(fn, name) {
        switch (name) {
          case '__constructor':
            return initFn.add("obj->setConstructor(__constructor);");
          case '__postAllocator':
            return initFn.add("obj->setPostAllocator(__postAllocator);");
          default:
            return initFn.add("obj->exposeMethod(\"" + name + "\", " + name + ");");
        }
      }, this));
      initFn.add("//Accessors");
      _.each(this.accessors, __bind(function(accessor, name) {
        return initFn.add("obj->exposeProperty(\"" + name + "\", accGet_" + name + ", accSet_" + name + ");");
      }, this));
      initFn.add("//Expose object to the Javascript");
      if (this.exposed) {
        initFn.add("obj->exposeTo(target);");
      } else {
        initFn.add("//Class not exposed to the javascript. Must instantiate and expose it manually");
        initFn.add("//obj->exposeTo(target);");
      }
      return initFn;
    };
    ClassConverter.prototype.requiredArgs = function(args) {
      var count;
      count = 0;
      _.each(args, function(arg) {
        if (!arg.value) {
          return count++;
        }
      });
      return count;
    };
    ClassConverter.prototype.createAccessor = function(accessor, name) {
      var block, fn;
      block = new CodeBlock.CodeBlock;
      if (this.classFns[name]) {
        this.warn("Accessor '" + name + "': Class '" + this.nativeClassName + "' already exports method '" + name + "'", accessor.node);
      }
      block.add("//Get Accessor " + name + " (" + (this.nativeType(accessor.type)) + ")");
      fn = block.add(new CodeBlock.FunctionBlock(snippets.impl.accessorGet(this.className, name)));
      fn.add(snippets.impl.accessorGetImpl("" + this.classType + "*", this.nativeType(accessor.type), accessor.read));
      block.add("//Set Accessor " + name + " (" + (this.nativeType(accessor.type)) + ")");
      fn = block.add(new CodeBlock.FunctionBlock(snippets.impl.accessorSet(this.className, name)));
      fn.add(snippets.impl.accessorSetImpl("" + this.classType + "*", this.nativeType(accessor.type), accessor.write));
      this.logger.stats.accessors++;
      return block;
    };
    ClassConverter.prototype.nativeType = function(type) {
      var nativeType;
      nativeType = type.fullType();
      if (this.typeManager.isWrapped(type)) {
        return nativeType + '*';
      }
      return nativeType;
    };
    ClassConverter.prototype.convertArg = function(arg, narg) {
      var argType, argv, nativeType;
      nativeType = this.nativeType(arg.type);
      if (arg.type.rawType === 'void') {
        this.warn('Type #{arg.type.fullType()} used as argument type.');
      }
      if (!arg.value) {
        return ("" + nativeType + " " + arg.name + " = ") + snippets.FromJS(nativeType, "args[" + narg + "]", narg);
      } else {
        argv = arg.value;
        argType = this.typeManager.typeFromValue(argv);
        if (argType) {
          if (argv.indexOf("::") === -1) {
            argv = argType.namespace + '::' + argv;
          }
          if (argType.wrapped && !arg.type.isPointer) {
            argv = '&' + argv;
          }
        }
        return ("" + nativeType + " " + arg.name + " = ") + snippets.Optional(nativeType, narg, argv);
      }
    };
    ClassConverter.prototype.typeif = function(args) {
      var ifclause;
      ifclause = [];
      _.each(args, __bind(function(arg, i) {
        if (!arg.value) {
          return ifclause.push(snippets.Is(this.nativeType(arg.type), "args[" + i + "]", ''));
        } else {
          return ifclause.push(snippets.OptionalIs(this.nativeType(arg.type), i, ''));
        }
      }, this));
      if (ifclause.length === 0) {
        return 'args.Length() == 0';
      }
      return ifclause.join(' && ');
    };
    ClassConverter.prototype.convertArguments = function(block, args) {
      return _.each(args, __bind(function(arg, i) {
        return block.add(this.convertArg(arg, i));
      }, this));
    };
    ClassConverter.prototype.createCall = function(block, overload) {
      var argList, fnName, fnRet, fncall, names, nativeType, retVal, tmp, _ref;
      if (overload.manual) {
        block.add('//TODO: Enter code here');
        block.add('return args.This();');
        return block;
      }
      this.convertArguments(block, overload.args);
      if (!this.isStatic && overload.name !== "__constructor") {
        block.add(("" + this.classType + "* _this = ") + snippets.FromJS(this.classType + '*', "args.This()", 0));
      }
      _.each(overload.sublines, __bind(function(line) {
        return block.add(new CodeBlock.Code(line.text));
      }, this));
      names = [];
      _.each(overload.args, __bind(function(arg) {
        if (!this.typeManager.knownType(arg.type)) {
          this.warn("Undefined type: '" + (arg.type.fullType()) + "' declared as '" + arg.type.org + "'", overload.node);
        }
        if (this.typeManager.isWrapped(arg.type) && !arg.type.isPointer) {
          return names.push('*' + arg.name);
        } else {
          return names.push(arg.name);
        }
      }, this));
      fnRet = '';
      retVal = 'return args.This();';
      argList = names.join(', ');
      if (overload.type.rawType !== 'void') {
        nativeType = this.nativeType(overload.type);
        fnRet = nativeType + ' fnRetVal';
        retVal = "return " + snippets.ToJS(nativeType, "fnRetVal");
      }
      fnName = overload.name;
      if (this.isStatic) {
        fnName = this.namespace + '::' + fnName;
      } else {
        if (overload.name === '__postAllocator') {
          fnName = '';
        } else {
          fnName = '_this->' + fnName;
        }
      }
      if (fnName.length) {
        if ((_ref = overload.callText) != null ? _ref.length : void 0) {
          fncall = new CodeBlock.CodeBlock(overload.callText, false);
        } else {
          if (!this.typeManager.isWrapped(overload.type)) {
            fncall = new FnCall(fnRet, fnName, argList);
          } else {
            if (overload.name === '__constructor') {
              fncall = new FnCall(fnRet, 'new ' + overload.type.fullType(), argList);
              retVal = "return v8::External::New(fnRetVal);";
            } else {
              tmp = new FnCall('', fnName, argList);
              fncall = new FnCall(fnRet, 'new ' + overload.type.fullType(), tmp.render(''));
            }
          }
        }
        block.add(fncall.render());
      }
      block.add(retVal);
      return block;
    };
    ClassConverter.prototype.allManual = function(overloads) {
      return _.all(overloads, function(overload) {
        return overload.manual;
      });
    };
    ClassConverter.prototype.anyManual = function(overloads) {
      return _.any(overloads, function(overload) {
        return overload.manual;
      });
    };
    ClassConverter.prototype.False = function(expr) {
      return false;
    };
    ClassConverter.prototype.createConversion = function(name, type, overloads) {
      var argc, fnBlock, minargs;
      if (!_.isArray(overloads)) {
        return this.False(this.logger.stats.failed++);
      }
      if (this.options.manual && !this.allManual(overloads)) {
        return this.False(this.logger.stats.ignored++);
      }
      fnBlock = new CodeBlock.FunctionBlock(snippets.impl.method(this.className, name));
      argc = [];
      overloads = _.sortBy(overloads, function(o) {
        argc.push(o.requiredArgs);
        return -o.requiredArgs;
      });
      minargs = _.min(argc);
      fnBlock.add(snippets.impl.methodBegin(minargs));
      if (overloads.length === 1) {
        fnBlock.add("//" + overloads[0].org);
        if (overloads[0].manual && !this.options.manual) {
          return this.False(this.logger.stats.ignored++);
        }
        this.createCall(fnBlock, overloads[0]);
        this.logger.stats.converted++;
      } else {
        if (this.anyManual(overloads) && !this.options.manual) {
          return this.False(this.logger.stats.ignored += overloads.length);
        }
        _.each(overloads, __bind(function(overload) {
          var ifblock;
          fnBlock.add("//" + overload.org);
          ifblock = new CodeBlock.CodeBlock("if (" + (this.typeif(overload.args)) + ")");
          this.createCall(ifblock, overload);
          fnBlock.add(ifblock);
          return this.logger.stats.converted++;
        }, this));
        fnBlock.add("return v8::ThrowException(v8::Exception::Error(v8::String::New((\"Could not determine overload from supplied arguments\"))));");
      }
      fnBlock.add(snippets.impl.methodEnd());
      return fnBlock;
    };
    ClassConverter.prototype.createDestructor = function() {
      var fnBlock;
      fnBlock = new CodeBlock.FunctionBlock(snippets.impl.destructor(this.className, "__destructor"));
      fnBlock.add("DESTRUCTOR_BEGIN();");
      fnBlock.add(("" + this.classType + "* _this = ") + snippets.FromJS(this.classType + '*', "value", 0));
      _.each(this.destructorNode.children, __bind(function(line) {
        return fnBlock.add(new CodeBlock.Code(line.text));
      }, this));
      fnBlock.add("DESTRUCTOR_END();");
      this.logger.stats.converted++;
      return fnBlock;
    };
    return ClassConverter;
  })();
  exports.ClassConverter = ClassConverter;
}).call(this);
