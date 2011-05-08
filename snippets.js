(function() {
  var CodeBlock;
  CodeBlock = require('./codeblock').CodeBlock;
  exports.FromJS = function(type, arg, i, sc) {
    if (sc == null) {
      sc = ';';
    }
    return ("bea::Convert<" + type + ">::FromJS(" + arg + ", " + i + ")") + sc;
  };
  exports.Is = function(type, arg, sc) {
    if (sc == null) {
      sc = ';';
    }
    return ("bea::Convert<" + type + ">::Is(" + arg + ")") + sc;
  };
  exports.Optional = function(type, nArg, def, sc) {
    if (sc == null) {
      sc = ';';
    }
    return ("bea::Optional<" + type + ">::FromJS(args, " + nArg + ", " + def + ")") + sc;
  };
  exports.OptionalIs = function(type, nArg, sc) {
    if (sc == null) {
      sc = ';';
    }
    return ("bea::Optional<" + type + ">::Is(args, " + nArg + ")") + sc;
  };
  exports.ToJS = function(type, value, sc) {
    if (sc == null) {
      sc = ';';
    }
    return ("bea::Convert<" + type + ">::ToJS(" + value + ")") + sc;
  };
  exports.decl = {};
  exports.decl.method = function(name) {
    return "static v8::Handle<v8::Value> " + name + "(const v8::Arguments& args);";
  };
  exports.decl.accessorGet = function(name) {
    return "static v8::Handle<v8::Value> accGet_" + name + "(v8::Local<v8::String> prop, const v8::AccessorInfo& info);";
  };
  exports.decl.accessorSet = function(name) {
    return "static void accSet_" + name + "(v8::Local<v8::String> prop, v8::Local<v8::Value> v, const v8::AccessorInfo& info);";
  };
  exports.decl.destructor = function() {
    return "static void __destructor(v8::Handle<v8::Value> value);";
  };
  exports.decl.InitJSObject = function(className) {
    return "void " + className + "::_InitJSObject(v8::Handle<v8::Object> target)";
  };
  exports.impl = {};
  exports.impl.methodBegin = function(nArgs) {
    return "METHOD_BEGIN(" + nArgs + ");";
  };
  exports.impl.methodEnd = function() {
    return "METHOD_END();";
  };
  exports.impl.method = function(className, name) {
    return "v8::Handle<v8::Value> " + className + "::" + name + "(const v8::Arguments& args)";
  };
  exports.impl.destructor = function(className, name) {
    return "void " + className + "::" + name + "(v8::Handle<v8::Value> value)";
  };
  exports.impl.accessorGet = function(className, name) {
    return "v8::Handle<v8::Value> " + className + "::accGet_" + name + "( v8::Local<v8::String> prop, const v8::AccessorInfo& info)";
  };
  exports.impl.accessorSet = function(className, name) {
    return "void " + className + "::accSet_" + name + "(v8::Local<v8::String> prop, v8::Local<v8::Value> v, const v8::AccessorInfo& info)";
  };
  exports.impl.accessorGetImpl = function(thisType, accessorType, impl) {
    var retVal;
    retVal = '; //TODO: store return value here';
    if (impl.length) {
      retVal = " = bea::Convert<" + accessorType + ">::ToJS(" + impl + ");";
    }
    return "v8::HandleScope scope; \n" + thisType + " _this = bea::Convert<" + thisType + ">::FromJS(info.Holder(), 0); \nv8::Handle<v8::Value> retVal" + retVal + "\nreturn scope.Close(retVal);";
  };
  exports.impl.accessorSetImpl = function(thisType, accessorType, impl) {
    if (impl.length === 0) {
      impl = '//TODO: Set value here';
    }
    return "v8::HandleScope scope;\n" + thisType + " _this = bea::Convert<" + thisType + ">::FromJS(info.Holder(), 0); \n" + accessorType + " value = bea::Convert<" + accessorType + ">::FromJS(v, 0);\n" + impl;
  };
  exports.impl.exposeClass = function(classType, exposedName) {
    return "bea::Wrapped<" + classType + ">* obj = EXPOSE_CLASS(" + classType + ", \"" + exposedName + "\");";
  };
  exports.impl.exposeObject = function(className, exposedName) {
    return "bea::ExposedObject<" + className + ">* obj = bea::ExposedObject<" + className + ">::Create(new " + className + ", \"" + exposedName + "\");";
  };
  exports.fnConv = {};
  exports.ConvertStruct = function(type) {
    var struct;
    struct = new CodeBlock.ClassBlock("template<> struct Convert<" + type + ">");
    struct.Is = struct.add(new CodeBlock.FunctionBlock("static bool Is(v8::Handle<v8::Value> v)"));
    struct.FromJS = struct.add(new CodeBlock.FunctionBlock("static " + type + " FromJS(v8::Handle<v8::Value> v, int nArg)"));
    struct.ToJS = struct.add(new CodeBlock.FunctionBlock("static v8::Handle<v8::Value> ToJS(" + type + " const& v)"));
    return struct;
  };
}).call(this);
