CodeBlock = require('./codeblock').CodeBlock

exports.FromJS = (type, arg, i, sc = ';') ->
	"bea::Convert<#{type}>::FromJS(#{arg}, #{i})" + sc

exports.Is = (type, arg, sc = ';') ->
	"bea::Convert<#{type}>::Is(#{arg})" + sc

exports.Optional = (type, nArg, def, sc = ';') ->
	"bea::Optional<#{type}>::FromJS(args, #{nArg}, #{def})" + sc
	
exports.OptionalIs = (type, nArg, sc = ';') ->
	"bea::Optional<#{type}>::Is(args, #{nArg})" + sc

exports.ToJS = (type, value, sc = ';') ->
	"bea::Convert<#{type}>::ToJS(#{value})" + sc
	
#declarations
exports.decl = {}

exports.decl.method = (name) ->
	"static v8::Handle<v8::Value> #{name}(const v8::Arguments& args);"
	
#accessor get
exports.decl.accessorGet = (name) ->
	"static v8::Handle<v8::Value> accGet_#{name}(v8::Local<v8::String> prop, const v8::AccessorInfo& info);"

#accessor set
exports.decl.accessorSet = (name) ->
	"static void accSet_#{name}(v8::Local<v8::String> prop, v8::Local<v8::Value> v, const v8::AccessorInfo& info);"
	
exports.decl.destructor = ->
	"static void __destructor(v8::Handle<v8::Value> value);"
	
exports.decl.InitJSObject = (className) ->
	"void #{className}::_InitJSObject(v8::Handle<v8::Object> target)"
	
	
#implementation 
exports.impl = {}

exports.impl.methodBegin = (nArgs) ->
	"METHOD_BEGIN(#{nArgs});"
	
exports.impl.methodEnd = ->
	"METHOD_END();"
	
exports.impl.method = (className, name) ->
	"v8::Handle<v8::Value> #{className}::#{name}(const v8::Arguments& args)"
	
exports.impl.destructor = (className, name) ->
	"void #{className}::#{name}(v8::Handle<v8::Value> value)"
	
exports.impl.accessorGet = (className, name) ->
	"v8::Handle<v8::Value> #{className}::accGet_#{name}( v8::Local<v8::String> prop, const v8::AccessorInfo& info)"
	
exports.impl.accessorSet = (className, name) ->
	"void #{className}::accSet_#{name}(v8::Local<v8::String> prop, v8::Local<v8::Value> v, const v8::AccessorInfo& info)"
	

exports.impl.accessorGetImpl = (thisType, accessorType, impl) ->
	retVal = '; //TODO: store return value here'
	if impl.length then retVal = " = bea::Convert<#{accessorType}>::ToJS(#{impl});"
	"""v8::HandleScope scope; 
	#{thisType} _this = bea::Convert<#{thisType}>::FromJS(info.Holder(), 0); 
	v8::Handle<v8::Value> retVal#{retVal}
	return scope.Close(retVal);"""

exports.impl.accessorSetImpl = (thisType, accessorType, impl) ->
	if impl.length == 0 then impl = '//TODO: Set value here'
	"""v8::HandleScope scope;
	#{thisType} _this = bea::Convert<#{thisType}>::FromJS(info.Holder(), 0); 
	#{accessorType} value = bea::Convert<#{accessorType}>::FromJS(v, 0);
	#{impl}
	"""
	
exports.impl.exposeClass = (classType, exposedName) ->
	"bea::Wrapped<#{classType}>* obj = EXPOSE_CLASS(#{classType}, \"#{exposedName}\");"
	
exports.impl.exposeObject = (className, exposedName) ->
	"bea::ExposedObject<#{className}>* obj = bea::ExposedObject<#{className}>::Create(new #{className}, \"#{exposedName}\");"
	

exports.fnConv = {}

#"template<> bool Is<#{type.fullType()}*>(v8::Handle<v8::Value> v)"
exports.ConvertStruct = (type) ->
	struct = new CodeBlock.ClassBlock "template<> struct Convert<#{type}>"
	struct.Is = 	struct.add new CodeBlock.FunctionBlock "static bool Is(v8::Handle<v8::Value> v)"
	struct.FromJS = struct.add new CodeBlock.FunctionBlock "static #{type} FromJS(v8::Handle<v8::Value> v, int nArg)"
	struct.ToJS = 	struct.add new CodeBlock.FunctionBlock "static v8::Handle<v8::Value> ToJS(#{type} const& v)"
	return struct
	
	