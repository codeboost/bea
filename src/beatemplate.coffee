_ = require 'underscore'
BeaParser = require('./beaparser').BeaParser
fs = require 'fs'
debugIt = require('./debugIt').debugIt

#Holds all templates used in the bea process
class TemplateManager
	constructor: (fileName = 'code-templates.bea') ->
		str = fs.readFileSync fileName, 'ascii'
		throw 'Template load failed: #{fileName}' if str.length == 0
		@parser = new BeaParser true
		try
			@parser.parse str
		catch e
			throw 'Template load failed #{fileName}: ' + e
		
	getTemplate: (name) ->
		childNode = @parser.root.findChild(name);
		
		if childNode then return childNode.toString()
		return ""
	#replaces all variables in the template (keys in obj) with the values in obj
	render: (name, obj) ->
		if name.match(/^template\s+/) == null then name = 'template ' + name
		str = @getTemplate name
		return "" unless str.length > 0
		_.each obj, (val, key) ->
			if _.isArray val then val = val.join '\n'
			str = str.split('$' + key).join(val);
		str
	
exports.TemplateManager = TemplateManager