_ = require 'underscore'
beautils = require('./beautils').u
CodeBlock = require('./codeblock').CodeBlock
snippets = require('./snippets')

fixt = snippets.fixt

class TypeManager 
	constructor: (@logger, @namespaces) ->
		@types = []
		
	#add a 'wrapped' or exposed class to the list
	addWrapped: (node, namespace) ->
		[type] = beautils.parseClassDirective node
		t = new beautils.Type type, namespace
		t.wrapped = true
		t.manual = false
		@types.push t
		
	#Check if a type is 'Wrapped', eg. is an exposed class
	isWrapped: (type) ->
		wrapped = _.filter @types, (t) -> t.wrapped
		_.any wrapped, (wt) -> wt.rawType == type.rawType && wt.namespace == type.namespace
		
		
	#Check if a type is native or is in the list of declared types
	knownType: (type) -> 
		type.isNative() || _.any @types, (wt) -> wt.rawType == type.rawType && wt.namespace == type.namespace
		
	#Attempts to see if the value looks like a known (user-defined) type constructor
	typeFromValue: (value) ->
		thatType = false
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
			members = _.map typeNode.children, (line) -> new beautils.Argument line.text, namespace
		else
			members = _.map typeNode.children, (line) -> line.text
		return members
		
	#Create the Is<T> function
	#type Convert<type>::Is(v8::Handle<v8::Value> v)
	fnIs: (type) ->	
		
		fnBlock = new CodeBlock.CodeBlock
		
		#Wrapped type -> forward to ExposedClass<T>::Is()
		if type.wrapped
			fnBlock.add "return bea::ExposedClass<#{fixt type.fullType()}>::Is(v);"
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
			fnBlock.add "return bea::ExposedClass<#{fixt type.fullType()}>::FromJS(v, nArg);"
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
		fnBlock = new CodeBlock.CodeBlock
		
		if type.wrapped
			fnBlock.add "return bea::ExposedClass<#{fixt type.fullType()}>::ToJS(v);"
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