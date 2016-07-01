# utilities
isUpperCase = (str) ->
  str == str.toUpperCase()

pp = (obj) -> console.log(JSON.stringify(obj, null, '  '))

# convert javascript's object to aoscript's value
obj2ao = (obj) ->
  if typeof obj == 'number'
    new AO.types.Int(obj)
  else if typeof obj == 'string'
    new AO.types.String(obj)
  else if obj instanceof AO.types.Tuple or obj instanceof AO.types.Cons
    obj
  else
    throw new Error("unsupported object: #{obj}")

class EvaluationError extends Error
  constructor: (@message, @location) ->
    @name = "EvaluationError"

# TODO: 現在実行している関数がdestructiveかどうかを格納する
class Environment
  constructor: (@parent, @lexicalParent) ->
    @local = {}
    @typeConstructors = {}

  getValue: (key) ->
    if (val = @local[key])?
      return val
    else
      if (val = @parent?.getValue(key))
        return val
      else if (val = @lexicalParent?.getValue(key))
        return val
      else
        return null

  setValue: (key, value, allowReassignValue = false) ->
    if @local[key]? and !allowReassignValue
      throw new Error("Can't reassign value")
    else
      @local[key] = value

  pushEnv: (lexicalParent) ->
    new Environment(@, lexicalParent)

  popEnv: ->
    @parent

  addUserType: (name, children) ->
    AO.types[name] = {
      name: name
    }
    for child in children
      @typeConstructors[child] = do (child) ->
        {
          create: (values) -> {
            values: values
            toString: -> child + '(' + values.join(', ') + ')'
            typename: -> name
            childTypename: -> child
            canExtractValues: (val) ->
              @values.length == val.values.length

            extractValues: (val) ->
              ret = {}
              for v, i in @values
                ret[v.value] = val.values[i]
              return ret

            toObject: ->
              {
                name: child
                values: @values.map((v) -> v.toObject())
                toString: @toString
              }
          }
          name: child
        }

  toString: ->
    @local.toString()

AO = {}

class AO.Type
  @fromAST: (ast) ->
    innerTypes = if ast.innerTypes?
      ast.innerTypes.map((t) -> AO.Type.fromAST(t))
    else
      []

    new AO.Type(ast.value, innerTypes)

  constructor: (typename, innerTypes) ->
    throw new Error("unknown type: #{typename}") unless AO.types[typename]?
    @type = AO.types[typename]
    @innerTypes = innerTypes

  match: (val) ->
    if @type.name == val.typename()
      switch @type
        when AO.types.Cons
          return true if val.isNull()
          return @innerTypes[0].match(val.car)
        when AO.types.Lambda
          types = [val.outType].concat(val.args.map((arg) -> arg.type))
          for type, i in @innerTypes
            unless type.equals(types[i])
              return false
          return true
        else
          for type, i in @innerTypes
            break if i >= val.values.length # TODO: fix it
            unless type.match(val.values[i])
              return false
          return true
    else
      return false

  equals: (type) ->
    return false unless type instanceof AO.Type
    return false unless @type == type.type
    return false unless @innerTypes.length == type.innerTypes.length
    for it, i in @innerTypes
      unless it.equals(type.innerTypes[i])
        return false
    return true

  toString: ->
    "#{@type.name}(#{@innerTypes.join(', ')})"

AO.types = {}

class AO.types.Value
  constructor: ->
  typename: -> @constructor.name
  toObject: -> throw new Error("#toObject is not implemented at #{@}")

class AO.types.Cons extends AO.types.Value
  innerTypes: ['a', AO.types.Cons]

  @fromObject: (objects) ->
    @fromArray(objects.map(obj2ao))

  @fromArray: (values) ->
    return AO.NULL if values.length == 0

    car = values.shift()
    cdr = if values.length > 0
      AO.types.Cons.fromArray(values)
    else
      AO.NULL

    new AO.types.Cons(car, cdr)

  constructor: (@car, @cdr) ->
    # checking type
    unless @isNull()
      # TODO: 要修正
      return if @cdr?.type == 'Identifier'

      unless @cdr instanceof AO.types.Cons
        throw new Error("cdr(#{@cdr.typename()}) must be Cons")

      if not @cdr.isNull() and @cdr.car.typename() != @car.typename()
        throw new Error('inner type of cdr must equal type of car')

  isNull: ->
    @car == null and @cdr == null

  _toString: (first) ->
    if first
      "[#{@car}#{@cdr._toString(false)}"
    else if @isNull()
      "]"
    else
      ", #{@car}#{@cdr._toString(false)}"

  canExtractValues: (val) ->
    (@isNull() and val.isNull()) or (!@isNull() and !val.isNull())

  extractValues: (val) ->
    ret = {}
    if not val.isNull()
      ret[@car.value] = val.car
      ret[@cdr.value] = val.cdr
    return ret

  toString: ->
    if @isNull()
      '[]'
    else
      @_toString(true)

  toArray: ->
    if @isNull()
      []
    else
      [@car].concat(@cdr.toArray())

  toObject: ->
    @toArray().map((v) -> v.toObject())

