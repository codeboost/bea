_ = require './lib/underscore'
class BeaNode
	constructor: (@text, @level, @fileName = "", @line = 0)->
		@children = []
		@parent = null
	
	addChild: (node)->
		node.parent = this
		@children.push node
		node
	
	#find child by exact text
	findChild: (text)->
		_.detect @children, (node)-> node.text == text
	
	#returns the 'type' of the node. Basically the first word of the line or 'comment'
	type: ->
		if @text.match(/^\/\//) then return "comment"		
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
		_.select @children, (node) -> node.text.match(re)?
	
	
			
class BeaParser 
	#preserveWhitespace means preserve starting whitespace. Trailing whitespace is removed
	constructor: (@fileName = "", @preserveWhitespace = false) ->
		@root = new BeaNode "", 0, @fileName, 0
		@curNode = @root
		
	#parse a line of text.
	#Indentation determines the node's level
	#Throws exception if indentation is invalid
	parseLine: (txt, linenumber) ->
		level = txt.match(/(^\s+)/g)?[0].length; level?=0; level++
		
		rawTxt = txt.replace(/^\s+|\s+$/g, '')
		
		
		return null unless rawTxt.length > 0
		#internal comments can start with #
		return null if rawTxt[0] == '#'
		
		#escaped hash must be added as node: \#
		if rawTxt.length > 2 && rawTxt[0] == '\\' && rawTxt[1] == '#'
			rawTxt = rawTxt.slice(1)
		
		if !@preserveWhitespace 
			txt = rawTxt
		else
			txt = txt.replace(/\s+$/g, '') #trailing whitespace
		
		node = new BeaNode txt, level, @fileName, linenumber + 1
		
		if level == @curNode.level
			@curNode.parent.addChild node
		else if level == @curNode.level + 1
			@curNode.addChild node
		else if level < @curNode.level 	
			#walk up until we find the parent 
			tmp = @curNode
			while tmp.level > level
				tmp = tmp.parent
			tmp.parent.addChild node
		else
			throw "Invalid indent on line " + (linenumber + 1) + ": '" + txt + "'"

		@curNode = node		

	parse: (txt) ->
		_.each txt.split('\n'), @parseLine, this

exports.BeaParser = BeaParser