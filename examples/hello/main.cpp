#include <iostream>
#include "../../cpp/beascript.h"
#include "helloJS.h"

using namespace std;

void printLog(const char* msg){
	std::cout << msg << std::endl;
}

std::string hello::Item::className(){
	return "Item";
}



class ScriptController : public bea::BeaScript<helloJS::Project>{

};

int main(int argc, char** argv){


	ScriptController script; 
	bea::BeaContext::m_logger = printLog; 

	if (argc < 2){
		std::cout << "Please give me a js file" << std::endl;
		return -1;
	}

	if (!script.loadScript(argv[1])){
		std::cout << "Error: " << ScriptController::lastError << std::endl;
		return -2; 
	}

	cout << "Finished" << endl;
	return 0;
}