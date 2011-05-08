(function() {
  var mustThrow, ok, test;
  ok = function(expr, msg, actual) {
    if (expr) {
      return console.log("PASSED: " + msg);
    } else {
      if (!actual) {
        return console.log("FAILED: " + msg);
      } else {
        return console.log("FAILED: " + msg + "; Actual value = " + actual);
      }
    }
  };
  test = function(name, fnTest) {
    console.log("*****");
    console.log(name);
    try {
      return fnTest();
    } catch (e) {
      return ok(false, "Exception thrown for '" + name + "': " + e.message);
    }
  };
  mustThrow = function(name, fn) {
    var excepted;
    excepted = false;
    try {
      fn();
    } catch (e) {
      excepted = true;
    }
    if (!excepted) {
      return ok(false, "Exception not thrown for '" + name + "'");
    } else {
      return ok(true, "Exception thrown for '" + name);
    }
  };
  exports.ok = ok;
  exports.test = test;
  exports.mustThrow = mustThrow;
}).call(this);
