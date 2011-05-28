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

Running bea
===========

	bea fileName.bea [-o outputDir -m -f]
	-o = the output directory
	-m = only the blank implementation of @manual methods and types will be written to the file specified in the @project directive
	-f = force file overwrite. If this parameter is not present and the file already exists, the program will exit
	

	
Bea file syntax
===============

Please read the DOCUMENTATION.md file.
