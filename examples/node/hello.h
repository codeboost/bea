#ifndef HELLO_H
#define HELLO_H

#include <iostream>

namespace hello{
	//This is a mock class which we'll expose to javascript

	class Item{
		std::string m_name;
		int m_age;
	public:
		//We can expose multiple constructor overloads
		Item(){
			m_name = "(no name)";
			m_age = 0; 
		}

		Item(const char* name): m_name(name){
			m_age = 0; 
		}

		Item(const std::string& name, int age): m_name(name), m_age(age){
		}

		virtual ~Item(){
			std::cout << "~Item()";
		}

		std::string name(){
			return m_name;
		}

		void setName(const std::string& name){
			m_name = name;
		}

		std::string sayHello(const std::string &message){
			//This calls a virtual function which can be overriden from Javascript
			//return m_name + greet() + message;
			return m_name + greet() + message;
		}

		//We can override functions in Javascript
		virtual std::string greet(){
			return " says hi: ";
		}


	};
}//namespace hello


#endif