_ = require './lib/underscore'
beautils = require('./beautils').u


class Code
	constructor: (@declaration) ->	
	
	render: ->
		@declaration

class CodeBlock extends Code 
	constructor: (@declaration, @braced=true) ->
		@children = []
		
	empty: ->
		return @children.length == 0
		
	render: ->
		content = _.map(@children, (childBlock) -> childBlock.render()).join '\n'
		if @declaration && @declaration.length
			if @braced
				"""#{@declaration} {
				#{beautils.tabify content, 1}
				}""" 
			else
				"""#{@declaration}
				#{beautils.tabify content, 1}"""
		else
			"#{content}"
			
	add: (childBlock) ->
		
		throw "Invalid block" if childBlock is undefined
			
		if _.isArray childBlock
			lastblock = null
			_.each childBlock, (child) ->
				if _.isArray child 
					lastblock = lastblock?.add child
				else
					lastblock = @add child
			, this
			return lastblock
		
		if typeof childBlock is "string"
			childBlock = new Code childBlock
		
		@children.push childBlock
		childBlock
		
class NamespaceBlock extends CodeBlock
	constructor: (namespace) ->
		super "namespace " + namespace
	render: ->
		super() + "\n"

class ClassBlock extends CodeBlock
	constructor: (declaration) ->
		super declaration
	render: ->
		super() + ";\n"
		
class FunctionBlock extends CodeBlock
	constructor: (declaration) ->
		super declaration
	render: ->
		super() + "\n"
		

test = ->
	_.delay ->
		namespace = new NamespaceBlock "jocT", [
			"class MyClass",  [
				'void doSomething()',  [
					"int k = 0;"
					"for (k = 0; k < 100; k++)", [
						"cout << k << endl;"
					]
				],
				'std::vector<int> somethingElse(int k, char* value)', [
					"char* name = new char [k + 1];"
					"std::vector<int> ret;"
					"for (int i = 0; i < k; i++)", [
						"ret.push_back(i)"
					]
					"return ret"
				]
			]
		]

		console.log namespace.render()
	, 10000

exports.CodeBlock = 
	Code: Code
	CodeBlock: CodeBlock
	NamespaceBlock: NamespaceBlock
	ClassBlock: ClassBlock
	FunctionBlock: FunctionBlock
