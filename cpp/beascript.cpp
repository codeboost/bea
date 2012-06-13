#include "beascript.h"
#include <sstream>
#include <iostream>
#include <boost/filesystem/path.hpp>
#include <boost/filesystem/operations.hpp>
#include <v8.h>
#include <v8-debug.h>

using namespace v8;
namespace bea{
	
	logCallback BeaContext::m_logger = NULL; 
	yieldCallback BeaContext::m_yielder = NULL;
	std::vector<std::string> BeaContext::cmdLine;

	std::string Global::scriptDir = std::string();
	reportExceptionCb Global::reportException = _BeaScript::reportError; 
	Persistent<v8::ObjectTemplate> Global::externalTemplate;
	Persistent<v8::ObjectTemplate> BeaContext::globalTemplate;
	Persistent<v8::Object> BeaContext::globalSandbox;

	// Reads a file into a v8 string.
	v8::Handle<v8::String> ReadFile(const char* name) {
		FILE* file = fopen(name, "rb");
		if (file == NULL) return v8::Handle<v8::String>();

		fseek(file, 0, SEEK_END);
		int size = ftell(file);
		rewind(file);

		char* chars = new char[size + 1];
		chars[size] = '\0';
		for (int i = 0; i < size;) {
			int read = (int) fread(&chars[i], 1, size - i, file);
			i += read;
		}
		fclose(file);
		v8::Handle<v8::String> result = v8::String::New(chars, size);
		delete[] chars;
		return result;
	}

	//Logs a message to the console
	static v8::Handle<v8::Value> Log(const Arguments& args) {
		if (args.Length() < 1) return v8::Undefined();
		HandleScope scope;
		v8::Handle<v8::Value> arg = args[0];
		v8::String::Utf8Value value(arg);
		//printf("Logged: %s\n", *value);
		std::cout << "Logged: " << *value << std::endl;
		return v8::Undefined();
	}

	//////////////////////////////////////////////////////////////////////////

	std::string BeaContext::lastError; 
	boost::filesystem::path _BeaScript::scriptPath;

	
	std::string toString(v8::Handle<v8::Value> v){
		return bea::Convert<std::string>::FromJS(v->ToString(), 0); 
	}

	v8::Handle<v8::Object> createModule(const std::string &fileName){

		v8::HandleScope scope; 
		v8::Local<v8::Object> obj = v8::Object::New();
		v8::Handle<v8::String> strFileName = Convert<std::string>::ToJS(fileName)->ToString();
		
		obj->Set(v8::String::New("id"), strFileName);
		obj->Set(v8::String::New("filename"), strFileName);
		obj->Set(v8::String::NewSymbol("exports"), v8::Object::New());
		return scope.Close(obj);
	}

	v8::Handle<v8::Value> _BeaScript::enumProperties(const v8::Arguments& args){

		HandleScope scope; 
		
		Local<Object> obj = args[0]->ToObject();
		v8::Local<v8::Array> keys = obj->GetPropertyNames();

		for (uint32_t i = 0; i < keys->Length(); i++) {
			v8::Handle<v8::String> key = keys->Get(i)->ToString();
			v8::Handle<v8::Value> value = obj->Get(key);
			std::cout << toString(key) << " : " << toString(value) << std::endl;
		}
		return args.This(); 
	}

	void CloneObject(Handle<Object> src, Handle<Object> dest){

		HandleScope scope; 
		v8::Local<v8::Array> keys = src->GetPropertyNames();
		TryCatch try_catch; 
		int ignored = 0; 
		for (uint32_t i = 0; i < keys->Length(); i++) {
			v8::Handle<v8::String> key = keys->Get(i)->ToString();
			if (key->Length() > 0){
				v8::Handle<v8::Value> value = src->Get(key);
				dest->Set(key, value);
			} 
		}
	}