class AO.types.Int extends AO.types.Value
  constructor: (@value) ->
  toString: -> @value.toString()
  toObject: -> @value

class AO.types.Boolean extends AO.types.Value
  constructor: (@value) ->
  toString: -> @value.toString()
  toObject: -> @value

class AO.types.String extends AO.types.Value
  constructor: (@value) ->
  toString: -> @value.toString()
  toObject: -> @value

class AO.types.Lambda extends AO.types.Value
  @fromAST: (ast) ->
    outType = AO.Type.fromAST(ast.outType)
    args = ast.args.map((arg) -> {
      type: AO.Type.fromAST(arg[0])
      name: arg[1].value
    })
    block = ast.block

    new AO.types.Lambda(outType, args, block, AO.currentEnv)

  constructor: (@outType, @args, @block, @lexicalParent) ->

  toString: ->
    'Lambda(' + @args.map((arg) -> arg.type).join(' -> ') + " -> #{@outType})"

  toObject: -> @

class AO.types.Tuple extends AO.types.Value
  @fromObject: (objects) ->
    new AO.types.Tuple(objects.map(obj2ao))

  constructor: (@values) ->
  toString: ->
    '(' + @values.join(', ') + ')'

  canExtractValues: (val) ->
    @values.length == val.values.length

  extractValues: (val) ->
    ret = {}
    for v, i in @values
      ret[v.value] = val.values[i]
    return ret

AO.NULL = new AO.types.Cons(null, null)

AO.evalBlock = (block) ->
  ret = block.map(AO.eval)
  ret[ret.length - 1]

