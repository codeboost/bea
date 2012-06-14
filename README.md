What is bea?
============

Bea helps you expose C++ libraries to Javascript.

What does it do ?
=================

It generates the 'glue' code between your C++ classes and the V8 Javascript engine.
The objects and functions which you want to expose are defined in special '.bea' files.
Bea parses these files and generates a .h and .cpp which you include in your project and build it.
Then you can write Javascript applications which use your C++ classes.

So far, bea has been successfully used to expose the OpenFrameworks C++ library to Javascript (https://github.com/codeboost/JOpenFrameworks),
OpenGL 1.1 and the OpenCV library.


What is supported / Features ?
==============================

* Static functions
* C++ classes
* Virtual functions -- allows you to subclass and override C++ virtual functions from Javascript
* Multiple inheritance is supported
* Raw pointers and buffers 
* Pointers from javascript Array and vice-versa
* Javascript accessors from member variables
* Object-notation js types to native C++ types

Installing & Running 
===========
Install node.js, then Coffee-Script, then run npm install to get bea dependencies:
	
	npm install -g coffee-script
	...
	git clone git@github.com:codeboost/bea.git 
	cd bea
	npm install
	
After that, you can run bea, like so:

	coffee bea fileName.bea 


	
Bea file syntax
===============

Please read the DOCUMENTATION.md file.
