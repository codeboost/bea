#ifndef __BEASCRIPT_H__
#define __BEASCRIPT_H__

#include "bea.h"
#include <boost/filesystem/path.hpp>
#include <v8.h>

namespace bea{

	//Thin wrapper around a v8 context
	//Allows calling functions, holds a map of cached js functions
	//Context can be re-assigned (v8::Persistent<> is ref-counted)
	typedef void (*logCallback)(const char* msg);
	typedef void (*yieldCallback)(int timeout);
	class BeaContext{

	public:
		static std::string lastError;
		static logCallback	m_logger;
		static yieldCallback m_yielder;
		static std::vector<std::string> cmdLine; 
		static v8::Persistent<v8::ObjectTemplate> globalTemplate; 
		static v8::Persistent<v8::Object> globalSandbox;
		
	protected:
		//Context in which the script will run
		v8::Persistent<v8::Context> m_context;
		typedef v8::Persistent<v8::Function> JFunction;
		typedef std::map<std::string, JFunction> CacheMap;
		//Cached javascript functions
		CacheMap m_fnCached;
		//Report the error from an exception, store it in lastError
		
		BeaContext();
	public:
		virtual ~BeaContext();
		//Call a function in Javascript
		v8::Handle<v8::Value> call(const char* fnName, int argc, v8::Handle<v8::Value> argv[]);

		bool exposeGlobal(const char* name, v8::InvocationCallback cb);
		static void reportError(v8::TryCatch& try_catch);

		//Lookup targetName in the global context and add a new value to it (what) with the name exposedName.
		//Eg. ctx->exposeToObject("window", "options", myoptions); //window.options is now accessible from Javascript
		
		bool exposeToObject(const char* tagetName, const char* exposedName, v8::Handle<v8::Value> what);

		//Current script context
		inline v8::Persistent<v8::Context> context(){
			return m_context;
		}

		std::string getLastError() {
			return lastError;
		}

		static void setLogCallback(logCallback cb){
			m_logger = cb;
		}

		static void setYieldCallback(yieldCallback cb){
			m_yielder = cb;
		}

		static void setCommandLine(int argc, char** argv){
			for (int k = 0; k < argc; k++){
				cmdLine.push_back(std::string(argv[k]));
			}
		}
	};

	//Helper class to run a javascript script
	class _BeaScript : public BeaContext{
		static boost::filesystem::path scriptPath; 
	protected:
		//Invocation callback for the 'require' javascript function
		static v8::Handle<v8::Value> loadScriptSource(const std::string& fileName);
		static v8::Handle<v8::Value> include(const v8::Arguments& args);
		static v8::Handle<v8::Value> enumProperties(const v8::Arguments& args);
		static v8::Handle<v8::ObjectTemplate> createGlobal();
		
		//Execute a string of javascript
		static v8::Handle<v8::Value> execute(v8::Handle<v8::String> script, v8::Handle<v8::String> fileName);
		
		static v8::Handle<v8::Value> yield(const v8::Arguments& args);
		static v8::Handle<v8::Value> collectGarbage(const v8::Arguments& args);

		virtual void expose() {}
		v8::Handle<v8::Value> executeScript(const char* fileName);
		//Init the script context and expose the objects offered by IBeaExposer
		bool init();

	public:
		inline _BeaScript(){

		}
		virtual ~_BeaScript(){

		}
		
		//Load, compile and execute a script 
		bool loadScript(const char* fileName);



	};

	template <class TExposer>
	class BeaScript : public _BeaScript{
	protected:
		void expose(){
			TExposer::expose(m_context->Global());
		}
	};

}


#endif //__BEASCRIPT_H__