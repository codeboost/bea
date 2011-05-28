Running bea
===========

	bea fileName.bea [-o outputDir -m -f]
	-o = the output directory
	-m = only the blank implementation of @manual methods and types will be written to the file specified in the @project directive
	-f = force file overwrite. If this parameter is not present and the file already exists, the program will exit
	

Bea file syntax
===============

A bea file is a mixture of special directives (starting with @), C++ declarations and snippets of C++ code.

Bea has been written in CoffeeScript and quite frankly, it has been one the most pleasurable programming experiences in my life. 
The syntax of the bea file tries to borrow from the cleanliness of CoffeeScript (which borrows from Python/Ruby) - braces, semi-columns, etc are optional

The bea parser builds a tree of nodes from the file, based on line indentation.
Each line is a node in the tree, lines below it, which are more indented, are it's children:
	
	//Bea file structure
	Line
		Child Line
			Child of Child line
	AnotherLine
		AnotherLine child
		
Comments start with #. C++ style comments (//) can only be used in C++ code/class declaration. C-style (/* ... */) comments are not supported.
Lines which must start with '#' (usually inserted C++ preprocessor definitions) can be escaped:

		#This is a comment, but next line is not
		\#include <header.h>

Bea directives start with the '@' character:

		//bea
		@include "constants.bea"
		@namespace myproject
			@class myclass
	
Directives
==========

The following directives can only appear within the root indent of the file.

@header
=======

Child lines of the @header directive will be inserted at the top of the generated header file. Usually some #include statements.

		#Bea
		@header
		\#include <v8.h>
		
		//Generated C++
		#include <v8.h>
		

@cpp
====

Child lines of the @cpp directive will be inserted at the top of the generated cpp file. Usually, some #include statements:

		@cpp
			\#include "myfile.h"
			\#define MYCONDITION(x);
			using namespace myproject;
		
		//C++: Generated C++ -> myproject.cpp
		#include "myfile.h"
		#define MYCONDITION(x);
		using namespace myproject;
			
@const
======
		
All child lines are the constants which are exposed to the javascript. 

		#Bea
		@const 
			EACCESS
			DBL_MAX
			BUFFER_SIZE

		//C++: Generated C++
		namespace jmyproject{
			void ExposeConstants(v8::Handle<v8::Object> target) {
				BEA_DEFINE_CONSTANT(target, EACCESS);
				BEA_DEFINE_CONSTANT(target, DBL_MAX);
				BEA_DEFINE_CONSTANT(target, BUFFER_SIZE);	
			}
		}
			
			
Note that only the names of the constants must be entered. It is assumed that during compilation, the C++ compiler knows the values of the constants. 
Tip: You can add a 'using namespace' statement in the @cpp section if your constants/enums are defined in some other namespace. 

@targetNamespace namespaceName
==============================

The namespace where the generated exposable code will be placed. Quotes are optional. 

@include "filename.bea"
=======================

Include another bea file. This is done recursively. Note that some directives should only appear once (like @targetNamespace) so make sure that the included files don't override
previously defined directives. I see including the file as pasting it in the main bea file in place of the @include line (or rather, replacing the '@include' node with the children of the
root node of the included file).

@namespace native_namespace
===========================
Context: Root

This is the C++ namespace of the object(s) you want to expose. If no namespace name is entered, it is assumed that the classes/functions defined below are globally accessible.
The children of the @namespace are the objects and types which you want to expose to the Javascript.
If the custom types used in function declarations don't have an implicit namespace, these types are assumed to be part of the parent @namespace.

	#bea
	@namespace cv	
		#expose cv::Mat
		@class Mat	
			Mat(Size sz, int type) #__constructor(cv::Size sz, int type)
		@static Global
			#bool clipLine(cv::Size imgSize, cv::Point pt1, cv::Point& pt2)
			bool clipLine(Size imgSize, Point& pt1, Point& pt2)	
			#void namedWindow(const std::string& winname, int flags)
			void namedWindow(const std::string& winname, int flags)
				


@class className exposedName : public Base1, public Base2
=========================================================
Context: @namespace
Sample:

		//bea
		@namespace ns
			@class MyClass
				MyClass(const int number, bool option = false); #semicolon ; at the end is optional
				MyClass(const std::string& name, int id = 0, const std::vector<int>& numbers) #argument types and default values
				int sum(const std::vector<int>* numbers) #references
				MyClass* clone() #Custom type/pointer return values
				
				
		
		//Javascript
		#1
		var obj = new MyClass();			//throws 'Couldn't determine overload from supplied arguments'
		#2
		var obj = new MyClass(0);			//calls MyClass::MyClass(const int, bool)
		var obj = new MyClass("my name");	//calls MyClass(const std::string&, int, std::vector<int>&)
		
		res = obj.myMethod({x: 0, y: 0});	//assume we a conversion for ns::Point to/from JS is defined

