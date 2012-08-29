// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Dart test program for testing basic boolean properties.
// @static-clean

class BoolTest {
  static void testEquality() {
    Expect.equals(true, true);
    Expect.equals(false, false);
    Expect.equals(true, true === true);
    Expect.equals(false, true === false);
    Expect.equals(true, false === false);
    Expect.equals(false, false === true);
    Expect.equals(false, true !== true);
    Expect.equals(true, true !== false);
    Expect.equals(false, false !== false);
    Expect.equals(true, false !== true);
    Expect.equals(true, true == true);
    Expect.equals(false, true == false);
    Expect.equals(true, false == false);
    Expect.equals(false, false == true);
    Expect.equals(false, true != true);
    Expect.equals(true, true != false);
    Expect.equals(false, false != false);
    Expect.equals(true, false != true);
    Expect.equals(true, true === (true == true));
    Expect.equals(true, false === (true == false));
    Expect.equals(true, true === (false == false));
    Expect.equals(true, false === (false == true));
    Expect.equals(false, true !== (true == true));
    Expect.equals(false, false !== (true == false));
    Expect.equals(false, true !== (false == false));
    Expect.equals(false, false !== (false == true));
    Expect.equals(false, false === (true == true));
    Expect.equals(false, true === (true == false));
    Expect.equals(false, false === (false == false));
    Expect.equals(false, true === (false == true));
    Expect.equals(true, false !== (true == true));
    Expect.equals(true, true !== (true == false));
    Expect.equals(true, false !== (false == false));
    Expect.equals(true, true !== (false == true));
    // Expect.equals could rely on a broken boolean equality.
    if (true == false) {
      throw "Expect.equals broken";
    }
    if (false == true) {
      throw "Expect.equals broken";
    }
    if (true === false) {
      throw "Expect.equals broken";
    }
    if (false === true) {
      throw "Expect.equals broken";
    }
    if (true == true) {
    } else {
      throw "Expect.equals broken";
    }
    if (false == false) {
    } else {
      throw "Expect.equals broken";
    }
    if (true === true) {
    } else {
      throw "Expect.equals broken";
    }
    if (false === false) {
    } else {
      throw "Expect.equals broken";
    }
    if (true != false) {
    } else {
      throw "Expect.equals broken";
    }
    if (false != true) {
    } else {
      throw "Expect.equals broken";
    }
    if (true !== false) {
    } else {
      throw "Expect.equals broken";
    }
    if (false !== true) {
    } else {
      throw "Expect.equals broken";
    }
    if (true != true) {
      throw "Expect.equals broken";
    }
    if (false != false) {
      throw "Expect.equals broken";
    }
    if (true !== true) {
      throw "Expect.equals broken";
    }
    if (false !== false) {
      throw "Expect.equals broken";
    }
  }

  static void testToString() {
    Expect.equals("true", true.toString());
    Expect.equals("false", false.toString());
  }

  static void testNegate(isTrue, isFalse) {
    Expect.equals(true, !false);
    Expect.equals(false, !true);
    Expect.equals(true, !isFalse);
    Expect.equals(false, !isTrue);
  }

  static void testLogicalOp() {
    testOr(a, b, onTypeError) {
      try {
        return a || b;
      } on TypeError catch (t) {
        return onTypeError;
      }
    }
    testAnd(a, b, onTypeError) {
      try {
        return a && b;
      } on TypeError catch (t) {
        return onTypeError;
      }
    }

    var isTrue = true;
    var isFalse = false;
    Expect.equals(true, testAnd(isTrue, isTrue, false));
    Expect.equals(false, testAnd(isTrue, 0, false));
    Expect.equals(false, testAnd(isTrue, 1, false));
    Expect.equals(false, testAnd(isTrue, "true", false));
    Expect.equals(false, testAnd(0, isTrue, false));
    Expect.equals(false, testAnd(1, isTrue, false));

    Expect.equals(true, testOr(isTrue, isTrue, false));
    Expect.equals(true, testOr(isFalse, isTrue, false));
    Expect.equals(true, testOr(isTrue, isFalse, false));
    Expect.equals(true, testOr(isTrue, 0, true));
    Expect.equals(true, testOr(isTrue, 1, true));
    Expect.equals(false, testOr(isFalse, 0, false));
    Expect.equals(false, testOr(isFalse, 1, false));
    Expect.equals(true, testOr(0, isTrue, true));
    Expect.equals(true, testOr(1, isTrue, true));
    Expect.equals(false, testOr(0, isFalse, false));
    Expect.equals(false, testOr(1, isFalse, false));
    
    // Test side effects.
    int trueCount = 0, falseCount = 0;
      
    trueFunc() {
      trueCount++;
      return true;
    }
    
    falseFunc() {
      falseCount++;
      return false;
    }

    Expect.equals(0, trueCount);
    Expect.equals(0, falseCount);
  
    trueFunc() && trueFunc();
    Expect.equals(2, trueCount);
    Expect.equals(0, falseCount);

    trueCount = falseCount = 0;
    falseFunc() && trueFunc();
    Expect.equals(0, trueCount);
    Expect.equals(1, falseCount);

    trueCount = falseCount = 0;
    trueFunc() && falseFunc();
    Expect.equals(1, trueCount);
    Expect.equals(1, falseCount);

    trueCount = falseCount = 0;
    falseFunc() && falseFunc();
    Expect.equals(0, trueCount);
    Expect.equals(1, falseCount);
    
    trueCount = falseCount = 0;
    trueFunc() || trueFunc();
    Expect.equals(1, trueCount);
    Expect.equals(0, falseCount);

    trueCount = falseCount = 0;
    falseFunc() || trueFunc();
    Expect.equals(1, trueCount);
    Expect.equals(1, falseCount);

    trueCount = falseCount = 0;
    trueFunc() || falseFunc();
    Expect.equals(1, trueCount);
    Expect.equals(0, falseCount);

    trueCount = falseCount = 0;
    falseFunc() || falseFunc();
    Expect.equals(0, trueCount);
    Expect.equals(2, falseCount);
  }
  

  static void testMain() {
    testEquality();
    testNegate(true, false);
    testToString();
    testLogicalOp();
  }
}

main() {
  BoolTest.testMain();
}
