#Barebone simple unit testing
ok = (expr, msg, actual) ->
	if expr 
		console.log "PASSED: " + msg
	else
		if not actual
			console.log "FAILED: " + msg
		else
			console.log "FAILED: " + msg + "; Actual value = " + actual
		

test = (name, fnTest) ->
	console.log "*****"
	console.log name
	try
		fnTest();
	catch e
		ok false, "Exception thrown for '" + name + "': " + e.message 

mustThrow = (name, fn) ->
	excepted = false
	try
		fn();
	catch e
		excepted = true; 
	
	if !excepted
		ok false, "Exception not thrown for '" + name + "'"
	else
		ok true, "Exception thrown for '" + name

		
exports.ok = ok
exports.test = test
exports.mustThrow = mustThrow