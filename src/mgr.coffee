_ = require 'underscore'
beautils = require('./beautils').u
CodeBlock = require('./codeblock').CodeBlock
snippets = require('./snippets')

fixt = snippets.fixt

class TypeManager 
	constructor: (@logger, @namespaces) ->
		@types = []
	#adds a type which represents an exposed class: I call them 'wrapped' types
	#These types will have different conversions generated (basically, returning from bea::ExposedClass<Type>)
	addClassType: (type) ->
		type.wrapped = true
		type.manual = false
		@dropType(type)
		@types.push type
		
	#parse class node and create a 'wrapped' type from the declaraiton
	addClassNode: (classNode, namespace) ->
		cl = beautils.parseClassDirective classNode
		cltype = new beautils.Type cl.className, namespace
		@addClassType cltype
		
	
	dropType: (type) ->
		@types = _.reject @types, (t) ->
			t.wrapped == type.wrapped && 
			t.rawType == type.rawType &&
			t.namespace == type.namespace
		@types
	
	#Check if a type is 'Wrapped', eg. is an exposed class
	isWrapped: (type) ->
		_.any @types, (wt) -> 
			wt.wrapped && 
			wt.rawType == type.rawType && 
			wt.namespace == type.namespace
		
	#Check if a type is native or is in the list of declared types
	knownType: (type) -> 
		type.isNative() || _.any @types, (wt) -> wt.rawType == type.rawType && wt.namespace == type.namespace

	#Check if a type has been declared, ignoring namespaces
	declaredType: (type) ->
		type.isNative() || _.any @types, (wt) -> wt.rawType == type.rawType

		
	#Attempts to see if the value looks like a known (user-defined) type constructor
	#returns false if it's not a type constructor
	#returns true type if not
	typeFromValue: (value) ->
		thatType = false
		#eg void fn(Mat& arg = Mat()) --> Mat() is a type constructor

		mret = value.match(/(\w+)\s*\(.*\)/)
		if mret?.length > 1
			probableType = mret[1]
			thatType = _.detect @types, (t) -> t.rawType == probableType
		return thatType
	
	#Add and parse a type node
	add: (typeNode, namespace) ->
		
		tmp = typeNode.text.replace /^@type\s+/, ''
		
		#types can be aliased like this:
		#type int32 castfrom int
		#type Scalar castfrom std::vector<float>
		#...
		#type MyType @manual --> only generate conversion declaration when -m switch is present
		#if declared as 'type MyType' (with no members) --> don't generate conversion code at all, user knows the conversions will compile
	
		#@type name @wrapped
		#Means this is a manual type, but must be treated as a wrapped type
		if /@wrapped/.test tmp
			tmp = tmp.replace /@wrapped\s*/, ''
			t = new beautils.Type tmp, namespace
			t.wrapped = true
			t.manual = true
			@types.push t
			return true
	
		alias = ''		
		manual = /\s+@manual/.test tmp
		
		if manual 
			typeName = tmp.match(/(.+)\s+@manual/)[1]
		else
			[typeName, alias] = tmp.split ' castfrom'
			if alias then alias = beautils.trim alias
		
		return false unless typeName.length
		
		type = new beautils.Type typeName, namespace
		type.alias = alias
		type.manual = manual
		type.members = @getMembers typeNode, type, namespace
		
		@types.push type
	
	#Parse type members 
	getMembers: (typeNode, type, namespace) ->
		if type.alias then return []
		members = []
		if not type.manual 
			children = _.select typeNode.children, (n) -> not /^\s*\/\//.test n.text #without the comments
			
			members = _.map children, (line) -> new beautils.Argument line.text.replace(';', '').replace(/\/\/.*$/,''), namespace
		else
			members = _.map typeNode.children, (line) -> line.text
		return members
		
	#Create the Is<T> function
	#type Convert<type>::Is(v8::Handle<v8::Value> v)
	fnIs: (type) ->	
		
		fnBlock = new CodeBlock.CodeBlock
		
		#Wrapped type -> forward to ExposedClass<T>::Is()
		if type.wrapped
			if not type.alias 
				fnBlock.add "return bea::ExposedClass<#{fixt type.fullType()}>::Is(v);"
			else
				fnBlock.add "return " + snippets.Is type.alias + '*', 'v'
			return fnBlock

		#alias, eg. type Double is double -> return Is<alias>(v). Compiler should recursively detect the right type
		if type.alias 
			fnBlock.add "return bea::Convert<#{fixt type.alias}>::Is(v);"
			return fnBlock
		
		#@manual type -> add a comment to enter the code
		if type.manual || type.members.length == 0 
			fnBlock.add "//TODO: Enter Is() code here..."
			fnBlock.add "return false;"
			return fnBlock
		
		#TODO: Handle Array type
		
		#Type has members, it means it's a structure of some type and passed by Object.
		fnBlock.add "return !v.IsEmpty() && v->IsObject();"
		return fnBlock
		
	#Create the FromJS<T> function
	fnFromJS: (type) ->
		
		fnBlock = new CodeBlock.CodeBlock
		if type.wrapped
			if not type.alias
				fnBlock.add "return bea::ExposedClass<#{fixt type.fullType()}>::FromJS(v, nArg);"
			else
				fnBlock.add "return " + snippets.FromJS type.alias + '*', 'v', 'nArg'
			return fnBlock
		
		if type.alias 
			#type Double alias double -> return (Double)FromJS<double>(v, nArg);
			fnBlock.add "return (#{type.fullType()})" + snippets.FromJS(type.alias, 'v', 'nArg')
			return fnBlock

		memstr = _.map(type.members, (member) -> member.name).join(', ')
		
		fnBlock.add "const char* msg = \"Object with the following properties expected: #{memstr}. This will be cast to '#{type.fullType()}'\";"
		fnBlock.add "if (!Is(v)) BEATHROW();"

		fnBlock.add "v8::HandleScope scope;"		
		if type.manual || type.members.length == 0
			fnBlock.add "//Enter FromJS conversion code here..."
			fnBlock.add "#{type.fullType()} ret;"
			fnBlock.add "return ret;"
			return fnBlock;
		
		fnBlock.add "v8::Local<v8::Object> obj = v->ToObject();"
		fnBlock.add "#{type.fullType()} ret;"
		fnBlock.add _.map(type.members, (member) -> "ret.#{member.name} = bea::Convert<#{fixt member.type.fullType()}>::FromJS(obj->Get(v8::String::NewSymbol(\"#{member.name}\")), nArg);").join("\n")
		fnBlock.add "return ret;"
		return fnBlock
	
	#Create to ToJS<T> function
	fnToJS: (type) ->
	
		#return false unless !type.noToJS
		fnBlock = new CodeBlock.CodeBlock
		
		if type.wrapped
			if not type.alias
				fnBlock.add "return bea::ExposedClass<#{fixt type.fullType()}>::ToJS(v);"
			else
				fnBlock.add "return " + snippets.ToJS type.alias + '*', "static_cast<#{fixt type.alias}*>(v)"
			return fnBlock
			
		if type.alias
			fnBlock.add "return " + snippets.ToJS type.alias, "v"
			return fnBlock
		
		fnBlock.add "v8::HandleScope scope;"
		
		if type.manual || type.members.length == 0
			fnBlock.add "v8::Handle<v8::Value> ret;"
			fnBlock.add "//TODO: Write conversion code here"
			fnBlock.add "return scope.Close(ret);"
			return fnBlock
		
		fnBlock.add "v8::Local<v8::Object> obj = v8::Object::New();"
		fnBlock.add _.map(type.members, (member) -> "obj->Set(v8::String::NewSymbol(\"#{member.name}\"), bea::Convert<#{fixt member.type.fullType()}>::ToJS(v.#{member.name}));").join('\n')
		fnBlock.add "return scope.Close(obj);"
		return fnBlock

	#FromJS<T>, Is<T>, ToJS<T>
	createConversions: (manualOnly = false) ->
		block = new CodeBlock.CodeBlock
		_.each @types, (type) ->
			
			return false unless type.wrapped || type.manual || type.alias || type.members.length > 0
			if manualOnly != type.manual
				@logger.stats.typesIgnored++
				return false
		
			typeName = type.fullType()
			if type.wrapped then typeName += '*'
			
			convStruct = block.add snippets.ConvertStruct typeName
			convStruct.Is.add 		@fnIs type
			convStruct.FromJS.add 	@fnFromJS type
			convStruct.ToJS.add 	@fnToJS type
			@logger.stats.typesConverted++
		, this	
		
		return block
		
exports.TypeManager = TypeManager