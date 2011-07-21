fs = require 'fs'
BeaParser 		= require('./beaparser').BeaParser
_ = require 'underscore'

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
		
exports.RecursiveParser = RecursiveParser