	v8::Handle<v8::Value> _BeaScript::loadScriptSource(const std::string &fileName){

		boost::filesystem::path parentPath = scriptPath.parent_path();

		//v8::String::Utf8Value fileName(args[i]);
		//std::string fileName = bea::Convert<std::string>::FromJS(args[0], 0);

		//Add the script path to it
		boost::filesystem::path absolutePath = parentPath / fileName; 

		if (!absolutePath.has_extension() && !boost::filesystem::exists(absolutePath))
			absolutePath.replace_extension(".js");

		HandleScope scope; 
		v8::Local<v8::Value> result;
		v8::Handle<v8::String> source;

		if (boost::filesystem::exists(absolutePath))
			source = ReadFile(absolutePath.string().c_str());

		if (source.IsEmpty()){
			std::stringstream s;
			s << "Could not include file " << absolutePath.string();
			return v8::ThrowException(v8::Exception::Error(v8::String::New(s.str().c_str())));
		}
		return scope.Close(source); 
	}


	//Include a script file into current context
	//Raise javascript exception if load failed 
	v8::Handle<v8::Value> _BeaScript::include( const Arguments& args )
	{
		HandleScope scope; 
		

		v8::Handle<v8::String> source = ReadFile(*v8::String::Utf8Value(args[0]));

		if (source.IsEmpty())
			return v8::Null();

		v8::Handle<v8::Value> result = v8::Null();

		v8::Handle<v8::Context> context = v8::Context::GetCalling();
		v8::Handle<v8::Context> moduleContext = v8::Context::New(NULL, v8::ObjectTemplate::New());
		moduleContext->SetSecurityToken(context->GetSecurityToken());
		v8::Context::Scope context_scope(moduleContext);
		v8::TryCatch try_catch;
		v8::Handle<v8::Script> script = v8::Script::New(source, args[0]->ToString());

		if (script.IsEmpty()){
			reportError(try_catch);
		}
		else {

			CloneObject(globalSandbox, moduleContext->Global());
			CloneObject(args[1]->ToObject(), moduleContext->Global());

			result = script->Run();

			if (try_catch.HasCaught() || result.IsEmpty()) {
				reportError(try_catch);
			}
			else {
				//Copy everything back to the mod object
				Handle<Value> mod = moduleContext->Global()->Get(v8::String::New("module"));
				if (!mod.IsEmpty() && mod->IsObject()){
					CloneObject(mod->ToObject(), args[1]->ToObject()); 
				}
			}
		}
		return result;
	}
	
	//Execute a string of script
	v8::Handle<v8::Value> _BeaScript::execute( v8::Handle<v8::String> script, v8::Handle<v8::String> fileName )
	{
		HandleScope scope;
		TryCatch try_catch;
		v8::Handle<v8::Value> result; 

		// Compile the script and check for errors.
		v8::Handle<v8::Script> compiled_script = v8::Script::Compile(script, fileName);
		if (compiled_script.IsEmpty()) {
			reportError(try_catch);
			return result;
		}

		// Run the script!
		result = compiled_script->Run();

		if (result.IsEmpty()) {
			reportError(try_catch);
			return result;
		}

		return scope.Close(result);
	}

	//Report the error from an exception, store it in lastError
	void BeaContext::reportError(TryCatch& try_catch){
		lastError = *v8::String::Utf8Value(try_catch.Exception());
		if (m_logger)
			m_logger(*v8::String::Utf8Value(try_catch.StackTrace()));
	}

	v8::Handle<v8::Value> _BeaScript::executeScript(const char* fileName){

		scriptPath = boost::filesystem::system_complete(fileName);

		Global::scriptDir = scriptPath.parent_path().string();

		Context::Scope context_scope(m_context);

		HandleScope scope;
		v8::Handle<v8::String> str = ReadFile(fileName);

		v8::Handle<v8::Value> v;

		if (!str.IsEmpty()){
			v = execute(str, bea::Convert<std::string>::ToJS(fileName)->ToString());
		}

		return scope.Close(v);
	}

	//Initialize the javascript context and load a script file into it
	bool _BeaScript::loadScript( const char* fileName )
	{
		v8::Locker locker; 
		if (!init())
			return false; 

	
		HandleScope scope; 
		Handle<Value> v = executeScript(fileName);

		return !v.IsEmpty();
	}


