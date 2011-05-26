_ = require('underscore')
BeaParser 		= require('./beaparser').BeaParser
CodeBlock 		= require('./codeblock').CodeBlock
mgr 			= require('./mgr')		
ClassConverter 	= require('./classconvert').ClassConverter
beautils 		= require('./beautils')
fs = require 'fs'
util = require 'util'


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
		
	error: (msg) ->
		console.log msg
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
		
		console.log 'Included file ' + fileName
		
		return @parseFile fileName
		
	processIncludes: (root) ->
		
		children = root.children
		gr = 0
		_.each root.children, (node, i) =>
			if node.type() == '@include' 
				ret = @include node
				retc = ret?.children ? []
				children = children.slice(0, i + gr).concat(retc, children.slice(i + gr + 1))
				if retc.length then gr = gr + retc.length - 1
		root.children = children
		return root
		
class MessageLogger
	@warnings: 0
	
	warn: (msg, node) ->
		[fileName, line] = [(node?.fileName) ? "", (node?.line) ? 0]
		console.log "#{fileName}(#{line}): warning: #{msg}"
		@warnings++
		
	info: (msg, node) ->
		[fileName, line] = [(node?.fileName) ? "", (node?.line) ? 0]
		if @verbose then console.log "#{fileName}(#{line}) : " + msg
		
	error: (msg, node) ->
		[fileName, line] = [(node?.fileName) ? "", (node?.line) ? 0]
		console.log "#{fileName}(#{line}): fatal error: #{msg}"
		process.exit -1
	

