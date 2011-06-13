
util = require 'util'
_ = require 'underscore'
debugIt = require('./debugit').debugIt;

a1 = [{one: "1"}, {two: "2"}, {three: "3"}]
a2 = [{one: "1"}, {two: "2"}, {three: "3"}, {four: "4"}]


res = _.isEqual a1, a2


debugIt ->
	
	fs = require 'fs'

console.log res

