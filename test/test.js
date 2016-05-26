function applyLambdaFromCode(code, args) {
  var lambda = aoscript.eval(code);
  return aoscript.applyFunction(lambda, args);
}

QUnit.test("arithmetic operations", function(assert) {
  assert.deepEqual(aoscript.eval("1 + 2"), aoscript.obj2ao(3));
  assert.deepEqual(aoscript.eval("1 - 2"), aoscript.obj2ao(-1));
  assert.deepEqual(aoscript.eval("4 * 2"), aoscript.obj2ao(8));
  assert.deepEqual(aoscript.eval("5 % 3"), aoscript.obj2ao(2));
  assert.deepEqual(aoscript.eval("1 + 2 + 3"), aoscript.obj2ao(6));
  assert.deepEqual(aoscript.eval("1 * 2 + 3 * 4"), aoscript.obj2ao(14));
  assert.deepEqual(aoscript.eval("-1"), aoscript.obj2ao(-1));

  assert.deepEqual(
    applyLambdaFromCode("Int fun() {\n\
      val x = 1\n\
      val y = 2\n\
      x + y\n\
    }", []),
    aoscript.obj2ao(3));

  assert.deepEqual(
    applyLambdaFromCode("Int fun() {\n\
      val x = 1\n\
      -x\n\
    }", []),
    aoscript.obj2ao(-1));
});

QUnit.test("function(no arguments)", function(assert) {
  assert.deepEqual(
    applyLambdaFromCode("Int fun() { 1 }", []),
    aoscript.obj2ao(1));
});

QUnit.test("pattern match(Cons)", function(assert) {
  var code = "\n\
Int fun([Int] list) {\n\
  match (list) {\n\
    Cons(x, xs) -> x\n\
    [] -> 0\n\
  }\n\
}";

  assert.deepEqual(
    applyLambdaFromCode(code, [aoscript.Cons.fromObject([1, 2, 3])]),
    aoscript.obj2ao(1));
});

QUnit.test("pattern match(Tuple)", function(assert) {
  var code = "\n\
Int fun((Int, Int) pair) {\n\
  match(pair) {\n\
    (x, y) -> x\n\
  }\n\
}\n\
";

  assert.deepEqual(
    applyLambdaFromCode(code, [aoscript.Tuple.fromObject([1, 2])]),
    aoscript.obj2ao(1));
});

QUnit.test("pattern match(Custom Type)", function(assert) {
  var code = "\n\
Int fun() {\n\
  val a = Just(1)\n\
  match(a) {\n\
    Just(v) -> v\n\
    Nothing() -> 999\n\
  }\n\
}\n\
";

  assert.deepEqual(
    applyLambdaFromCode(code, []),
    aoscript.obj2ao(1));
});

QUnit.test("high order function", function(assert) {
  var code = "\n\
val map = [Int] fun([Int] list, (Int -> Int) f) {\n\
  match(list) {\n\
    Cons(x, xs) -> Cons(f(x), map(xs, f))\n\
    [] -> []\n\
  }\n\
}\n\
[Int] fun([Int] list) { map(list, Int fun(Int n) { n * 2 }) }\n\
";

  assert.deepEqual(
    applyLambdaFromCode(code, [aoscript.Cons.fromObject([1, 2, 3])]),
    aoscript.Cons.fromObject([2, 4, 6]));
});