# opts: {
#   allowRemainsId: false
#   allowReassignValue: false
# }
AO.eval = (ast, opts = {}) ->
  opts.allowRemainsId = false unless opts.allowRemainsId
  opts.allowReassignValue = false unless opts.allowReassignValue

  return null if ast == null

  switch ast.type
    when 'Bind'
      AO.currentEnv.setValue(ast.valName.value, AO.eval(ast.value), opts.allowReassignValue)
      null

    when 'ApplyFunction'
      switch ast.name.value
        when 'print!'
          exports.onprint AO.eval(ast.args[0]).toString()
          new AO.types.Tuple([])
        when 'toString'
          new AO.types.String(AO.eval(ast.args[0]).toString())
        else
          name = ast.name.value
          if isUpperCase(name[0])
            switch name
              when 'Cons'
                if ast.args.length != 2
                  throw new EvaluationError('Cons needs two arguments')
                new AO.types.Cons(AO.eval(ast.args[0], opts), AO.eval(ast.args[1], opts))
              else
                if AO.rootEnv.typeConstructors[name]?
                  AO.rootEnv.typeConstructors[name].create(ast.args.map((a) -> AO.eval(a, opts)))
                else
                  throw new EvaluationError("unknown type constructor: #{name}", ast.location)
          else
            f = AO.currentEnv.getValue(ast.name.value)
            if f != null
              AO.currentEnv = AO.currentEnv.pushEnv(f.lexicalParent)

              if f.args.length != ast.args.length
                throw new EvaluationError("wrong number of arguments (#{ast.args.length} for #{f.args.length})", ast.location)

              for arg, i in f.args
                val = AO.eval(ast.args[i], opts)
                unless arg.type.match(val)
                  throw new EvaluationError("arguments type error of #{i+1}:#{arg.name} except: #{arg.type}, actual: #{val}:#{val.typename()}", ast.args[i].location)
                AO.currentEnv.setValue(arg.name, val)

              ret = AO.evalBlock(f.block)
              AO.currentEnv = AO.currentEnv.popEnv()

              unless f.outType.match(ret)
                throw new EvaluationError("output type error! except: #{f.outType}, actual: #{ret.typename()}", ast.location)

              ret
            else
              #pp AO.currentEnv
              console.log AO.currentEnv
              throw new EvaluationError("undefiend function #{ast.name.value}", ast.name.location)
    when 'BinaryOperation'
      left = AO.eval(ast.left, opts).value
      right = AO.eval(ast.right, opts).value
      i = AO.types.Int
      b = AO.types.Boolean
      return switch(ast.op)
        when '+'
          new i(left + right)
        when '-'
          new i(left - right)
        when '*'
          new i(left * right)
        when '%'
          new i(left % right)
        when '=='
          new b(left == right)
        when '>='
          new b(left >= right)
        when '<='
          new b(left <= right)
        when '>'
          new b(left > right)
        when '<'
          new b(left < right)
        when '||'
          new b(left || right)
        when '&&'
          new b(left && right)
    when 'UnaryOperation'
      res = {
        '+': (v) -> v
        '-': (v) -> -v
      }[ast.op](AO.eval(ast.val, opts).value)
      new AO.types.Int(res)
    when 'Identifier'
      return ast if opts.allowRemainsId

      val = AO.currentEnv.getValue(ast.value)
      if val != null
        val
      else
        #pp AO.currentEnv
        console.log AO.currentEnv
        throw new EvaluationError("undefiend value #{ast.value}", ast.location)

    when 'If'
      if AO.eval(ast.condition).value
        AO.evalBlock(ast.iftrue)
      else
        AO.evalBlock(ast.ifelse)

    when 'PatternMatch'
      val = AO.eval(ast.value)
      for pattern in ast.patterns
        pat = AO.eval(pattern[0], allowRemainsId: true)
        continue unless val.typename() == pat.typename()

        if pat.canExtractValues(val)
          AO.currentEnv = AO.currentEnv.pushEnv(AO.currentEnv)

          values = pat.extractValues(val)
          for k, v of values
            AO.currentEnv.setValue(k, v)

          ret = AO.eval(pattern[1])

          AO.currentEnv = AO.currentEnv.popEnv()

          return ret

      throw new EvaluationError("value hasn't mathed any patterns", ast.location)

    when 'Lambda'
      AO.types.Lambda.fromAST(ast)

    when 'List'
      AO.types.Cons.fromArray(ast.value.map((a) -> AO.eval(a, opts)))

    when 'Int'
      new AO.types.Int(ast.value)

    when 'Boolean'
      new AO.types.Boolean(ast.value)

    when 'String'
      new AO.types.String(ast.value)

    when 'Tuple'
      new AO.types.Tuple(ast.value.map((a) -> AO.eval(a, opts)))

    else
      throw new EvaluationError("unknown ast type: #{ast.type}", ast.location)

exports = {
  Environment: Environment
  Tuple: AO.types.Tuple
  Cons:  AO.types.Cons
  eval: (code, rootEnv = new Environment(null), opts = {}) ->
    AO.rootEnv = AO.currentEnv = rootEnv

    rootEnv.addUserType('Maybe', ['Just', 'Nothing'])

    ast = PEG.parse(code).filter((a) -> a != null)

    ret = ast.map (a) -> AO.eval(a, opts)
    return ret[ret.length - 1]

  evalBlock: (lambda, env) ->
    AO.rootEnv = AO.currentEnv = env
    AO.evalBlock(lambda.block)

  applyFunction: (lambda, args) ->
    AO.currentEnv = AO.currentEnv.pushEnv(lambda.lexicalParent)

    if lambda.args.length != args.length
      throw new Error("wrong number of arguments (#{args.length} for #{lambda.args.length})")

    for arg, i in lambda.args
      val = args[i]
      unless arg.type.match(val)
        throw new Error("Type error! except: #{arg.type}, actual: #{val.typename()}")
      AO.currentEnv.setValue(arg.name, val)

    ret = AO.evalBlock(lambda.block)
    AO.currentEnv = AO.currentEnv.popEnv()

    unless lambda.outType.match(ret)
      throw new Error("Type error! except: #{lambda.outType}, actual: #{ret.typename()}")

    return ret
  obj2ao: obj2ao

  # config
  onprint: console.log
}

if isNode
  module.exports = exports
else
  window.aoscript = exports
