(function() {
  var beautils, debugIt, fs, inspectType, utest, util, _;
  util = require('util');
  _ = require('underscore');
  fs = require('fs');
  beautils = require('./beautils').u;
  utest = require('./utest');
  debugIt = require('./debugIt').debugIt;
  inspectType = function(typeStr, ns) {
    var t;
    console.log('TypeStr: ' + typeStr + '; ns = ' + ns);
    t = new beautils.Type(typeStr, ns);
    console.log('Inspect: ' + util.inspect(t));
    console.log('Fulltype: ' + t.fullType());
    return console.log('-----------------');
  };
  utest.test('TypeTest', function() {
    var cvMat, testType;
    testType = function(type, ns, res) {
      var t;
      console.log("Type: " + type + "; namespace: " + ns);
      t = new beautils.Type(type, ns);
      return _.each(res, function(val, key) {
        if (key.indexOf('()') !== -1) {
          return utest.ok(t[key.replace('()', '')]() === val, "" + key + " == " + val, t[key.replace('()', '')]());
        } else {
          return utest.ok(t[key] === val, "" + key + " == " + val, t[key]);
        }
      });
    };
    testType("const Mat&", void 0, {
      type: 'Mat&',
      rawType: 'Mat',
      isPointer: false,
      isRef: true,
      isConst: true,
      'fullType()': 'Mat'
    });
    cvMat = {
      type: 'Mat',
      rawType: 'Mat',
      isPointer: false,
      isRef: false,
      isConst: false,
      'fullType()': 'cv::Mat'
    };
    testType("cv::Mat", void 0, cvMat);
    testType("cv::Mat", "cv", cvMat);
    testType("const Mat*", "cv", {
      type: 'Mat*',
      rawType: 'Mat',
      isPointer: true,
      isRef: false,
      isConst: true,
      'fullType()': 'cv::Mat'
    });
    testType("std::vector<cv::Mat*>", "cv", {
      type: "vector<cv::Mat*>",
      rawType: "vector<cv::Mat*>",
      isPointer: false,
      isRef: false,
      isConst: false,
      'fullType()': 'std::vector<cv::Mat*>'
    });
    return testType("std::vector<cv::Mat*>*", "cv", {
      type: "vector<cv::Mat*>*",
      rawType: "vector<cv::Mat*>",
      isPointer: true,
      isRef: false,
      isConst: false,
      'fullType()': 'std::vector<cv::Mat*>'
    });
  });
  /*		
  inspectType "const Mat&"
  inspectType "cv::Mat"
  inspectType "cv::Mat", "cv"
  inspectType "const Mat*", "cv"
  */
}).call(this);
