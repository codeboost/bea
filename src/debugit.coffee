exports.debugIt = (fn) ->
	console.log 'Press c to continue or any key to quit'
	tty = require 'tty'
	tty.setRawMode true		
	process.stdin.resume()		
	process.stdin.on "keypress", (char, key) ->		
		if key && key.name == 'c' 
			fn()
		else
			console.log 'aborted'
			process.exit(0)