{
  var RESERVED_WORDS =
    ["fun", "val", "if", "else", "match", "true", "false"];

  Array.prototype.flatten = function() {
    return Array.prototype.concat.apply([], this);
  }

  function loc() {
    return { line: line(), column: column() };
  }

  function value(type, val) {
    return { type: type, value: val, location: loc() };
  }

  function filterEmptyList(list) {
    if(Object.prototype.toString.call(list) != "[object Array]") return list;
    return list.filter(function(e) { return e.length != 0 && e[0] != " "; });
  }

  function flatAndFilter(values, excludes) {
    var ret = values.flatten()
                    .filter(function(v) { return excludes.indexOf(v) === -1; })
                    .filter(function(v) { return v !== null });
    return filterEmptyList(ret);
  }

  function makeSet(first, rest, type) {
    var set = flatAndFilter([first].concat(rest), [",", null]);
    return value(type, set);
  }

  function makeList(first, rest) {
    return makeSet(first, rest, "List");
  }

  function makeTuple(first, rest) {
    return makeSet(first, rest, "Tuple");
  }

  function makeBinaryOp(left, rest) {
    var rest2 = flatAndFilter([left].concat(rest), []);
    var makeBiOp_ = function(nodes) {
      var right = nodes.pop();
      var op    = nodes.pop();
      var left;
      if (nodes.length == 1) {
        left = nodes[0];
      }
      else {
        left = makeBiOp_(nodes);
      }
      return { type: "BinaryOperation", left: left, op: op, right: right, location: loc() };
    }
    return makeBiOp_(rest2)
  }

  function makeUnaryOp(op, val) {
    return { type: "UnaryOperation", op: op, val: val };
  }

  function makeLambda(outType, firstArg, restArgs, block) {
    var args = null;
    if(firstArg != null) {
      args = [firstArg].concat(filterEmptyList(restArgs))
                       .map(filterEmptyList)
                       .map(function(arg) {
                           return arg.filter(function(a) {
                               return a != ',';
                             });
                           });
    } else {
      args = []
    }
    return { type: "Lambda", outType: outType, args: args, block: block, location: loc() };
  }

  function makeApplyFunction(name, firstArg, restArgs) {
    var args = flatAndFilter([firstArg].concat(restArgs), [","])
    return { type: "ApplyFunction", name: name, args: args, location: loc() };
  }

  function makeIdentifier(name, destructive) {
    if(destructive) {
      name += '!';
    }
    return {
      type: "Identifier",
      value: name,
      destructive: destructive == '!',
      location: loc()
    };
  }

  function makePatternMatch(value, patterns) {
    var pat = patterns.map(filterEmptyList)
      .map(function(p) { return p.filter(function(e) { return e != "->" }) });
    return { type: "PatternMatch", value: value, patterns: pat, location: loc() };
  }

  function makeLambdaType(firstType, restTypes) {
    var types = flatAndFilter([firstType].concat(restTypes), ["->"])
    return { type: "Type", value: "Lambda", innerTypes: types, location: loc() };
  }

  function makeTupleType(firstType, restTypes) {
    var types = flatAndFilter([firstType].concat(restTypes), [","])
    return { type: "Type", value: "Tuple", innerTypes: types, location: loc() };
  }

  function makeType(type, innerTypes) {
    var itypes;
    if (innerTypes) {
      itypes = flatAndFilter(innerTypes, [",", "(", ")"]);
    }
    else {
      itypes = [];
    }
    return { type: "Type", value: type.flatten().join(""), innerTypes: itypes, location: loc() };
  }

  function convertMethodStyleApply(left, rest) {
    var res = flatAndFilter(rest, ["."]);
    res[0].args.unshift(left);
    while(res.length > 1) {
      res[1].args.unshift(res.shift());
    }
    return res[0];
  }

  function makeBind(type, id, expr) {
    return { type: "Bind", valType: type, valName: id, value: expr, location: loc() }
  }
}

program = block

block = _ nl? _ expr:expression _ exprs:(nl _ expression _)* _ nl? _
  { return flatAndFilter([expr].concat(exprs), []); }

