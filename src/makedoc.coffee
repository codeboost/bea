#Make documentation from a bea-formatted file
BeaParser = require('./beaparser').BeaParser
CodeBlock = require('./codeblock')
_ = require 'underscore'
debugIt = require('./debugit').debugIt
util = require 'util'
fs = require 'fs'

if process.argv.length < 3 
	console.log 'Cannot! You must specify a file'
	process.exit -1

getCode = (node, lang) ->
	title = node.children[0].text.match(/\s*:\s*(.+)/)?[1]
	if title then title = '|title=' + title
	node.children[0].text = ''
	childBlock = "{newcode:#{lang}#{title}}\n" + node.toString() + "{newcode}"
	
	
processChild = (node) ->	
	childBlock = ""
	if node.children?.length
		if /^\s*\/\/C\+\+/.test node.children[0].text
			childBlock = getCode node, "CPP"
		else if node.children && /^\s*\/\/[J|j]ava[s|S]cript/.test node.children[0].text
			childBlock = getCode node, "javascript"
		else
			childBlock = _.map(node.children, (node) -> processChild node).join ''
			
	if node.level < 2
		nodeText = "\nh#{node.level + 1}.#{node.text}"
	else
		nodeText = node.text
		
	return nodeText + "\n" + childBlock
	
	
confluence = (root) ->
	ret = processChild root
	console.log ret


parser = new BeaParser process.argv[2], true, true
contents = fs.readFileSync process.argv[2], 'ascii'
parser.parse contents
confluence(parser.root)






