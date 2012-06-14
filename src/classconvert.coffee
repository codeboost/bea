_ = require 'underscore'
beautils = require('./beautils').u
CodeBlock = require('./codeblock').CodeBlock
snippets = require './snippets'

###
TODO:
	- Warn if class does not define a constructor/insert default constructor

###

#Helper class to render a function call
class FnCall
	constructor: (@retVal, @name, @argList)->
	render: (term = ';')->
		cl = @name + '(' + @argList + ')' + term
		if @retVal.length then return @retVal + ' = ' + cl
		return cl

class ClassConverter
	constructor: (@options)->
		@classFns = {}
			
		@className = ""
		@nativeClassName = ""
		@virtual = false	#has virtual functions
		@exposed = true	
		@namespace = ''
		@nsBlock = null
		@accessors = {}
		@destructorNode = null
		@typeManager = @options.typeManager
		@logger = @options.logger
		@virtCount = 0
		@environ = @options.environ;
		@virtualCount = 0
		
	warn: (msg, node) ->
		@logger.warn msg, node
		return false

	#Process a class and create all conversions. This is the only 'public' function of this class
	processClass: (cl, targetNamespace) ->
	
		@namespace = cl.namespace
		if /^@static\s+/.test cl.node.text then @isStatic = true else @isStatic = false
		
		cldef = beautils.parseClassDirective cl.node
		
		@className = cldef.className
		@exposedName = cldef.exposedName
		@parentClass = cldef.parentClass


		#inherit from parent
		if @parentClass
			_.each @parentClass, (parentClass) =>
				parentType = new beautils.Type parentClass, @namespace
				parentFns = @environ[parentType.namespace][parentType.rawType]
				if !parentFns
					@warn "Unkown base class '#{parentClass}'", cl.node
				else
					#inherit all non-virtual members from parent 
					#virtual functions: if defined
					_.extend @classFns, parentFns.fns
					delete @classFns["__constructor"]
					delete @classFns["__destructor"]
					@virtualCount += parentFns.virtualCount

		@nsBlock = new CodeBlock.NamespaceBlock targetNamespace
		
		@nativeClassName = @className
		@classType = new beautils.Type @nativeClassName, @namespace
		@className = 'J' + @nativeClassName
		
		
		
		#make sure there is a postAllocator defined for 
		if !@isStatic 
			if !cl.node.findChild "@postAllocator" then cl.node.addChild "@postAllocator"

		
		#parse all functions
		_.each cl.node.children, (child) =>	
			if /^public\s*:/.test child.text
				_.each child.children, (chld) => @processFunNode chld
			else if /^private\s*:|^protected\s*:/.test child.text 
				@warn 'Private and protected members ignored.', child
			else	
				@processFunNode child
				
		#save raw processed class in the global 'environ' thing
		#we may revisit this class if another class derives from it
		if !@environ[@namespace]  
			@environ[@namespace] = {}

		@environ[@namespace][@nativeClassName] = 
			fns: @classFns
			virtualCount: @virtualCount		
		
		#if virtual functions are defined, create a derived class which acts
		#as the native class
		if @virtualCount > 0
			@baseType = @classType
			@nativeClassName = @options.derivedPrefix + @nativeClassName
			@classType = new beautils.Type @nativeClassName, targetNamespace
			
		if not @isStatic
			@options.typeManager.addClassType @classType
			if @baseType
				@baseType.alias = @classType.fullType()	#means return from this type
				@options.typeManager.addClassType @baseType
			
			
		@globalBlock = new CodeBlock.CodeBlock
		
		#produce destructor
		if !@options.manual && @destructorNode
			@nsBlock.add @createDestructor()
		
		#produce the method conversions
		_.each @classFns, (fn, name) =>	
			ret = @createConversion name, fn.type, fn
			if ret then @nsBlock.add ret
		
		if !@options.manual
			#produce accessor functions
			_.each @accessors, (accessor, name) => @nsBlock.add @createAccessor accessor, name

		if !@options.manual
			@nsBlock.add @createInitFn()
			
			
		if !@options.manual #only cpp must be generated for manual
			declaNs = new CodeBlock.NamespaceBlock targetNamespace
			declaNs.add @createDeclaration()
			
			#has virtual functions?
			if @virtualCount > 0 
				#generate derived class block
				#change className to bea_className
				#function call will be _this->bea_functionName(arguments)
				derivedDecla = @createDerivedClass();
				declaNs.add derivedDecla.decla
				@nsBlock.add derivedDecla.impl
				
					
					
		if not @options.manual
			if not @isStatic
				@globalBlock.add "DECLARE_EXPOSED_CLASS(#{@classType.fullType()});"
				
				if !@classFns["__constructor"] 
					@warn "No constructor defined for #{@className}!", cl.node
					
			else
				@globalBlock.add "DECLARE_STATIC(#{targetNamespace}::#{@className});"
					
		
		ret = 
			global: @globalBlock
			impl: @nsBlock		#implementation block
			decla: declaNs		#declaration block
			tests: @testBlock	#javascript tests
			eClassName: @className
			tClassName: @nativeClassName
			
		return ret
		
	#Parse a function declaration and it's arguments and store the result in the @classFns hash
	processFunNode: (node) ->

		#ignore C++ comments
		return false if /^\/\//.test node.text 
	
		#noexpose directive - means don't expose class to Javascript
		if /^@noexpose/.test node.text
			@exposed = false
			return false
		
		if /^@manual\s+/.test node.text
			isManual = true
			str = node.text.replace /^@manual\s+/, ''
		else 
			str = node.text
			
			
		#remove end comments			
		str = str.replace /\s*\/\/.*$/g, '' 
		
		return @parseAccessor node if /^\@accessor\s+/.test str 
		
		if /^\@postAllocator/.test str
			if @isStatic then return @warn "Postallocator for static class ignored", node
			str = "void __postAllocator()"
			
		#destructor is something which starts with ~ or virtual ~
		
		return false if /^~|^virtual\s+~/.test str 			#str = '@destructor'
			
		if /^\@destructor/.test str 
			if @isStatic then return @warn "Destructor for static class ignored", node
			@destructorNode = node
			return true
		
		str = str.replace /;\s*$/, ''
			
		#If string doesn't look like a function call, but has a space, 
		#we assume that it is in the form Type name and we generate a r/w accessor for it
		if str.indexOf("(") == -1 && /\s+/.test str 
			return @parseAsAccessor str, node
			
		if /\s+operator\s*[=\+\/\\\*<>\^\-]*/.test str
			return @warn 'Operator overloading not supported. Declaration ignored', node

			
		fn = beautils.parseDeclaration str, @namespace
		#returns {
		#	name: function name
		#	type: return type
		#	args: array of arguments
		#}
		
		if not fn then return @warn "Cannot parse method declaration: '#{str}'. Ignoring.", node
		
		if fn.type.rawType == @nativeClassName && fn.name == ""
			fn.orgName = fn.name
			fn.name = '__constructor'
			
	
		if isManual then @logger.stats.manual++
	
		fn.org = str
		fn.manual = isManual
		fn.requiredArgs = @requiredArgs fn.args
		fn.sublines = node.children
		fn.node = node
		fn.parentClass = @nativeClassName
		
		if fn.virtual 
			@virtualCount++
		
		#check sublines for @call directive
		callNode = _.detect fn.sublines, (subline) -> /^\@call/.test subline.text
		
		if callNode 
			nodeText = callNode.text.replace(/^\@call\s*/,"");
			fn.callText = _.compact([nodeText, callNode.toString()]).join '\n'
			fn.sublines = _.without fn.sublines, callNode
		
		
		
		if @classFns[fn.name]
			existing = beautils.findOverload @classFns[fn.name], fn
			if not existing
				@classFns[fn.name].push fn
			else
				existing.pure = fn.pure
		else
			@classFns[fn.name] = [fn]
			@classFns[fn.name].name = fn.name
			@classFns[fn.name].type = fn.type
			
		return true
	
	#parse a string as accessor declaration
	#eg. int value1, value2, etc..
	parseAsAccessor: (str, node) ->
		str = str.replace /\s+/g, ' '
		#split by , --> we can have multiple variables declared as
		#type var1, var2, var3
		tmp = str.split ','
		#first element is the argument type/name
		ar1 = beautils.parseArg tmp[0]
		accType = ar1.type
		#the rest of the array are other variables
		_accName = tmp.slice 1
		_accName.push ar1.name
		_.each _accName, (accName) =>
			accName = beautils.trim(accName)
			return false unless accName.length
			
			type = new beautils.Type accType, @namespace
			read = "_this->#{accName}"
			write =  "_this->#{accName} = _accValue;"
			
			#cast to/back from pointer if type is wrapped
			if @typeManager.isWrapped(type) 
				read = "&" + read
				write =  "_this->#{accName} = *_accValue;"
			
			accessor = 
				type: type
				name: accName
				read: read
				write: write
				
			@addAccessor accessor, node
		return true
	
	#add accessors to the list of accessors
	addAccessor: (accessor, node) ->
		if @accessors[accessor.name] then return @warn "Accessor: '#{accessor.name}': accessor already defined. Second definition ignored", node
		@accessors[accessor.name] = accessor
		
	#Parse an accessor node, add to @accessors
	parseAccessor: (node) ->
		parts = node.text.match /^\@accessor\s+(\w+)\s+(\w+)/
		return @warn("Invalid accessor definition. Ignored.", node) unless parts && parts.length > 1
		
		accessor = 
			name: parts[1]
			type: parts[2]
			
		if not accessor.type then accessor.type = 'int'; @warn "Accessor '#{accessor.name}' : type not defined, int assumed", node
		
		read = node.childType "@get"
		write = node.childType "@set"
		
		if not read then @warn "Accessor '#{accessor.name}': get not defined", node
		if not write then @warn "Accessor '#{accessor.name}': set not defined", node
		
		accessor.type = new beautils.Type accessor.type, @namespace
		accessor.read = (read?.text.replace(/^@get\s*/, '')) ? ""
		accessor.write = (write?.text.replace(/^@set\s*/, '')) ? ""
		accessor.node = node
		@addAccessor accessor
		
	#Create the class declaration. Include methods, accessors, and destructor. Included in the header file
	createDeclaration: ->
		
		return false unless !@options.manual
		
		decBlock = new CodeBlock.ClassBlock "class " + @className
		block = decBlock.add(new CodeBlock.CodeBlock "protected:", false).add new CodeBlock.CodeBlock
		
		if @destructorNode 
			block.add "//Destructor"
			block.add snippets.decl.destructor()
			@logger.stats.declared++
		
		block.add "//Exported methods"
		_.each @classFns, (fn, name) => 
			block.add snippets.decl.method name
			@logger.stats.declared++

		if _.size @accessors 
			
			block.add "//Accessors - Getters"
			_.each @accessors, (acc, name) => 
				block.add snippets.decl.accessorGet name
				@logger.stats.declared++
			
			block.add "//Accessors - Setters"
			_.each @accessors, (acc, name) => 
				block.add snippets.decl.accessorSet name
				@logger.stats.declared++
		
		decBlock.add(new CodeBlock.CodeBlock "public:", false).add "static void _InitJSObject(v8::Handle<v8::Object> target);"
		
		return decBlock
		
	#Creates a 'hidden' derived class from the original class in which
	#the virtual functions are implemented
	#TODO: This function needs cleanup
	createDerivedClass: ->
		
		classBlock = new CodeBlock.ClassBlock "class #{@nativeClassName} : public #{@baseType.fullType()}, public bea::DerivedClass"
		
		publicBlock = classBlock.add (new CodeBlock.CodeBlock "public:", false)
		
		#constructor
		constructors = _.detect @classFns, (fn) -> fn.name == '__constructor'
		
		_.each constructors, (constr) =>
			
			#declaration arguments
			dargs = _.map constr.args, (arg) -> arg.org
			#call arguments
			cargs = _.map constr.args, (arg) -> arg.name
			
			#bea_Derived() : Derived(){}
			#bea_Derived(int k, CClass* ptr): Derived(k, ptr){}
			publicBlock.add "#{@nativeClassName}(#{dargs.join ', '}) : #{@baseType.fullType()}(#{cargs.join(', ')}){}"

		#add virtual functions
		vfuncs = []
		_.each @classFns, (fn) -> _.each fn, (over) -> if over.virtual then vfuncs.push over
		
		
		#native-called virtual functions go into the .cpp file
		#this is because we may return specializations of Convert<> from these functions
		#and this must not happen before the explicit specializations of Convert<> generated by TypeManager.
		
		implBlock = new CodeBlock.CodeBlock
		
		publicv = publicBlock.add new CodeBlock.CodeBlock "", false
		publicv.add "//JS: These virtual functions will only be called from Javascript"
		publicd = publicBlock.add new CodeBlock.CodeBlock "", false
		publicd.add "//Native: These virtual functions will only be called from native code"
		
		_.each vfuncs, (vfunc) =>
			dargs = _.map vfunc.args, (arg) -> arg.org
			cargs = _.map vfunc.args, (arg) -> arg.name
			
			vfunc.callAs = "_d_" + vfunc.name
			
			ret = 'return'
			if vfunc.type.rawType == 'void' then ret = ''
			
			if vfunc.pure
				funcontents = "throw bea::Exception(\"'#{vfunc.name}' : pure virtual function not defined.\");"
			else
				funcontents = "#{ret} #{@baseType.fullType()}::#{vfunc.name}(#{cargs.join ', '});"
			
			publicv.add(new CodeBlock.FunctionBlock "inline #{vfunc.type.org} _d_#{vfunc.name}(#{dargs.join ', '})").add funcontents
			
			
			vfuncdecla = "#{vfunc.type.org} #{vfunc.name}(#{dargs.join ', '})"
			
			publicd.add vfuncdecla + ';'
			
			
			fn = implBlock.add new CodeBlock.FunctionBlock "#{vfunc.type.org} #{@nativeClassName}::#{vfunc.name}(#{dargs.join ', '})"
			fn.add "v8::Locker v8locker;"
			#fn.add "v8::Context::Scope v8ctxScope(bea::Global::context);"
			fn.add "v8::HandleScope v8scope; v8::Handle<v8::Value> v8retVal;"
			cif = fn.add new CodeBlock.CodeBlock "if (bea_derived_hasOverride(\"#{vfunc.name}\"))"
			
			arglist = _.map vfunc.args, (arg) =>
				snippets.ToJS(@nativeType(arg.type), @castArgument(arg), '')
				
			if vfunc.args.length > 0
				cif.add "v8::Handle<v8::Value> v8args[#{vfunc.args.length}] = {#{arglist.join(', ')}};"
			else
				cif.add "v8::Handle<v8::Value> v8args[1];"
				
			cif.add "v8retVal = bea_derived_callJS(\"#{vfunc.name}\", #{vfunc.args.length}, v8args);"
			
			fn.add "if (v8retVal.IsEmpty()) #{ret} _d_#{vfunc.name}(#{cargs.join ', '});"
			
			if vfunc.type.rawType != 'void'
				nativeType = @nativeType(vfunc.type)
				#shit, this is messy, but no time now
				if nativeType.indexOf('*') != -1 && !vfunc.type.isPointer then castBack = '*' else castBack = ''
				fn.add "return #{castBack}" + snippets.FromJS(nativeType, "v8retVal", 0)
			
			
		return {
			decla: classBlock
			impl: implBlock
		}
		
		
	#Create the InitJSObject function, to be added to the CPP file. 
	#This function will be called by the exposing function
	createInitFn: ->
		initFn = new CodeBlock.FunctionBlock snippets.decl.InitJSObject(@className) 
		if not @isStatic
			initFn.add snippets.impl.exposeClass(@classType.fullType(), @exposedName)
		else
			initFn.add snippets.impl.exposeObject(@className, @exposedName)
			
		if @destructorNode 
			initFn.add "//Destructor"
			initFn.add "obj->setDestructor(__destructor);"
		
		initFn.add "//Exposed Methods"
		_.each @classFns, (fn, name) =>
			switch name
				when '__constructor'
					initFn.add "obj->setConstructor(__constructor);"
				when '__postAllocator'
					initFn.add "obj->setPostAllocator(__postAllocator);"
				else
					initFn.add "obj->exposeMethod(\"#{name}\", #{name});"
		
		
		initFn.add "//Accessors"
		_.each @accessors, (accessor, name) =>
			initFn.add "obj->exposeProperty(\"#{name}\", accGet_#{name}, accSet_#{name});"
		
		initFn.add "//Expose object to the Javascript"
		if @exposed 
			initFn.add "obj->exposeTo(target);"
		else
			initFn.add "//Class not exposed to the javascript. Must instantiate and expose it manually"
			initFn.add "//obj->exposeTo(target);"
			
		return initFn
		
	#returns number of required arguments (eg. arguments with no default value)
	requiredArgs: (args) ->
		count = 0 
		_.each args, (arg) ->
			if not arg.value then count++
		count
		

		
	#Create the get and set accessors
	createAccessor: (accessor, name) ->
		block = new CodeBlock.CodeBlock
		
		if @classFns[name] then @warn "Accessor '#{name}': Class '#{@nativeClassName}' already exports method '#{name}'", accessor.node
		
		#Get accessor
		block.add "//Get Accessor #{name} (#{@nativeType accessor.type})"
		fn = block.add new CodeBlock.FunctionBlock(snippets.impl.accessorGet @className, name)
		fn.add (snippets.impl.accessorGetImpl "#{@classType.fullType()}*", @nativeType(accessor.type), accessor.read)
		
		#Set accessor
		block.add "//Set Accessor #{name} (#{@nativeType accessor.type})"
		fn = block.add new CodeBlock.FunctionBlock(snippets.impl.accessorSet @className, name)
		fn.add (snippets.impl.accessorSetImpl "#{@classType.fullType()}*", @nativeType(accessor.type), accessor.write)
		@logger.stats.accessors++
		return block
		
				
	#Return the native type form of a type which can be used for variable declaration
	nativeType: (type) ->
		#Checks if the type is a 'wrapped' type and returns it as a pointer
		#otherwise returns the type properly namespaced, but without pointer/ref
		
		if type.cast
			nativeType = type.cast
		else
			nativeType = type.fullType()
			
		if @typeManager.isWrapped(type) then return nativeType + '*'
		
		nativeType
		
	#returns the proper cast for an argument name
	castVariable: (type, varName) ->
		if @typeManager.isWrapped type
			if !type.isPointer then return '&' + varName
		return varName
		
	castArgument: (arg) ->
			return @castVariable arg.type, arg.name
		
	#Create conversion code for a function argument
	convertArg: (arg, narg) ->
		nativeType = @nativeType arg.type
			
		if not arg.value
			return "#{nativeType} #{arg.name} = " + snippets.FromJS nativeType, "args[#{narg}]", narg
		else
			#value can be:
			#someArg = integer
		
			argv = arg.value
			#type manager attempts to see if the value looks like a known (user-defined) type constructor
			#returns the known type or false
			argType = @typeManager.typeFromValue argv
			if argType 
				if argv.indexOf("::") == -1
					argv = argType.namespace + '::' + argv
				if argType.wrapped and not arg.type.isPointer
					argv = '&' + argv

			return "#{nativeType} #{arg.name} = " + snippets.Optional nativeType, narg, argv
		
	#Generates the if clause for a type check used to determine which overload to call
	typeif: (args) ->
		#if (Is<int>(args[0], 0) && Is<double>(args[1], 1))...
		ifclause = []
		_.each args, (arg, i) =>
			if not arg.value
				ifclause.push snippets.Is @nativeType(arg.type), "args[#{i}]", ''
			else
				ifclause.push snippets.OptionalIs @nativeType(arg.type), i, ''
		
		if ifclause.length == 0 then return 'args.Length() == 0'
		
		ifclause.join ' && '
			
	#Generate the conversion code for all arguments and store the code in the 'block'
	convertArguments: (block, args) ->
		#int arg1 = FromJS<int>(args[0], 0);
		#int arg2 = FromJs<double>(args[1], 1);
		#etc
		_.each args, (arg, i) =>
			block.add @convertArg arg, i
		
	#Generate a function call block, including argument conversion, the native call and return value
	createCall: (block, overload) ->
		
		if overload.manual		
			block.add '//TODO: Enter code here'
			block.add 'return args.This();'
			return block
	
		@convertArguments block, overload.args
		
		isStatic = overload.static | @isStatic

		if !isStatic && overload.name != "__constructor" 
			block.add "#{@classType.fullType()}* _this = " + snippets.FromJS @classType.fullType() + '*', "args.This()", 0

		if overload.name == '__postAllocator' && @virtualCount > 0
			block.add '_this->bea_derived_setInstance(args.This());'
		
		#add the C++ sublines 
		_.each overload.sublines, (line) =>	block.add new CodeBlock.Code line.text
		
		names = [] #argument names, used in the function call;
		_.each overload.args, (arg) =>
			if not @typeManager.knownType arg.type then @warn "Undefined type: '#{arg.type.fullType()}' declared as '#{arg.type.org}'", overload.node
			if @typeManager.isWrapped(arg.type) && !arg.type.isPointer
				names.push '*' + arg.name
			else
				names.push arg.name
				
		fnRet = ''
		retVal = 'return args.This();'
		
		argList = names.join(', ')
		
		if overload.type.type != 'void'
			nativeType = @nativeType(overload.type)
			fnRet = nativeType + ' fnRetVal' 
			retVal = "return " + snippets.ToJS(nativeType, "fnRetVal")
		
		#Determine what function call to generate
		#If we are processing a static class, the converted functions aren't part of a C++ class, so we just have to prepend the current namespace to the function call (eg. cv::add())
		#In case of a class member, we need to convert args.This() to the wrapped type (our class type)
		#and use the form _this->functionName() to call the member function. Crazy stuff.
		fnName = overload.callAs ? overload.name
		if @isStatic 
			fnName = @namespace + '::' + fnName
		else if overload.static
			fnName = @nativeClassName + '::' + fnName
		else
			if overload.name == '__postAllocator'
				fnName = ''
			else
				fnName = '_this->' + fnName

		if fnName.length 
			if overload.callText?.length 
				fncall = new CodeBlock.CodeBlock overload.callText, false
			else
				#Now generate the actual call
				#If the return type is not a wrapped type or void, then we just issue the call
				#If the return type is a wrapped Type, then we need to create a new object of type Type
				if !@typeManager.isWrapped(overload.type)
					fncall = new FnCall fnRet, fnName, argList
				else
					#Mat* fnRet = new Mat(cols, rows)
					#Mat* fnRet = new Mat(*src)
					if overload.name == '__constructor'
						fncall = new FnCall fnRet, 'new ' + @classType.fullType(), argList
						retVal = "return v8::External::New(fnRetVal);"
					else
						#Native function returns a wrapped type. 
						#if it's not a pointer, make one
						if not overload.type.isPointer
							tmp = new FnCall '', fnName, argList
							fncall = new FnCall fnRet, 'new ' + overload.type.fullType(), tmp.render('')
						else
							fncall = new FnCall fnRet, fnName, argList

			#finally, add the block
			block.add fncall.render()	#function call
			
		block.add retVal			#return statement
		return block
		
	allManual: (overloads) ->
		return _.all overloads, (overload) -> overload.manual
		
	anyManual: (overloads) ->
		return _.any overloads, (overload) -> overload.manual
		
	False: (expr) ->
		return false
			
	
	#Creates the conversion code for a native function. 
	#This includes declaring the function, argument conversion and the actual call + return value
	#Overloads are handled here as well
	createConversion: (name, type, overloads) ->
		
		return @False(@logger.stats.failed++) unless _.isArray overloads
		
		return @False(@logger.stats.ignored++) if @options.manual && !@allManual overloads
		
		fnBlock = new CodeBlock.FunctionBlock snippets.impl.method(@className, name)
			
		#compute required arguments
		argc = []
		overloads = _.sortBy overloads, (o) -> 
			argc.push o.requiredArgs
			-o.requiredArgs #sort overloads by number of required arguments
		
		minargs = _.min argc
		
		fnBlock.add snippets.impl.methodBegin(minargs)
		
		if overloads.length == 1
			fnBlock.add "//#{overloads[0].org}"
			if overloads[0].manual && !@options.manual then return @False (@logger.stats.ignored++)
			@createCall fnBlock, overloads[0]
			@logger.stats.converted++
		else
			if @anyManual(overloads) && !@options.manual then return @False(@logger.stats.ignored += overloads.length)
			_.each overloads, (overload) =>
				fnBlock.add "//#{overload.org}"
				ifblock = new CodeBlock.CodeBlock "if (#{@typeif overload.args})"	#if (Is<int>(args[0], 0) && Is<double>....)
				@createCall ifblock, overload	#convert arguments, create native call and return value
				fnBlock.add ifblock
				@logger.stats.converted++
			
			fnBlock.add "return v8::ThrowException(v8::Exception::Error(v8::String::New((\"Could not determine overload from supplied arguments\"))));"
			
		fnBlock.add snippets.impl.methodEnd()
		return fnBlock

	createDestructor: () ->
		#destructor does not need any argument conversions. Just generate the _this conversion and 
		#add the sublines to the function
		fnBlock = new CodeBlock.FunctionBlock snippets.impl.destructor(@className, "__destructor")
		fnBlock.add "DESTRUCTOR_BEGIN();"
		fnBlock.add "#{@classType.fullType()}* _this = " + snippets.FromJS @classType.fullType() + '*', "value", 0
		_.each @destructorNode.children, (line) =>	fnBlock.add new CodeBlock.Code line.text
		fnBlock.add "DESTRUCTOR_END();"
		@logger.stats.converted++
		return fnBlock	
		
#add the class to exports
exports.ClassConverter = ClassConverter






































