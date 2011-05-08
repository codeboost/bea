_ = require('./lib/underscore')
BeaParser 		= require('./beaparser').BeaParser
CodeBlock 		= require('./codeblock').CodeBlock
mgr 			= require('./mgr')		
ClassConverter 	= require('./classconvert').ClassConverter
beautils 		= require('./beautils')
fs = require 'fs'
util = require('util')


#Bea parser which handles the 'include' directives in the nodes
#Includes files recursively
class RecursiveParser

	constructor: ->
		@includes = []
	
	parseFile: (fileName) ->
		
		contents = fs.readFileSync(fileName, "ascii")
		if not contents 	
			@error "Cannot read file '#{fileName}'."
			return false

		@includes.push fileName

		parser = new BeaParser fileName
		parser.parse contents
		
		ret = @processIncludes parser.root
		
		return ret
		
		
	warn: (msg, node) ->
		fileName = (node?.fileName) ? ""
		line = (node?.line) ? 0
		if line > 0 then line = "(" + line + ")" else line = ""
		console.log "#{fileName}(#{line}): warning: #{msg}"
		
	include: (node) ->
		fileName = node.text.match(/^@include\s+\"(.+)\"/, "")?[1]	#"#-- my syntax highlighter gets confused by regular expressions with quotes
		if not fileName then return @warn "Invalid include directive", node
		
		fileName = fs.realpathSync fileName
		
		if _.any(@includes, (nf) -> nf == fileName) then return @warn "File #{fileName} already included!", node
		
		return @parseFile fileName
		
	processIncludes: (root) ->
		
		children = root.children
	
		_.each root.children, (node, i) =>
			if node.type() == '@include' 
				ret = @include node
				retc = ret?.children ? []
				children = children.slice(0, i).concat(retc, children.slice(i + 1))
		
		root.children = children
		return root
		
class MessageLogger
	constructor: ->
		@warnings = 0

	warn: (msg, node) ->
		[fileName, line] = [(node?.fileName) ? "", (node?.line) ? 0]
		console.log "#{fileName}(#{line}): warning: #{msg}"
		@warnings++
		
	info: (msg, node) ->
		[fileName, line] = [(node?.fileName) ? "", (node?.line) ? 0]
		if @verbose then console.log "#{fileName}(#{line}) : " + msg
		
	error: (msg, node) ->
		[fileName, line] = [(node?.fileName) ? "", (node?.line) ? 0]
		console.log "#{fileName}(#{line}): warning: #{msg}"
		process.exit -1
	

class BeaLoader extends MessageLogger
	constructor: (@curFileName) ->
		
		@classes = []	#list of defined classes
		@namespaces = {} #namespace definitions
		@typeMgr = new mgr.TypeManager this, @namespaces
		@constants = []
		@verbose = true
		@hFilename = ""
		@cppFilename = ""
		@targetNamespace = ""
		@options = 
			manual: false
			typeManager: @typeMgr
			logger: this
			mtypes: false
		@stats = 
			classes: 0		#number of classes converted
			converted: 0	#number of functions converted
			ignored: 0		#number of functions not converted
			manual: 0		#number of manual functions
			declared: 0		#number of declared functions
			accessors: 0	#number of accessors converted
			failed: 0		#number of failed conversions
			constants: 0 	#number of constants declared
			typesConverted: 0		#number of types converted
			typesIgnored: 0	#number of types not converted
			
	
	setTargetNamespace: (node) ->
		@targetNamespace = node.text.replace(/^@targetNamespace\s+/, '')
		@targetNamespace = @targetNamespace.replace(/\"|\'/g); 
		
	addClass: (classNode, namespace) ->	
		@classes.push 
			namespace: namespace
			node: classNode
		
		if not classNode.text.match /^@static\s+/
			@typeMgr.addWrapped classNode, namespace
			
	addConst: (node) ->
		_.each node.children, (con) =>
			@constants.push con.text
			
	namespace: (nsNode) ->	
		nsname = nsNode.text.replace /^@namespace\s+/, ''
		_.each nsNode.children, (node) =>
			switch node.type()
				when "@class" then @addClass node, nsname
				when "@static" then @addClass node, nsname
				when "@type" then @typeMgr.add node, nsname
				else @warn "Unexpected '#{node.type()}' within namespace #{nsname}", node
		
	setHFileName: (node) ->
		#do not allow filename override
		return @warn("h file name already set.", node) unless @hFilename == ""
		filename = node.text.replace /^@hfilename\s+/, ""
		filename = filename.replace /\"|\'/g, ""
		@hFilename = filename
	
	setCPPFileName: (node) ->
		#do not allow filename override
		return @warn("cpp file name already set.", node) unless @cppFilename == ""
		filename = node.text.replace /^@cppfilename\s+/, ""
		filename = filename.replace /\"|\'/g, ""
		@cppFilename =  filename 
		
		
	addHeader: (hNode) ->
		@header = hNode.toString('\n')

	addCpp: (cppNode) ->
		@cpp = cppNode.toString('\n')
		
	convertConstants: ->
		fn = new CodeBlock.FunctionBlock "void ExposeConstants(v8::Handle<v8::Object> target)"
		_.each @constants, (constant) =>
			fn.add "BEA_DEFINE_CONSTANT(target, #{constant});"
			@stats.constants++
		return fn
	
	#creates the IBeaExposer implementation
	#exposed - list of class names
	#returns: header declarations and cpp implementation
	createBeaExposer: (exposed) ->
		
		return false unless _.isArray(exposed)
		
		#declaration
		declaNS = new CodeBlock.NamespaceBlock @targetNamespace
		declaClass = declaNS.add new CodeBlock.ClassBlock "class Project"
		declaClass.add(new CodeBlock.CodeBlock "public:", false).add "static void expose(v8::Handle<v8::Object> target);"
		
		#implementation
		
		implNS = new CodeBlock.NamespaceBlock @targetNamespace
		fn = implNS.add new CodeBlock.FunctionBlock "void Project::expose(v8::Handle<v8::Object> target)"
		
		_.each exposed, (clExposed) ->
			fn.add clExposed + "::_InitJSObject(target);"
		
		fn.add "ExposeConstants(target);"
		
		ret = 
			h: declaNS
			cpp: implNS
		
		return ret
		
	ifdefH: (header, fileName) ->
		hFile = new CodeBlock.CodeBlock 
		cond = fileName.replace(/\./, '_').toUpperCase();
		hFile.add "#ifndef " + cond
		hFile.add "#define " + cond
		hFile.add header
		hFile.add "#endif //#ifndef " + cond
		return hFile
		
	convertFull: ->
		cppFile = new CodeBlock.CodeBlock 
		hFile = new CodeBlock.CodeBlock
		
		cppFile.add @cpp
		hFile.add @header
		nsBea = cppFile.add new CodeBlock.NamespaceBlock "bea"
		
		nsBea.add @typeMgr.createConversions()
		
		convClasses = []
		
		_.each @classes, (cl) =>
			@stats.classes++
			cv = new ClassConverter(@options)
			ret = cv.processClass cl, @targetNamespace
			
			#Global functions/declarations
			if not ret.global.empty() then cppFile.add ret.global	
			
			#the actual implementation, in the cppNS namespace
			if not ret.impl.empty() then cppFile.add ret.impl
			
			convClasses.push ret.eClassName #exposed class name
			
			#the declarations
			hFile.add ret.decla
		
		nsCPP = cppFile.add new CodeBlock.NamespaceBlock @targetNamespace
		nsH = hFile.add new CodeBlock.NamespaceBlock @targetNamespace
		nsCPP.add @convertConstants()
		nsH.add "static void ExposeConstants(v8::Handle<v8::Object> target);"

		
		#create the bea exposer
		ret = @createBeaExposer convClasses
		if ret.h then hFile.add ret.h
		if ret.cpp then cppFile.add ret.cpp
		
		hFile = @ifdefH hFile, @hFilename
		
		fs.writeFileSync @cppFilename, cppFile.render(), 'ascii'
		fs.writeFileSync @hFilename, hFile.render(), 'ascii'		
		
	convertManual: ->
		#check if the file exists. 
		res = fs.statSync(@cppFilename)
		
		#bail out if -f command line switch is not preset - we don't want to overwrite the cpp file which the user might have modified
		if res && res.size > 0 && !@options.force 
			@error "#{@cppFilename} already exists. Use -f switch to overwrite."
			return false
			
			
		cppFile = new CodeBlock.CodeBlock 
		cppFile.add @cpp
		cppFile.add "using namespace bea;"
		
		nsBea = new CodeBlock.NamespaceBlock "bea"
		nsBea.add @typeMgr.createConversions(@options.manual)
		
		if !nsBea.empty() then cppFile.add nsBea
		
		
		_.each @classes, (cl) =>
			@stats.classes++
			cv = new ClassConverter(@options)
			ret = cv.processClass cl, @targetNamespace
			
			#Global functions/declarations
			if not ret.global.empty() then cppFile.add ret.global	
			
			#the actual implementation, in the cppNS namespace
			if not ret.impl.empty() then cppFile.add ret.impl
		
		fs.writeFileSync @cppFilename, cppFile.render(), 'ascii'
		
	CONVERT: ()->
		#try
			if @options.manual
				@convertManual()
			else
				@convertFull()
		#catch e
		#	@error "Exception: " + e
			
	load:  (@curFileName) ->
		
		parser = new RecursiveParser
		
		root = parser.parseFile @curFileName
		
		return false unless root
		
		_.each root.children, (node, i) =>
			switch node.type()
				when "@targetNamespace" then @setTargetNamespace node
				when "@namespace" then @namespace node
				when "@header" then @addHeader node
				when "@cpp" then @addCpp node
				when "@hfilename" then @setHFileName node
				when "@cppfilename" then @setCPPFileName node
				when "@const" then @addConst node
				when "@comment" then ""
				else @warn "Unknown directive: #{node.type()}", node
				
		if _.isEmpty @targetNamespace 
			@warn "@targetNamespace not defined. ", parser.root
			@targetNamespace = 'targetNamespace'
		
		return true
	
#############

doConvert = (bea, beaFile) ->
	start = Date.now()

	if bea.load(beaFile) 
		console.log "Successfully loaded and parsed #{beaFile}"
	else
		console.log "Fatal error: Could not parse #{beaFile}"
		process.exit -2

	if not bea.options.manual
		console.log "Output header file: #{bea.hFilename}"
	else
		console.log "*** -manual switch present. Only producing manual conversions."
		
	console.log "Output cpp file: #{bea.cppFilename}"
		
	console.log "Converting..."

	bea.CONVERT()

	console.log "Conversion finished in " + (Date.now() - start) + " ms."

	console.log "Conversion results:"
		
	console.log util.inspect bea.stats

	if bea.stats.manual > 0 && !bea.options.manual 
		console.log "***"
		console.log "Note: There are #{bea.stats.manual} manual functions which have not been converted. You must implement these manually."
		console.log "Tip: You can generate the empty methods with the -manual switch (must output to different .cpp file)."
	

exports.doConvert = doConvert
exports.BeaLoader = BeaLoader


				
		
		
		
		
		
		