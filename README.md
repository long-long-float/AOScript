AOScript
====

AOScript is an simple functional language which has C-like syntax.

# Build

```
$ npm i
$ `npm bin`/gulp
```

## for browser

load `aoscript.js` in your html file.

## for Node.js

```js
var aoscript = require('./dist/aoscript.js');
```

# Run tests

```
$ npm test
```

# Usage

```js
// simple
aoscript.eval(code);

// using an environment
var env = new aoscript.Environment(null);
aoscript.eval(code, env);
var exitcode = aoscript.applyFunction(env.getValue('main!'), []).toObject();
```

# Sample

```scala
[Int] map([Int] list, (Int -> Int) f) {
  match(list) {
    [] -> []
    Cons(x, xs) -> Cons(f(x), map(xs, f))
  }
}

Int main!() {
  val list = [1, 2, 3]
  print!(list.map(Int fun(Int n){ n * 2 }))
  0
}
```