expression = val:ope0 _ comment? { return filterEmptyList(val); }
           / comment

ope0
 = type:(type / "val") _ id:identifier _ "=" _ expr:ope01
  { return makeBind(type, id, expr) }
 / outType:type _ id:identifier _ "(" _ firstArg:(type _ identifier)? restArgs:(_ "," _ type _ identifier)* _ ")" _ "{" _ block:block _ "}"
  { return makeBind("val", id, makeLambda(outType, firstArg, restArgs, block)) }
 / ope01

ope01
 = left:ope1 rest:(_ ("<=" / ">=" / "<" / ">" / "==") _ ope1)+
  { return makeBinaryOp(left, rest) }
 / ope1

ope1
 = left:ope2 rest:(_ ("+" / "-" / "%") _ ope2)+ { return makeBinaryOp(left, rest) }
 / ope2

ope2
 = left:primary0 rest:(_ "*" _  primary0)+ { return makeBinaryOp(left, rest) }
 / primary0

primary0
 = left:unary rest:(_ "." _ applyFunction)+ { return convertMethodStyleApply(left, rest); }
 / unary

unary
 = op:("-" / "+") _ val:primary { return makeUnaryOp(op, val); }
 / primary

primary
 = "if" _ "(" _ condition:expression _ ")" _ "{" _ iftrue:block _ "}" _ nl? _
   "else" _ "{" _ ifelse:block _ "}"
    { return { type: "If", condition: condition, iftrue: iftrue, ifelse: ifelse } }
 / "match" _ "(" _ val:expression _ ")" _ "{" _ nl? _
    pattern:(expression _ "->" _ expression) _ patterns:(nl _ expression _ "->" _ expression _)* nl? _ "}"
    { return makePatternMatch(val, [pattern].concat(patterns)) }
 / applyFunction
 / value

 value
 = val:([0-9]+ "." [0-9]+) { return value("Float", parseFloat(val.flatten().join(""))) }
 / val:[0-9]+              { return value("Int", parseInt(val.join(""))) }
 / "'" val:. "'"           { return value("Char", val) }
 / "\"" val:[^"]* "\""     { return value("String", val.join("")) }
 / val:("true" / "false")  { return value("Boolean", val == "true") }
 / outType: type _ "fun" _ "(" _ firstArg:(type _ identifier)? restArgs:(_ "," _ type _ identifier)* _ ")" _ "{" _ block:block _ "}"
    { return makeLambda(outType, firstArg, restArgs, block) }
 / "[" _ expr:expression? exprs:(_ "," _ expression)* _ "]" { return makeList(expr, exprs) }
 / "(" _ expr:expression? exprs:(_ "," _ expression)* _ ")" { return makeTuple(expr, exprs); }
 / identifier

identifier
 = val:([a-zA-Z][a-zA-Z0-9]*) destructive:"!"?
  & { return RESERVED_WORDS.indexOf(val.flatten().join("")) === -1; }
  { return makeIdentifier(val.flatten().join(""), destructive) }

applyFunction
 = id:identifier _ "(" _ expr:expression? exprs:(_ "," _ expression)* _ ")"
  { return makeApplyFunction(id, expr, exprs) }

type
 = val:([A-Z][a-z]*) innerTypes:(_ "(" _ type (_ "," _ type)* ")" )?
    { return makeType(val, innerTypes) }
 / "(" _ ")"
    { return makeTupleType(null, []) }
 / "(" _ firstType:type restTypes:(_ "," _ type)* _ ")"
    { return makeTupleType(firstType, restTypes) }
 / "(" _ firstType:type restTypes:(_ "->" _ type)+ _ ")"
    { return makeLambdaType(firstType, restTypes) }
 / "[" _ itype:type _ "]" { return { type: "Type", value: "Cons", innerTypes: [itype], location: loc() } }

comment
 = "//" [^\n\r]* _ { return null }

// white space
_  = [ \t]*

nl = ("\r" / "\r\n" / "\n")+ { return " " }
