_ = require('./lib/underscore')

trim = (str) ->
	str.replace(/^\s+|\s+$/g, '');

tabify = (str, ntabs) ->
	i = 0
	tabs = ''
	while i++ < ntabs 
		tabs+='\t'
	_.map(str.split('\n'), (line) -> tabs + line).join('\n');
	
	

#returns:
#name - argument name
#type - argument type, including namespace and 'const'
#value - default value or undefined
parseArg = (arg) ->
## char*, const char*, const char *, const char* value, const char * value = NULL
	ret = {}
	arg = trim arg 

## split on = to get default value, eg. int k = 0
	vals = arg.split '=' 
	if vals.length > 1 then	ret.value = vals[1]
	arg = vals[0]
	
## at this point, args is a variation of 'const type * name' or 'const type &'
# can be std::vector<int*> *
	arg = arg.replace(/\*/g, ' * ')
			.replace(/\&/g, ' & ')
			.replace(/\s+\*/g, '* ')
			.replace(/\s+\&/g, '& ')
			
## remove any double spaces inside string
	arg = arg.replace /\s{2,99}/g, ' '
	arg = trim arg
	
	arg = arg.split ' '
			
## just the type, no argument name
	if arg.length == 1
	
		ret.type = arg[0]
		ret.name = ''
		return ret
## const char*, const Mat, const MyClass
	
	if arg.length == 2
		if arg[0] == 'const' || arg[1] == 'const' || arg[0] == 'const*' || arg[1] == 'const*'
			ret.type = arg[0] + ' ' + arg[1]
			return ret
		else
			[ret.type, ret.name] = arg
			return ret
			
	ret.name = arg[arg.length - 1]
	ret.type = arg.slice(0, arg.length - 1).join(' ');
	return ret
	

#very optimistic detection of native C++ type :)	
isNativeType = (type) ->
	nativeTypes = ['void', 'int', 'long', 'bool', 'char', 'double', 'short', 'float', 'size_t']
	type = type.replace /^\s*unsigned\s+|\s*signed\s+/, ''
	_.any nativeTypes, (nt) -> nt == type
	
class Type
	constructor: (@org, @namespace) ->
		type = @org.replace /^\s*const\s+|\s*volatile\s+/, ''
		#extract namespace
		ln = type.indexOf '::'
		if ln != -1
			@namespace = type.substring 0, ln
			type = type.substring ln + 2
		
		#nsType = type without namespace, but with pointer/ref
		@type = type
		@rawType = type.replace(/^\s+|\s+$/g, '').replace(/\s*\&$/, '').replace(/\s*\*$/, '') #the type without namespaces and decoration
		@isPointer = type.match(/\*\s*$/)?
		@isRef = type.match(/\&\s*$/)?
		@isConst = false
		if @org.match(/^\s*const\s+/) then @isConst = true
	fullType: ->
		if isNativeType(@rawType) then return @org
		if @namespace then return @namespace + '::' + @rawType
		return @rawType
	isNative: -> isNativeType(@rawType)
#argument
class Argument
	constructor: (@org, @ns) ->
		parsed = parseArg @org
		@name = parsed.name
		@type = new Type parsed.type, @ns
		@value = parsed.value
	

parseDeclaration = (str, namespace) ->


	argsStart = str.indexOf '('
	argsEnd = str.lastIndexOf ')'
	return false if argsStart is -1 or argsEnd is -1

	
	
	args = trim str.slice(argsStart + 1, argsEnd)
	decla = trim(str.slice(0, argsStart))
	
	isPure = /\s*=\s*0/.test str
	
	parseArgs = (args) ->
		if args.length == 0 then return []
		ret = []
		cur = ''
		paran = 0
		symbol = 0; 
		for char in args 
			switch char
				when ',' 
					if paran != 0
						cur+= char
					else
						ret.push cur
						cur = ''
					
				when '(' 
					paran++
					cur+=char
				when ')' 
					paran--
					cur+=char
				else
				   cur+=char
		
		if paran is not 0
			throw 'Mismatched ('
		
		ret.push cur
		
		return ret
		
	args = parseArgs args 
	
	fnArgs = [];
	
	fnArgs.push new Argument(arg, namespace) for arg in args
	
	isVirtual = false
	if /^virtual\s+/.test decla
		decla = decla.replace /^virtual\s+/, ''
		isVirtual = true
	
	fnDec = new Argument decla, namespace
	_.extend fnDec, {args: fnArgs, virtual: isVirtual, pure: isPure}		

isSameOverload = (overload1, overload2) ->
	overload1.name == overload2.name &&
	_.isEqual overload1.args, overload2.args
	
hasOverload = (list, overload) ->
	_.any list, (over) ->
		isSameOverload over, overload	
	
parseClassDirective = (node) ->
	className = node.text.replace /{\s*$/, ''
	className = (className.replace /^\s*@class\s+|^\s*@static\s+/, '').replace(/\'|\"/g, '')

	[className, _derived] = className.split ' : '
	
	if _derived
		derived = _.map _derived.split(','), (derived) ->
			derived.replace(/\s*public\s+/, '').replace /^\s+|\s+$/, ''
	
	tmp = className.split ' '
	className = tmp[0]
	exposedName = (tmp[1] ? className).replace(/\s+/g, '_')
	ret = 
		className: className
		exposedName: exposedName
		parentClass: derived
	return ret
	
exports.u = 
	parseArg: parseArg
	tabify: tabify
	trim: trim
	parseDeclaration: parseDeclaration
	isSameOverload: isSameOverload
	hasOverload: hasOverload
	Type: Type
	Argument: Argument
	isNativeType: isNativeType
	parseClassDirective:parseClassDirective