require.load [
			{id: 'underscore', 	url: 'lib/underscore.js'},
			{id: 'fs',			url: 'lib/web/fs.js'},
			{id: 'util',		url: 'lib/web/util.js'},
			'beaparser.js',
			'codeblock.js',
			'mgr.js',
			'classconvert.js',
			'beautils.js',
			'bealoader.js',
			'snippets.js'
			]
			
class BeaWeb
	constructor: ->
		@bealoader = require 'bealoader'
		@beaSource = "Enter bea text here"
		@fileSystem = require('fs').fsFiles
		@fileSystem['out_h'] = '' 
		@fileSystem['out_cpp'] = ''
			
	beaSourceChange: ->
		#save it into the 'fileSystem'
		@fileSystem['beaSource'] = @beaSource
		
	compile: ->
		bea = new @bealoader.BeaLoader 'beaSource'
		bea.hFilename = 'out_h'
		bea.cppFilename = 'out_cpp'
		@bealoader.doConvert bea, 'beaSource'
		
		

window.BeaWeb = BeaWeb		
#window.onload = ->
	#angular.compile(window.document)()
	
