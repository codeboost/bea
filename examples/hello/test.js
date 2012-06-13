_ = require('./underscore'); //Yes, you can do this!

log("In Javascript!");
var item = new Item();

log("item.name() should be (no name): " + item.name());

//Instantiate with another constructor
item = new Item("my name is");
log("item.name() should be my name is: " + item.name());

item = new Item("John");

//Call the normal (non-overloaded) function
var msg1 = item.sayHello("How are you today?");
log(msg1);


//Override greet()
function ItemSubclass(){
	this.greet = function(){
		return " says from javascript subclass: ";
	}
}

_.extend(item, new ItemSubclass());

msg = item.sayHello("How are you today?");
log(msg);

//Another, simpler way to override a virtual function
item.greet = function(){
	return " says from yet another subclass: ";
}

msg = item.sayHello("How are you today?");
log(msg);
