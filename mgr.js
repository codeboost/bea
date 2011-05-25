(function() {
  var CodeBlock, TypeManager, beautils, fixt, snippets, _;
  _ = require('underscore');
  beautils = require('./beautils').u;
  CodeBlock = require('./codeblock').CodeBlock;
  snippets = require('./snippets');
  fixt = snippets.fixt;
  TypeManager = (function() {
    function TypeManager(logger, namespaces) {
      this.logger = logger;
      this.namespaces = namespaces;
      this.types = [];
    }
    TypeManager.prototype.addClassType = function(type) {
      type.wrapped = true;
      type.manual = false;
      this.dropType(type);
      return this.types.push(type);
    };
    TypeManager.prototype.addClassNode = function(classNode, namespace) {
      var cl, cltype;
      cl = beautils.parseClassDirective(classNode);
      cltype = new beautils.Type(cl.className, namespace);
      return this.addClassType(cltype);
    };
    TypeManager.prototype.dropType = function(type) {
      this.types = _.reject(this.types, function(t) {
        return t.wrapped === type.wrapped && t.rawType === type.rawType && t.namespace === type.namespace;
      });
      return this.types;
    };
    TypeManager.prototype.isWrapped = function(type) {
      return _.any(this.types, function(wt) {
        return wt.wrapped && wt.rawType === type.rawType && wt.namespace === type.namespace;
      });
    };
    TypeManager.prototype.knownType = function(type) {
      return type.isNative() || _.any(this.types, function(wt) {
        return wt.rawType === type.rawType && wt.namespace === type.namespace;
      });
    };
    TypeManager.prototype.typeFromValue = function(value) {
      var mret, probableType, thatType;
      thatType = false;
      mret = value.match(/(\w+)\s*\(.*\)/);
      if ((mret != null ? mret.length : void 0) > 1) {
        probableType = mret[1];
        thatType = _.detect(this.types, function(t) {
          return t.rawType === probableType;
        });
      }
      return thatType;
    };
    TypeManager.prototype.add = function(typeNode, namespace) {
      var alias, manual, t, tmp, type, typeName, _ref;
      tmp = typeNode.text.replace(/^@type\s+/, '');
      if (/@wrapped/.test(tmp)) {
        tmp = tmp.replace(/@wrapped\s*/, '');
        t = new beautils.Type(tmp, namespace);
        t.wrapped = true;
        t.manual = true;
        this.types.push(t);
        return true;
      }
      alias = '';
      manual = /\s+@manual/.test(tmp);
      if (manual) {
        typeName = tmp.match(/(.+)\s+@manual/)[1];
      } else {
        _ref = tmp.split(' castfrom'), typeName = _ref[0], alias = _ref[1];
        if (alias) {
          alias = beautils.trim(alias);
        }
      }
      if (!typeName.length) {
        return false;
      }
      type = new beautils.Type(typeName, namespace);
      type.alias = alias;
      type.manual = manual;
      type.members = this.getMembers(typeNode, type, namespace);
      return this.types.push(type);
    };
    TypeManager.prototype.getMembers = function(typeNode, type, namespace) {
      var children, members;
      if (type.alias) {
        return [];
      }
      members = [];
      if (!type.manual) {
        children = _.select(typeNode.children, function(n) {
          return !/^\s*\/\//.test(n.text);
        });
        members = _.map(children, function(line) {
          return new beautils.Argument(line.text.replace(';', '').replace(/\/\/.*$/, ''), namespace);
        });
      } else {
        members = _.map(typeNode.children, function(line) {
          return line.text;
        });
      }
      return members;
    };
    TypeManager.prototype.fnIs = function(type) {
      var fnBlock;
      fnBlock = new CodeBlock.CodeBlock;
      if (type.wrapped) {
        if (!type.alias) {
          fnBlock.add("return bea::ExposedClass<" + (fixt(type.fullType())) + ">::Is(v);");
        } else {
          fnBlock.add("return " + snippets.Is(type.alias + '*', 'v'));
        }
        return fnBlock;
      }
      if (type.alias) {
        fnBlock.add("return bea::Convert<" + (fixt(type.alias)) + ">::Is(v);");
        return fnBlock;
      }
      if (type.manual || type.members.length === 0) {
        fnBlock.add("//TODO: Enter Is() code here...");
        fnBlock.add("return false;");
        return fnBlock;
      }
      fnBlock.add("return !v.IsEmpty() && v->IsObject();");
      return fnBlock;
    };
    TypeManager.prototype.fnFromJS = function(type) {
      var fnBlock, memstr;
      fnBlock = new CodeBlock.CodeBlock;
      if (type.wrapped) {
        if (!type.alias) {
          fnBlock.add("return bea::ExposedClass<" + (fixt(type.fullType())) + ">::FromJS(v, nArg);");
        } else {
          fnBlock.add("return " + snippets.FromJS(type.alias + '*', 'v', 'nArg'));
        }
        return fnBlock;
      }
      if (type.alias) {
        fnBlock.add(("return (" + (type.fullType()) + ")") + snippets.FromJS(type.alias, 'v', 'nArg'));
        return fnBlock;
      }
      memstr = _.map(type.members, function(member) {
        return member.name;
      }).join(', ');
      fnBlock.add("const char* msg = \"Object with the following properties expected: " + memstr + ". This will be cast to '" + (type.fullType()) + "'\";");
      fnBlock.add("if (!Is(v)) BEATHROW();");
      fnBlock.add("v8::HandleScope scope;");
      if (type.manual || type.members.length === 0) {
        fnBlock.add("//Enter FromJS conversion code here...");
        fnBlock.add("" + (type.fullType()) + " ret;");
        fnBlock.add("return ret;");
        return fnBlock;
      }
      fnBlock.add("v8::Local<v8::Object> obj = v->ToObject();");
      fnBlock.add("" + (type.fullType()) + " ret;");
      fnBlock.add(_.map(type.members, function(member) {
        return "ret." + member.name + " = bea::Convert<" + (fixt(member.type.fullType())) + ">::FromJS(obj->Get(v8::String::NewSymbol(\"" + member.name + "\")), nArg);";
      }).join("\n"));
      fnBlock.add("return ret;");
      return fnBlock;
    };
    TypeManager.prototype.fnToJS = function(type) {
      var fnBlock;
      fnBlock = new CodeBlock.CodeBlock;
      if (type.wrapped) {
        if (!type.alias) {
          fnBlock.add("return bea::ExposedClass<" + (fixt(type.fullType())) + ">::ToJS(v);");
        } else {
          fnBlock.add("return " + snippets.ToJS(type.alias + '*', "static_cast<" + (fixt(type.alias)) + "*>(v)"));
        }
        return fnBlock;
      }
      if (type.alias) {
        fnBlock.add("return " + snippets.ToJS(type.alias, "v"));
        return fnBlock;
      }
      fnBlock.add("v8::HandleScope scope;");
      if (type.manual || type.members.length === 0) {
        fnBlock.add("v8::Handle<v8::Value> ret;");
        fnBlock.add("//TODO: Write conversion code here");
        fnBlock.add("return scope.Close(ret);");
        return fnBlock;
      }
      fnBlock.add("v8::Local<v8::Object> obj = v8::Object::New();");
      fnBlock.add(_.map(type.members, function(member) {
        return "obj->Set(v8::String::NewSymbol(\"" + member.name + "\"), bea::Convert<" + (fixt(member.type.fullType())) + ">::ToJS(v." + member.name + "));";
      }).join('\n'));
      fnBlock.add("return scope.Close(obj);");
      return fnBlock;
    };
    TypeManager.prototype.createConversions = function(manualOnly) {
      var block;
      if (manualOnly == null) {
        manualOnly = false;
      }
      block = new CodeBlock.CodeBlock;
      _.each(this.types, function(type) {
        var convStruct, typeName;
        if (!(type.wrapped || type.manual || type.alias || type.members.length > 0)) {
          return false;
        }
        if (manualOnly !== type.manual) {
          this.logger.stats.typesIgnored++;
          return false;
        }
        typeName = type.fullType();
        if (type.wrapped) {
          typeName += '*';
        }
        convStruct = block.add(snippets.ConvertStruct(typeName));
        convStruct.Is.add(this.fnIs(type));
        convStruct.FromJS.add(this.fnFromJS(type));
        convStruct.ToJS.add(this.fnToJS(type));
        return this.logger.stats.typesConverted++;
      }, this);
      return block;
    };
    return TypeManager;
  })();
  exports.TypeManager = TypeManager;
}).call(this);
