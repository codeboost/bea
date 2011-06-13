_ = require 'underscore'
class BeaNode
	constructor: (@text, @level, @fileName = "", @line = 0)->
		@children = []
		@parent = null
	
	addChild: (node)->
		if typeof node == "string" then node = new BeaNode node, @level + 1, @fileName
		node.parent = this
		@children.push node
		node
	
	#find child by exact text
	findChild: (text)->
		_.detect @children, (node)-> node.text == text
	
	#returns the 'type' of the node. Basically the first word of the line or 'comment'
	type: ->
		if /^\/\/|^\#/.test @text then return '@comment'
		tmp = @text.split(' ')
		return tmp[0]
		
	#flattens children into a joined string (???) - make a string out of all children
	toString: (joinStr = '\n') ->
		if @children.length == 0 then return ""
		_.compact(_.flatten(_.map @children, (node) -> [node.text, node.toString(joinStr)])).join joinStr
	
	#returns a child of type() type
	childType: (type) ->
		_.detect @children, (node) -> node.type() == type
		
	#return list of children which match re
	matchChildren: (re) ->
		_.select @children, (node) -> re.test node.text
	
	
			
class BeaParser 
	#preserveWhitespace means preserve starting whitespace. Trailing whitespace is removed
	constructor: (@fileName = "", @preserveWhitespace = false, @preserveComments = false) ->
		@root = new BeaNode "", 0, @fileName, 0
		@curNode = @root
		
	#parse a line of text.
	#Indentation determines the node's level
	#Throws exception if indentation is invalid
	parseLine: (txt, linenumber) ->

		level = txt.match(/(^\s+)/g)?[0].length; level?=0; level++
		
		rawTxt = txt.replace(/^\s+|\s+$/g, '')
		
		return null unless rawTxt.length
		
		if !@preserveComments 
			#internal comments can start with #
			#escaped hash must be added as node: \#
			
			return null if rawTxt[0] == '#'			
			
			#in-string comments 
			rawTxt = rawTxt.replace /[^\\]\#.*/, ''
			rawTxt = rawTxt.replace /\\#/g, '#'
				
		if !@preserveWhitespace 
			txt = rawTxt
		else
			txt = txt.replace(/\s+$/g, '') #trailing whitespace
			
		return null unless txt.length
		
		#replace all tab chars with spaces 
		txt = txt.replace /\t/g, ' '
		
		node = new BeaNode txt, level, @fileName, linenumber + 1
		
		if level == @curNode.level
			@curNode.parent.addChild node
		else if level >= @curNode.level + 1
			@curNode.addChild node
		else if level < @curNode.level 	
			#walk up until we find the parent 
			tmp = @curNode
			while tmp && tmp.level > level
				tmp = tmp.parent
			if tmp && tmp.parent
				tmp.parent.addChild node
			else
				throw "Invalid indent on line " + (linenumber + 1) + ": '" + txt + "'"

		@curNode = node		

	parse: (txt) ->
		_.each txt.split('\n'), @parseLine, this

exports.BeaParser = BeaParser