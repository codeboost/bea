#include <bea.h>
#include "helloJS.h"
namespace bea {
	template<> struct Convert<helloJS::_D_Item*> {
		static bool Is(v8::Handle<v8::Value> v) {
			return bea::ExposedClass<helloJS::_D_Item>::Is(v);
		}
		
		static helloJS::_D_Item* FromJS(v8::Handle<v8::Value> v, int nArg) {
			return bea::ExposedClass<helloJS::_D_Item>::FromJS(v, nArg);
		}
		
		static v8::Handle<v8::Value> ToJS(helloJS::_D_Item* const& v) {
			return bea::ExposedClass<helloJS::_D_Item>::ToJS(v);
		}
		
	};
	
	template<> struct Convert<hello::Item*> {
		static bool Is(v8::Handle<v8::Value> v) {
			return bea::Convert<helloJS::_D_Item*>::Is(v);
		}
		
		static hello::Item* FromJS(v8::Handle<v8::Value> v, int nArg) {
			return bea::Convert<helloJS::_D_Item*>::FromJS(v, nArg);
		}
		
		static v8::Handle<v8::Value> ToJS(hello::Item* const& v) {
			return bea::Convert<helloJS::_D_Item*>::ToJS(static_cast<helloJS::_D_Item*>(v));
		}
		
	};
	
}

DECLARE_EXPOSED_CLASS(helloJS::_D_Item);
namespace helloJS {
	void JItem::__destructor(v8::Handle<v8::Value> value) {
		DESTRUCTOR_BEGIN();
		helloJS::_D_Item* _this = bea::Convert<helloJS::_D_Item*>::FromJS(value, 0);
		delete _this;
		DESTRUCTOR_END();
	}
	
	v8::Handle<v8::Value> JItem::__constructor(const v8::Arguments& args) {
		METHOD_BEGIN(0);
		//Item(const std::string& name, int age)
		if (bea::Convert<std::string>::Is(args[0]) && bea::Convert<int>::Is(args[1])) {
			std::string name = bea::Convert<std::string>::FromJS(args[0], 0);
			int age = bea::Convert<int>::FromJS(args[1], 1);
			hello::Item* fnRetVal = new helloJS::_D_Item(name, age);
			return v8::External::New(fnRetVal);
		}
		//Item(const char* name)
		if (bea::Convert<bea::string>::Is(args[0])) {
			bea::string name = bea::Convert<bea::string>::FromJS(args[0], 0);
			hello::Item* fnRetVal = new helloJS::_D_Item(name);
			return v8::External::New(fnRetVal);
		}
		//Item()
		if (args.Length() == 0) {
			hello::Item* fnRetVal = new helloJS::_D_Item();
			return v8::External::New(fnRetVal);
		}
		return v8::ThrowException(v8::Exception::Error(v8::String::New(("Could not determine overload from supplied arguments"))));
		METHOD_END();
	}
	
	v8::Handle<v8::Value> JItem::name(const v8::Arguments& args) {
		METHOD_BEGIN(0);
		//std::string name()
		helloJS::_D_Item* _this = bea::Convert<helloJS::_D_Item*>::FromJS(args.This(), 0);
		std::string fnRetVal = _this->name();
		return bea::Convert<std::string>::ToJS(fnRetVal);
		METHOD_END();
	}
	
	v8::Handle<v8::Value> JItem::sayHello(const v8::Arguments& args) {
		METHOD_BEGIN(1);
		//std::string sayHello(const std::string &message)
		std::string message = bea::Convert<std::string>::FromJS(args[0], 0);
		helloJS::_D_Item* _this = bea::Convert<helloJS::_D_Item*>::FromJS(args.This(), 0);
		std::string fnRetVal = _this->sayHello(message);
		return bea::Convert<std::string>::ToJS(fnRetVal);
		METHOD_END();
	}
	
	v8::Handle<v8::Value> JItem::greet(const v8::Arguments& args) {
		METHOD_BEGIN(0);
		//virtual std::string greet()
		helloJS::_D_Item* _this = bea::Convert<helloJS::_D_Item*>::FromJS(args.This(), 0);
		std::string fnRetVal = _this->greet();
		return bea::Convert<std::string>::ToJS(fnRetVal);
		METHOD_END();
	}
	
	v8::Handle<v8::Value> JItem::__postAllocator(const v8::Arguments& args) {
		METHOD_BEGIN(0);
		//void __postAllocator()
		helloJS::_D_Item* _this = bea::Convert<helloJS::_D_Item*>::FromJS(args.This(), 0);
		_this->bea_derived_setInstance(args.This());
		return args.This();
		METHOD_END();
	}
	
	void JItem::_InitJSObject(v8::Handle<v8::Object> target) {
		bea::ExposedClass<helloJS::_D_Item>* obj = EXPOSE_CLASS(helloJS::_D_Item, "Item");
		//Destructor
		obj->setDestructor(__destructor);
		//Exposed Methods
		obj->setConstructor(__constructor);
		obj->exposeMethod("name", name);
		obj->exposeMethod("sayHello", sayHello);
		obj->exposeMethod("greet", greet);
		obj->setPostAllocator(__postAllocator);
		//Accessors
		//Expose object to the Javascript
		obj->exposeTo(target);
	}
	
	std::string _D_Item::greet() {
		v8::Locker v8locker;
		v8::HandleScope v8scope; v8::Handle<v8::Value> v8retVal;
		if (bea_derived_hasOverride("greet")) {
			v8::Handle<v8::Value> v8args[1];
			v8retVal = bea_derived_callJS("greet", 0, v8args);
		}
		if (v8retVal.IsEmpty()) return _d_greet();
		return bea::Convert<std::string>::FromJS(v8retVal, 0);
	}
	
}

namespace helloJS {
	void Project::expose(v8::Handle<v8::Object> target) {
		JItem::_InitJSObject(target);
	}
	
}
