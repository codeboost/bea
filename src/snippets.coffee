CodeBlock = require('./codeblock').CodeBlock

#fix template type, add a space if type ends in >
fixt = (type) ->
	if />$/.test type then return type + ' ' 
	return type
	
exports.fixt = fixt

exports.FromJS = (type, arg, i, sc = ';') ->
	"bea::Convert<#{fixt type}>::FromJS(#{arg}, #{i})" + sc

exports.Is = (type, arg, sc = ';') ->
	if />$/.test type then type += ' '
	"bea::Convert<#{fixt type}>::Is(#{arg})" + sc

exports.Optional = (type, nArg, def, sc = ';') ->
	if />$/.test type then type += ' '
	"bea::Optional<#{fixt type}>::FromJS(args, #{nArg}, #{def})" + sc
	
exports.OptionalIs = (type, nArg, sc = ';') ->
	if />$/.test type then type += ' '
	"bea::Optional<#{fixt type}>::Is(args, #{nArg})" + sc

exports.ToJS = (type, value, sc = ';') ->
	if />$/.test type then type += ' '
	"bea::Convert<#{fixt type}>::ToJS(#{value})" + sc
	
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
	if impl.length then retVal = " = bea::Convert<#{fixt accessorType}>::ToJS(#{impl});"
	"""v8::HandleScope scope; 
	#{thisType} _this = bea::Convert<#{fixt thisType}>::FromJS(info.Holder(), 0); 
	v8::Handle<v8::Value> retVal#{retVal}
	return scope.Close(retVal);"""

exports.impl.accessorSetImpl = (thisType, accessorType, impl) ->
	if impl.length == 0 then impl = '//TODO: Set value here'
	"""v8::HandleScope scope;
	#{thisType} _this = bea::Convert<#{fixt thisType}>::FromJS(info.Holder(), 0); 
	#{accessorType} _accValue = bea::Convert<#{fixt accessorType}>::FromJS(v, 0);
	#{impl}
	"""
	
exports.impl.exposeClass = (classType, exposedName) ->
	"bea::ExposedClass<#{fixt classType}>* obj = EXPOSE_CLASS(#{classType}, \"#{exposedName}\");"
	
exports.impl.exposeObject = (className, exposedName) ->
	#"bea::ExposedStatic<#{className}>* obj = bea::ExposedStatic<#{className}>::Create(new #{className}, \"#{exposedName}\");"
	"bea::ExposedStatic<#{className}>* obj = EXPOSE_STATIC(#{className}, \"#{exposedName}\");"
	

exports.fnConv = {}

#"template<> bool Is<#{type.fullType()}*>(v8::Handle<v8::Value> v)"
exports.ConvertStruct = (type) ->
	struct = new CodeBlock.ClassBlock "template<> struct Convert<#{fixt type}>"
	struct.Is = 	struct.add new CodeBlock.FunctionBlock "static bool Is(v8::Handle<v8::Value> v)"
	struct.FromJS = struct.add new CodeBlock.FunctionBlock "static #{type} FromJS(v8::Handle<v8::Value> v, int nArg)"
	struct.ToJS = 	struct.add new CodeBlock.FunctionBlock "static v8::Handle<v8::Value> ToJS(#{fixt type} const& v)"
	return struct

exports.FromJSCast = (castName, type, name, v, i) ->
	if castName.indexOf("<>") == -1
		vtype = castName
	else
		castName = castName.replace /<|>/g, ''
		vtype = "#{castName}<#{fixt type}>"
		
	"#{vtype} #{name} = " + exports.FromJS vtype, v, i

exports.FromJSCastOptional = (castName, type, name, v, i, argv) ->	
	if castName.indexOf("<") == -1
		vtype = castName
	else
		vtype = "#{castName}<#{fixt type}>"
	"#{vtype} #{name} = " + exports.Optional vtype, v, i, argv
	
	
	
	