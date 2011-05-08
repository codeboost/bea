bealoader = require './bealoader'
fs = require 'fs'
debugIt = require('./debugIt').debugIt

console.log "Bea C++ to V8 Converter 0.1" 
args = require('./lib/argsparser').parse()

if args["node"].length < 2  
	console.log "Error: bea file not specified. Nothing to do."
	process.exit -1

beaFile = fs.realpathSync args["node"][1]
bea = new bealoader.BeaLoader beaFile

if args["-manual"] || args["-m"] then bea.options.manual = true
if args["-mtypes"] || args["-mt"] then bea.options.mtypes = true
if args["-force"] || args["-f"] then bea.options.force = true

if bea.options.manual && !args["-oc"] 
	console.log "Error: -manual present, but no -oc. You must specify output file for manual generation." 
	process.exit -1
	
if bea.options.mtypes && !args["-oh"]
	console.log "Error: -mtypes present, but no -oh. You must specify output header file for manual types generation."
	process.exit -1
	

if args["-oh"] then bea.hFilename = args["-oh"]
if args["-oc"] then bea.cppFilename = args["-oc"]


bealoader.doConvert bea, beaFile
console.log "Exit"