class BeaLoader extends MessageLogger
	constructor: () ->
		
		@classes = []	#list of defined classes
		@namespaces = {} #namespace definitions
		@typeMgr = new mgr.TypeManager this, @namespaces
		@constants = []
		@verbose = true
		@targetNamespace = ""
		@projectName = ""
		@outDir = '.'
		
		@files = 
			cpp: 'out.cpp'
			h: 'out.h'
			manualcpp: 'manual.cpp'
			manualh: 'manual.h'
		
		@options = 
			manual: false
			typeManager: @typeMgr
			logger: this
			mtypes: false
			derivedPrefix: '_D_'
			environ: {}
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
			warnings: 0
			
	filenameFromNode: (node) ->
		filename = node.text.replace /^@\w+\s*=?\s*/, ''	#remove node type
		filename = filename.replace /\"|\'/g, '' 	#remove quotes
		filename = filename.replace /\s+/g, '_'		#convert spaces to underscore
		return filename
		
	mkpath: (fileName) ->
		return @outDir + '/' + fileName
			
	setProject: (node) ->
		
		if @projectName != '' then return @warn "@project already set.", node
		
		@projectName = node.text.replace(/^@project\s+/, '')
		@info "Project name set to #{@projectName}", node
		
		@files = 
			cpp: @projectName + '.cpp'
			h: @projectName + '.h'
			cppm: @projectName + '_m.cpp'
			hm: @projectName + '_m.h'
			
		_.each node.children, (child) =>
			switch child.type()
				when "@h" then @files.h = @filenameFromNode child
				when "@cpp" then @files.cpp = @filenameFromNode child
				when "@hmanual" then @files.hm = @filenameFromNode child
				when "@cppmanual" then @files.cppm = @filenameFromNode child
				
		@info "Files set to " + util.inspect(@files), node
	
	setTargetNamespace: (node) ->
		@targetNamespace = node.text.replace(/^@targetNamespace\s+/, '')
		@targetNamespace = @targetNamespace.replace(/\"|\'/g); 
		
	addClass: (classNode, namespace) ->	
		@classes.push 
			namespace: namespace
			node: classNode
		
		if not /^@static\s+/.test classNode.text
			@typeMgr.addClassNode classNode, namespace
			
	addConst: (node) ->
		_.each node.children, (con) =>
			@constants.push con.text
			
	parseNamespace: (nsNode) ->	
		nsname = nsNode.text.replace /^@namespace\s*/, ''
		_.each nsNode.children, (node) =>
			switch node.type()
				when "@class" then @addClass node, nsname
				when "@static" then @addClass node, nsname
				when "@type" then @typeMgr.add node, nsname
				when "@comment" then false
				when "}", "};", "{" then false
				else @warn "Unexpected '#{node.type()}' within namespace #{nsname}", node
		
	addHeader: (hNode) ->
		@header = hNode.toString('\n')

	addCpp: (cppNode) ->
		@cpp = cppNode.toString('\n')
		
	convertConstants: ->
		if @constants.length == 0 then return false
		
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
		
		if @constants.length > 0 then fn.add "ExposeConstants(target);"
		
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
		if not @canWriteFile(@files.cpp) then return false
		if not @canWriteFile(@files.h) then return false

		cppFile = new CodeBlock.CodeBlock 
		hFile = new CodeBlock.CodeBlock
		
		if @cpp then cppFile.add @cpp
		if @header then hFile.add @header
		
		nsBea = cppFile.add new CodeBlock.NamespaceBlock "bea"

		convClasses = []

		
		@options.typeMgr = @typeMgr
		
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
		

		#create type conversions
		nsBea.add @typeMgr.createConversions()

		
		if @constants.length
			nsCPP = cppFile.add new CodeBlock.NamespaceBlock @targetNamespace
			nsH = hFile.add new CodeBlock.NamespaceBlock @targetNamespace
			nsCPP.add @convertConstants()
			nsH.add "static void ExposeConstants(v8::Handle<v8::Object> target);"

		
		#create the bea exposer
		ret = @createBeaExposer convClasses
		if ret.h then hFile.add ret.h
		if ret.cpp then cppFile.add ret.cpp
		
		hFile = @ifdefH hFile, @files.h
		
		out = 
			cpp: cppFile.render()
			h: hFile.render()
		fs.writeFileSync @mkpath(@files.cpp), out.cpp, 'ascii'
		fs.writeFileSync @mkpath(@files.h), out.h, 'ascii'		
		return out
		
	canWriteFile: (fileName) ->
		outFilename = @mkpath(fileName)
		
		try
			#check if the file exists. 
			res = fs.statSync(outFilename)
			
			#bail out if -f command line switch is not preset - we don't want to overwrite the cpp file which the user might have modified
			if res && res.size > 0 && !@options.force 
				@error "#{outFilename} already exists. Use -f switch to overwrite."
				return false
		catch err
			return true
		return true
		
		
	convertManual: ->
		if not @canWriteFile(@files.cppm) then return false
			
		cppFile = new CodeBlock.CodeBlock 
		if @cpp then cppFile.add @cpp
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
		
		out = 
			cpp: cppFile.render()
			
		fs.writeFileSync @files.cppm, out.cpp, 'ascii'
		return out
		
	CONVERT: ()->
		#try
			if @options.manual
				return @convertManual()
			else
				return @convertFull()
				
			@stats.warnings = @warnings
		#catch e
		#	@error "Exception: " + e
			
	load:  (fileName) ->
		
		parser = new RecursiveParser
		
		root = parser.parseFile fileName
		
		return false unless root
		
		_.each root.children, (node, i) =>
			switch node.type()
				when "@project"	then @setProject node
				when "@targetNamespace" then @setTargetNamespace node
				when "@namespace" then @parseNamespace node
				when "@header" then @addHeader node
				when "@cpp" then @addCpp node
				when "@const" then @addConst node
				when "@comment" then false
				when "}", "};", "{" then false
				else @warn "Unknown directive: #{node.type()}", node
				
		if _.isEmpty @targetNamespace 
			@warn "@targetNamespace not defined. ", parser.root
			@targetNamespace = 'targetNamespace'
			
		if !@projectName 
			@warn "@project directive not found."
			return false
		
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
		console.log "Output header file: #{bea.files.h}"
		console.log "Output cpp file: #{bea.files.cpp}"
	else
		console.log "*** -manual switch present. Only producing manual conversions."
		console.log "Output header file: #{bea.files.hmanual}"
		console.log "Output cpp file: #{bea.files.cppmanual}"
		
	
		
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
exports.version = '0.5'


				
		
		
		
		
		
		