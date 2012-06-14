Compiling on OSX:

0. Assume you cloned bea in ~/bea

1. Get and compile V8: https://developers.google.com/v8/build
After build completes, copy the v8 include files and the newly built libraries to the examples/hello/v8 folder:

	svn checkout http://v8.googlecode.com/svn/trunk/ v8
	cd v8
	make native
	..wait..
	cp -r include ~/bea/examples/hello/v8
	cp build/native/*.a ~/bea/examples/hello/v8

2. Install boost

	brew install -v boost 2>&1

3. Install scons

	brew install scons

4. To build, type:

	cd ~/bea
	scons

5. To run, type:
	
	./hello test.js

	
