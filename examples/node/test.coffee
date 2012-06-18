hello = require './build/Release/addon.node'

console.log hello

item = new hello.Item("Two")

console.log item.name();

item.greet = -> " is happy "

console.log item.sayHello("world");