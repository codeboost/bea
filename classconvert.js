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
      this.virtual = false;
      this.exposed = true;
      this.namespace = '';
      this.nsBlock = null;
      this.accessors = {};
      this.destructorNode = null;
      this.typeManager = this.options.typeManager;
      this.logger = this.options.logger;
      this.virtCount = 0;
      this.environ = this.options.environ;
      this.virtualCount = 0;
    }
    ClassConverter.prototype.warn = function(msg, node) {
      this.logger.warn(msg, node);
      return false;
    };
    ClassConverter.prototype.processClass = function(cl, targetNamespace) {
      var cldef, declaNs, derivedDecla, ret;
      this.namespace = cl.namespace;
      if (/^@static\s+/.test(cl.node.text)) {
        this.isStatic = true;
      } else {
        this.isStatic = false;
      }
      cldef = beautils.parseClassDirective(cl.node);
      this.className = cldef.className;
      this.exposedName = cldef.exposedName;
      this.parentClass = cldef.parentClass;
      if (this.parentClass) {
        _.each(this.parentClass, __bind(function(parentClass) {
          var parentFns, parentType;
          parentType = new beautils.Type(parentClass, this.namespace);
          parentFns = this.environ[parentType.namespace][parentType.rawType];
          if (!parentFns) {
            return this.warn("Unkown base class '" + parentClass + "'", cl.node);
          } else {
            _.extend(this.classFns, parentFns.fns);
            delete this.classFns["__constructor"];
            delete this.classFns["__destructor"];
            return this.virtualCount += parentFns.virtualCount;
          }
        }, this));
      }
      this.nsBlock = new CodeBlock.NamespaceBlock(targetNamespace);
      this.nativeClassName = this.className;
      this.classType = new beautils.Type(this.nativeClassName, this.namespace);
      this.className = 'J' + this.nativeClassName;
      if (!this.isStatic) {
        if (!cl.node.findChild("@postAllocator")) {
          cl.node.addChild("@postAllocator");
        }
      }
      _.each(cl.node.children, __bind(function(child) {
        if (/^public\s*:/.test(child.text)) {
          return _.each(child.children, __bind(function(chld) {
            return this.processFunNode(chld);
          }, this));
        } else if (/^private\s*:|^protected\s*:/.test(child.text)) {
          return this.warn('Private and protected members ignored.', child);
        } else {
          return this.processFunNode(child);
        }
      }, this));
      if (!this.environ[this.namespace]) {
        this.environ[this.namespace] = {};
      }
      this.environ[this.namespace][this.nativeClassName] = {
        fns: this.classFns,
        virtualCount: this.virtualCount
      };
      if (this.virtualCount > 0) {
        this.baseType = this.classType;
        this.nativeClassName = this.options.derivedPrefix + this.nativeClassName;
        this.classType = new beautils.Type(this.nativeClassName, targetNamespace);
      }
      if (!this.isStatic) {
        this.options.typeManager.addWrapped(this.classType, this.baseType);
      }
      this.globalBlock = new CodeBlock.CodeBlock;
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
        if (this.virtualCount > 0) {
          derivedDecla = this.createDerivedClass();
          declaNs.add(derivedDecla.decla);
          this.nsBlock.add(derivedDecla.impl);
        }
      }
      if (!this.options.manual) {
        if (!this.isStatic) {
          this.globalBlock.add("DECLARE_EXPOSED_CLASS(" + (this.classType.fullType()) + ");");
          if (!this.classFns["__constructor"]) {
            this.warn("No constructor defined for " + this.className + "!", cl.node);
          }
        } else {
          this.globalBlock.add("DECLARE_STATIC(" + targetNamespace + "::" + this.className + ");");
        }
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
      var accType, callNode, fn, fspace, isManual, nodeText, str, _accName;
      if (/^\/\//.test(node.text)) {
        return false;
      }
      if (/^@noexpose/.test(node.text)) {
        this.exposed = false;
        return false;
      }
      if (/^@manual\s+/.test(node.text)) {
        isManual = true;
        str = node.text.replace(/^@manual\s+/, '');
      } else {
        str = node.text;
      }
      str = str.replace(/\s*\/\/.*$/g, '');
      if (/^\@accessor\s+/.test(str)) {
        return this.parseAccessor(node);
      }
      if (/^\@postAllocator/.test(str)) {
        if (this.isStatic) {
          return this.warn("Postallocator for static class ignored", node);
        }
        str = "void __postAllocator()";
      }
      if (/^~|^virtual\s+~/.test(str)) {
        return false;
      }
      if (/^\@destructor/.test(str)) {
        if (this.isStatic) {
          return this.warn("Destructor for static class ignored", node);
        }
        this.destructorNode = node;
        return true;
      }
      str = str.replace(/;\s*$/, '');
      if (str.indexOf("(") === -1 && /\s+/.test(str)) {
        str = str.replace(/\s+/g, ' ');
        fspace = str.indexOf(' ');
        accType = str.slice(0, fspace);
        _accName = str.slice(fspace);
        _.each(_accName.split(','), __bind(function(accName) {
          var accessor;
          accName = beautils.trim(accName);
          if (!accName.length) {
            return false;
          }
          accessor = {
            type: new beautils.Type(accType, this.namespace),
            name: accName,
            read: "_this->" + accName,
            write: "_this->" + accName + " = _accValue;"
          };
          return this.addAccessor(accessor, node);
        }, this));
        return true;
      }
      if (/\s+operator\s*[=\+\/\\\*<>\^\-]*/.test(str)) {
        return this.warn('Operator overloading not supported. Declaration ignored', node);
      }
      fn = beautils.parseDeclaration(str, this.namespace);
      if (!fn) {
        return this.warn("Cannot parse method declaration: '" + str + "'. Ignoring.", node);
      }
      if (fn.type.rawType === this.nativeClassName && fn.name === "") {
        fn.orgName = fn.name;
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
      fn.parentClass = this.nativeClassName;
      if (fn.virtual) {
        this.virtualCount++;
      }
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
    ClassConverter.prototype.addAccessor = function(accessor, node) {
      if (this.accessors[accessor.name]) {
        return this.warn("Accessor: '" + accessor.name + "': accessor already defined. Second definition ignored", node);
      }
      return this.accessors[accessor.name] = accessor;
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
      return this.addAccessor(accessor);
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
    ClassConverter.prototype.createDerivedClass = function() {
      var classBlock, constructors, implBlock, public, publicd, publicv, vfuncs;
      classBlock = new CodeBlock.ClassBlock("class " + this.nativeClassName + " : public " + (this.baseType.fullType()) + ", public bea::DerivedClass");
      public = classBlock.add(new CodeBlock.CodeBlock("public:", false));
      constructors = _.detect(this.classFns, function(fn) {
        return fn.name === '__constructor';
      });
      _.each(constructors, __bind(function(constr) {
        var cargs, dargs;
        dargs = _.map(constr.args, function(arg) {
          return arg.org;
        });
        cargs = _.map(constr.args, function(arg) {
          return arg.name;
        });
        return public.add("" + this.nativeClassName + "(" + (dargs.join(', ')) + ") : " + (this.baseType.fullType()) + "(" + (cargs.join(', ')) + "){}");
      }, this));
      vfuncs = [];
      _.each(this.classFns, function(fn) {
        return _.each(fn, function(over) {
          if (over.virtual) {
            return vfuncs.push(over);
          }
        });
      });
      implBlock = new CodeBlock.CodeBlock;
      publicv = public.add(new CodeBlock.CodeBlock("", false));
      publicv.add("//JS: These virtual functions will only be called from Javascript");
      publicd = public.add(new CodeBlock.CodeBlock("", false));
      publicd.add("//Native: These virtual functions will only be called from native code");
      _.each(vfuncs, __bind(function(vfunc) {
        var arglist, cargs, castBack, cif, dargs, fn, funcontents, nativeType, ret, vfuncdecla;
        dargs = _.map(vfunc.args, function(arg) {
          return arg.org;
        });
        cargs = _.map(vfunc.args, function(arg) {
          return arg.name;
        });
        vfunc.callAs = "_d_" + vfunc.name;
        ret = 'return';
        if (vfunc.type.rawType === 'void') {
          ret = '';
        }
        if (vfunc.pure) {
          funcontents = "throw bea::Exception(\"'" + vfunc.name + "' : pure virtual function not defined.\");";
        } else {
          funcontents = "" + ret + " " + (this.baseType.fullType()) + "::" + vfunc.name + "(" + (cargs.join(', ')) + ");";
        }
        publicv.add(new CodeBlock.FunctionBlock("inline " + vfunc.type.org + " _d_" + vfunc.name + "(" + (dargs.join(', ')) + ")")).add(funcontents);
        vfuncdecla = "" + vfunc.type.org + " " + vfunc.name + "(" + (dargs.join(', ')) + ")";
        publicd.add(vfuncdecla + ';');
        fn = implBlock.add(new CodeBlock.FunctionBlock("" + vfunc.type.org + " " + this.nativeClassName + "::" + vfunc.name + "(" + (dargs.join(', ')) + ")"));
        fn.add("v8::HandleScope v8scope; v8::Handle<v8::Value> v8retVal;");
        cif = fn.add(new CodeBlock.CodeBlock("if (bea_derived_hasOverride(\"" + vfunc.name + "\"))"));
        arglist = _.map(vfunc.args, __bind(function(arg) {
          return snippets.ToJS(arg.type.org, arg.name, '');
        }, this));
        if (vfunc.args.length > 0) {
          cif.add("v8::Handle<v8::Value> v8args[" + vfunc.args.length + "] = {" + (arglist.join(', ')) + "};");
        } else {
          cif.add("v8::Handle<v8::Value> v8args[1];");
        }
        cif.add("v8retVal = bea_derived_callJS(\"" + vfunc.name + "\", " + vfunc.args.length + ", v8args);");
        fn.add("if (v8retVal.IsEmpty()) " + ret + " _d_" + vfunc.name + "(" + (cargs.join(', ')) + ");");
        if (vfunc.type.rawType !== 'void') {
          nativeType = this.nativeType(vfunc.type);
          if (nativeType.indexOf('*') !== -1 && !vfunc.type.isPointer) {
            castBack = '*';
          } else {
            castBack = '';
          }
          return fn.add(("return " + castBack) + snippets.FromJS(nativeType, "v8retVal", 0));
        }
      }, this));
      return {
        decla: classBlock,
        impl: implBlock
      };
    };
    ClassConverter.prototype.createInitFn = function() {
      var initFn;
      initFn = new CodeBlock.FunctionBlock(snippets.decl.InitJSObject(this.className));
      if (!this.isStatic) {
        initFn.add(snippets.impl.exposeClass(this.classType.fullType(), this.exposedName));
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
      fn.add(snippets.impl.accessorGetImpl("" + (this.classType.fullType()) + "*", this.nativeType(accessor.type), accessor.read));
      block.add("//Set Accessor " + name + " (" + (this.nativeType(accessor.type)) + ")");
      fn = block.add(new CodeBlock.FunctionBlock(snippets.impl.accessorSet(this.className, name)));
      fn.add(snippets.impl.accessorSetImpl("" + (this.classType.fullType()) + "*", this.nativeType(accessor.type), accessor.write));
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
      var argList, fnName, fnRet, fncall, names, nativeType, retVal, tmp, _ref, _ref2;
      if (overload.manual) {
        block.add('//TODO: Enter code here');
        block.add('return args.This();');
        return block;
      }
      this.convertArguments(block, overload.args);
      if (!this.isStatic && overload.name !== "__constructor") {
        block.add(("" + (this.classType.fullType()) + "* _this = ") + snippets.FromJS(this.classType.fullType() + '*', "args.This()", 0));
      }
      if (overload.name === '__postAllocator' && this.virtualCount > 0) {
        block.add('_this->bea_derived_setInstance(args.This());');
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
      fnName = (_ref = overload.callAs) != null ? _ref : overload.name;
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
        if ((_ref2 = overload.callText) != null ? _ref2.length : void 0) {
          fncall = new CodeBlock.CodeBlock(overload.callText, false);
        } else {
          if (!this.typeManager.isWrapped(overload.type)) {
            fncall = new FnCall(fnRet, fnName, argList);
          } else {
            if (overload.name === '__constructor') {
              fncall = new FnCall(fnRet, 'new ' + this.classType.fullType(), argList);
              retVal = "return v8::External::New(fnRetVal);";
            } else {
              if (!overload.type.isPointer) {
                tmp = new FnCall('', fnName, argList);
                fncall = new FnCall(fnRet, 'new ' + overload.type.fullType(), tmp.render(''));
              } else {
                fncall = new FnCall(fnRet, fnName, argList);
              }
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
      fnBlock.add(("" + (this.classType.fullType()) + "* _this = ") + snippets.FromJS(this.classType.fullType() + '*', "value", 0));
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