	v8::Handle<v8::ObjectTemplate> _BeaScript::createGlobal(){
		
		v8::Handle<v8::ObjectTemplate> global = v8::ObjectTemplate::New();
		global->Set(v8::String::New("loadCommonJSModule"), v8::FunctionTemplate::New(include));
		global->Set(v8::String::New("log"), v8::FunctionTemplate::New(Log));
		global->Set(v8::String::New("yield"), v8::FunctionTemplate::New(yield));
		global->Set(v8::String::New("collectGarbage"), v8::FunctionTemplate::New(collectGarbage));
		return global;
	}

	//Initialize the javascript context and expose the methods in exposer
	bool _BeaScript::init()
	{
		
		lastError = "";
		HandleScope handle_scope;

		if (globalTemplate.IsEmpty()){
			globalTemplate = v8::Persistent<v8::ObjectTemplate>::New(createGlobal());
		}
		
		//Create the context
		m_context = v8::Context::New(NULL, globalTemplate);

		Context::Scope context_scope(m_context);

		globalSandbox = v8::Persistent<v8::Object>::New(v8::Object::New()); 

		Handle<Value> vCmdLine = bea::Convert<std::vector<std::string> >::ToJS(cmdLine);

		Handle<Object> objProcess = v8::Object::New();
		objProcess->Set(v8::String::New("argv"), vCmdLine);

		m_context->Global()->Set(v8::String::New("process"), objProcess);
		
		expose();

		executeScript("./lib/loader.js");
		CloneObject(m_context->Global(), globalSandbox);


		return true; 
	}

	v8::Handle<v8::Value> _BeaScript::collectGarbage( const v8::Arguments& args ){

		while (!V8::IdleNotification()) {}
		return args.This();
	}

	v8::Handle<v8::Value> _BeaScript::yield( const v8::Arguments& args )
	{
		{
			int timeToYield = bea::Optional<int>::FromJS(args, 0, 10); 

			v8::Unlocker unlocker;

			if (m_yielder)
				m_yielder(timeToYield);

			//Cleanup garbage
			//while (!V8::IdleNotification()) {}		

		}
		return args.This();
	}


	//Call a javascript function, store the found function in a local cache for faster access
	v8::Handle<v8::Value> BeaContext::call(const char *fnName, int argc, v8::Handle<v8::Value> argv[]){
		
		HandleScope scope;
		Context::Scope context_scope(m_context);

		//Lookup function in cache
		JFunction fn;
		CacheMap::iterator iter = m_fnCached.find(std::string(fnName));

		if (iter != m_fnCached.end())
			fn = iter->second;
		else {
			//Lookup function in the script 
			v8::Handle<v8::Value> fnv = m_context->Global()->Get(v8::String::New(fnName));

			if (!fnv->IsFunction()) {
				std::stringstream strstr;
				strstr << "Error: " << fnName << " is not a function";
				lastError = strstr.str();
				return v8::False();
			} else {

				//Store found function in our cache
				fn = Persistent<Function>::New(v8::Handle<Function>::Cast(fnv));
				m_fnCached[std::string(fnName)] = fn;
			}
		}

		//Call the function
		TryCatch try_catch;
		v8::Handle<v8::Value> result = fn->Call(m_context->Global(), argc, argv);

		if (result.IsEmpty())
			reportError(try_catch);

		return scope.Close(result);
	}


	BeaContext::BeaContext()
	{

	}

	BeaContext::~BeaContext()
	{
		for (CacheMap::iterator iter = m_fnCached.begin(); iter!= m_fnCached.end(); iter++){
			iter->second.Dispose();
		}

		m_fnCached.empty();
		m_context.Dispose();
	}

	bool BeaContext::exposeGlobal( const char* name, v8::InvocationCallback cb )
	{
		return BEA_SET_METHOD(m_context->Global(), name, cb);
	}

	bool BeaContext::exposeToObject( const char* targetName, const char* exposedName, v8::Handle<v8::Value> what )
	{
		HandleScope scope; 
		v8::Handle<v8::Value> jc = m_context->Global()->Get(v8::String::New(targetName));
		if (!jc.IsEmpty() && jc->IsObject()){
			v8::Handle<Object> obj = jc->ToObject();
			return obj->Set(v8::String::New(exposedName), what);
		}
		return false; 
	}
}	//namespace bea