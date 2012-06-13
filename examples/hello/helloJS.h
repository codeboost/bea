#ifndef HELLOJS_H
#define HELLOJS_H
#include <v8.h>
#include "hello.h"
namespace helloJS {
	class JItem {
		protected:
			//Destructor
			static void __destructor(v8::Handle<v8::Value> value);
			//Exported methods
			static v8::Handle<v8::Value> __constructor(const v8::Arguments& args);
			static v8::Handle<v8::Value> name(const v8::Arguments& args);
			static v8::Handle<v8::Value> sayHello(const v8::Arguments& args);
			static v8::Handle<v8::Value> greet(const v8::Arguments& args);
			static v8::Handle<v8::Value> __postAllocator(const v8::Arguments& args);
		public:
			static void _InitJSObject(v8::Handle<v8::Object> target);
	};
	
	class _D_Item : public hello::Item, public bea::DerivedClass {
		public:
			_D_Item() : hello::Item(){}
			_D_Item(const char* name) : hello::Item(name){}
			_D_Item(const std::string& name,  int age) : hello::Item(name, age){}
			//JS: These virtual functions will only be called from Javascript
			inline std::string _d_greet() {
				return hello::Item::greet();
			}
			
			//Native: These virtual functions will only be called from native code
			std::string greet();
	};
	
}

namespace helloJS {
	class Project {
		public:
			static void expose(v8::Handle<v8::Object> target);
	};
	
}

#endif //#ifndef HELLOJS_H