Exposes a class to the javascript. The exposed class can be instantiated with javascript's new operator (eg. obj = new className)
className must be a valid C++ class declared in the C++ namespace which is defined by the parent @namespace directive.
exposedName is the name of the exposed object in Javascript. If exposedName is ommited, className will be used.

@class children are the exposed functions. The function declarations are mostly identical to the way they are declared in the C++ class
(without the private, protected or public modifiers).
You can add multiple overloads of the same function or multiple constructor overloads.
	
Inheritance
===========

As in C++, you can declare the base classes of a class. Note that these must also be defined in the .bea file, *before* the compiler sees the current class.
The way inheritance works is described in the chapter Inheritance.

Exposed class methods
=====================

Exposed methods are declared as children of the @class or @static directives.
A method is declared just like the declaration in C++:

	@class MyClass
		int method(int param1, std::string param2, double param3 = 0.0)

Bea will place the method within the @targetNamespace::J@class class. Each argument will be converted from Javascript to native type
and then the code for the native call is inserted.
All arguments are converted from JS through specializations of bea::Convert<T>.
For @class, the native calls are rendered as _this->methodName(arguments). _this is the pointer to an instance of the class being exposed (cast from javascript's args.This())
For @static, methods are rendered as @namespace::methodName(arguments)


If the function requires a different implementation than what Bea is generating, the method declaration can be perceded by the @manual directive.

	@class MyClass
		@manual int method(MyCustomType* type)
		
This tells Bea not to generate the function call implementation.
Child lines of the method declaration are called 'sublines'. These are snippets of C++ code which will be inserted between the argument conversions and 
the native call. It can be used to place guards for argument values/ranges in here, using the build in macro THROW_IF_NOT(truth, "message");
	
	@class MyClass
		int sum(std::vector<int> numbers)
			THROW_IF_NOT(numbers.size() > 0, "Non-empty array expected");


The way the native method is invoked can also be customized, using the @call directive.

		
@type
=====
Context: @namespace

Type conversion

The main problem with exposing C++ objects to Javascript is the conversion of types between Javascript and native code and vice-versa.
Bea tries to simplify this problem, by providing conversions for most native types as well as a way to generate custom conversions.
When Javascript makes a call into the native code, the arguments passed to the javascript function must first be converted to native
types and then passed on to the native function.

Suppose we have the following C++ class, which has a method "process" and takes some arguments:

	//C++
	class SomeObject{
		...
		void process(int times, std::string name, std::vector<int> list, const Size& size);
	};
	
The natural way to call this function from the script would be this:

	//Javascript
	res = SomeObject.process(1, "String value", [1, 2, 4], {width: 100, height: 100});


There are some great libraries out there which facilitate type conversion (v8-convert, cp-v8proxy), but they only solve half the problem.
Since Javascript is weakly typed, it will not complain if you pass a String argument instead of an integer or undefined instead of an Object.
In many cases, just converting the arguments will work (eg. undefined becomes 0, "123"=>123), but calling the native functions with invalid values can 
often lead to disastrous results. Last thing we want is the script (easily) crashing our app.
Bea solves this problem by strictly checking the type of the supplied arguments and throwing an exception back to the javascript when the type supplied
is not the one expected by the native function. Also, an exception is thrown if the number of arguments is invalid.
In our case, the following things will happen:

	//Javascript
	someObject = new SomeObject();
	someObject.process(1);	//throws "Invalid number of arguments"
	someObject.process(1, "String", undefined, undefined);	//throws: "Argument 3 - Array expected"
	someObject.process(1, "String", [], {not: 1, size: 0}); //throws: "Argument 4 - Object with 'width', 'height' members expected"
	
Isn't this cool ? Now the C++ code is guarded from undefined, misplaced arguments and strings passed as integers (things which the C++ compiler would complain about).
Apart from checking weather the argument values are within the allowed range, one doesn't have to worry about type validity.

	//Javascript
	SomeObject.process(1, "String", [], {width: "string", height: 1});//throws: Argument 4 - Integer expected

This is because members of objects are also cast from Javascript and 'width' will throw "Integer expected".

TODO: fix the exception so that it shows the correct invalid member.

Defining types
==============
	
Bea makes it possible to define conversions for custom types.
In C++, conversions are done by specializing the bea::Convert structures with the native type.

	//C++
	template <class T>
	struct Convert{
		static bool Is(v8::Handle<v8::Value> v){ return false; }	//Is type T ?
		static T FromJS(v8::Handle<v8::Value> v, int nArg);			//Convert from Handle<Value> to type T
		static Handle<Value> ToJS(const T& val);			//Convert from T to Handle<Value>
	};
	
For example, bea::Convert<int> does conversions from/to type int, bea::Convert<cv::Size> does conversions from cv::Size.
Bea will generate the conversion functions for the types defined in the .bea file.
All conversions must be defined within the 'bea' namespace.


The 'type' directive defines a type used by one of the exposed objects. The syntax is the following:
	
	#Bea
	namespace nativeNamespace
		type TypeName [castfrom] [CastType]
			[Type members]
	
TypeName - is the name of the type. If a namespace is not specified for TypeName, the parent namespace is assumed.

If nothing else is defined (castfrom or type members), the compiler assumes that custom conversions are already implemented, eg:

	type std::string
	

castfrom - generate conversion by casting from CastType to TypeName. For instance:
	
		type size_t castfrom int

Tells the compiler to generate conversion functions which cast from int to size_t:

		struct Convert<size_t>{
			static size_t FromJS(v8::Handle<v8::Value> v, int nArg) {
				return (size_t)bea::Convert<int>::FromJS(v, nArg);
			}
			//...
		}

Note that the type (after resolving typedef's) must be different but cast-able from the castfrom type, otherwise the C++ compiler will be unable to specialize it:

		//C++
		typedef int int32;
		
		//Bea
		type int32 castfrom int

In the C++ code, int32 will resolve to 'int' and the generated bea::Convert<int32> specialization will fail to compile, because it basically means bea::Convert<int>.
typedef'd types must be entered simply as 

		type int32
		
which tells the bea compiler that no conversion is necessary for int32 and that Convert<int32> will compile.
	
castfrom @manual
================

@manual directive means "generate conversions, but don't implement them", eg:

		type MyType castfrom @manual
	
Type members
============

If the type has members, then it is assumed that they will be passed 'Object' from Javascript. 
Members are defined similar to C++ types:

		Type membername
	
It is assumed that Type.member is a valid C++ accessor and Bea will generate the code to convert all members to their respective acccessors in the Type variable:
	
		namespace cv
			type Point
				int x
				int y
				
Will generate the following C++ code:
	
		template<> struct Convert<cv::Point> {
			static bool Is(v8::Handle<v8::Value> v) {
				return !v.IsEmpty() && v->IsObject();
			}
			static cv::Point FromJS(v8::Handle<v8::Value> v, int nArg) {
				const char* msg = "Object with the following properties expected: x, y. This will be cast to 'cv::Point'";
				if (!Is(v)) THROW();
				v8::HandleScope scope;
				v8::Local<v8::Object> obj = v->ToObject();
				cv::Point ret;
				ret.x = Convert<int>::FromJS(obj->Get(v8::String::NewSymbol("x")), nArg);
				ret.y = Convert<int>::FromJS(obj->Get(v8::String::NewSymbol("y")), nArg);
				return ret;
			}
			static v8::Handle<v8::Value> ToJS(cv::Point const& v) {
				v8::HandleScope scope;
				Local<Object> obj = v8::Object::New();
				obj->Set(v8::String::NewSymbol("x"), Convert<int>::ToJS(v.x));
				obj->Set(v8::String::NewSymbol("y"), Convert<int>::ToJS(v.y));
				return scope.Close(obj);
			}
		
		};
		
This can be called from Javascript:

		//Javascript
		MyClass.processPoint({x: 100, y: 50}); 
	
	

@postAllocator
==============

	<C++ code>
	
This directive lets you enter C++ code which will execute after your object has been allocated and wrapped into the javascript prototype object.
This is guranteed to be the first method called after __constructor and before returning the new object to Javascript.
It will generate 'v8::Handle<v8::Value> __postAllocator(const v8::Arguments& args)'. 
Refer to your object's 'this' through the generator-inserted '_this' variable in the @postAllocator code.
You will also use @postAllocator to make your object indexable (eg. accessible like object[index] from Javascript). Use
	
		args.This()->SetIndexedPropertiesToExternalArrayData(_this->yourPointer, kExternalUnsignedByteArray, _this->yourPointerSize);
	
Although optional, it is strongly adviced that you define the post allocator for every object and at minimum call the V8::AdjustAmountOfExternalAllocatedMemory() with the 
right values.
Example:

		@postAllocator
				int bytes = _this->dataend - _this->datastart;
				args.This()->SetIndexedPropertiesToExternalArrayData(_this->datastart, kExternalUnsignedByteArray, bytes);	//Make this object indexable
				V8::AdjustAmountOfExternalAllocatedMemory(sizeof(*_this) + bytes);	//Tell the garbage collector the amount of external memory in use
	
