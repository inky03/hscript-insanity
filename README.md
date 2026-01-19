# hscript-insanity

> [!TIP]
> this is my first time messing with code and macros this complex so ... 
> i apologize for any terribly mid code u might encounter !! (feel free to PR)

experimental fork of [hscript](https://github.com/HaxeFoundation/hscript)!! (parse and evaluate Haxe expressions dynamically)

! this project is inspired by [hscript-iris](https://github.com/pisayesiwsi/hscript-iris) and [rulescript](https://github.com/Kriptel/RuleScript) !

still a heavy work in progress, have patience ...


## Features & amendments

### Simple `Script` class

allows you to define code, give it a name, and run it easily

```hx
import insanity.Script;

var script:Script = new Script('
function testFunction(a, b, c)
	trace(a + b + c);

trace("hi!!");
');

script.start();
script.call('testFunction', 1, 2, 3);
```

you can also edit the `variables` map in a Script to expose certain variables on a script. by default, `this` is defined as the Script instance


### Scripted modules and types (with `Module` and `Environment`)

> [!WARNING]
> this feature is experimental and currently very unfinished. <br>
> CLASS and ENUM types are supported (TYPEDEFS (alias) and ABSTRACTS may be supported later)

you can load custom modules from string and use them in scripts !!

```hx
var path:String = 'test/source/TestModule.hxs';
var module:Module = new Module(File.getContent(path), 'TestModule', ['package', 'name'], path);

var environment:Environment = new Environment([module]);
environment.start();

/*
new Module creates a new module script instance...
you can then add it to a new Environment ! (think of it as the source code folder)
start() it to initialize all added modules and make them usable in new Scripts !!
*/

var path:String = 'test/scripts/TestScript.hxs';
var script:Script = new Script(File.getContent(path), path, environment);
script.start();
```

you can also define types in a script itself, for example:

```hx
class TestClass {
	public function new() {
		trace('hi!!');
	}
}

var instance:TestClass = new TestClass();

/*
do note that classes defined in scripts have certain limitations,
such as (maybe expectedly) not being importable in other scripts !
*/
```

if you want to make a haxe class extendable in scripted classes, extend your class and add the `IScripted` interface like the following:

```hx
class BaseThing {
	// ...
}

class ScriptedThing extends BaseThing implements insanity.IScripted {}
```

(NOTE: currently only most behavior is properly implemented from extending classes. while i dont see why implement the interface in the base class, some things might have to be promptly fixed to correctly support them ...)



### Abstracts

> [!WARNING]
> this feature is Very experimental and has only been tested with interp, i apologize for any issues that might currently arise from trying to use it. 
> add the `@:build(insanity.backend.macro.AbstractMacro.build())` metadata to your abstracts to make them usable in Insanity

you can import abstracts and use MOST of their features !! (see the Todo for all implemented / missing features)

due to type parameter limitations, you must Explicitly cast an expression to the desired abstract type.. recommendably , store it in a local variable to modify it with ease.<br>
you can also include a type parameter for an implicit cast in variable / method argument declarations.

enum abstracts should also be supported !

```hx
import flixel.util.FlxColor;

function colorToString(color:FlxColor)
	return '(red: ${color.red} | green: ${color.green} | blue: ${color.blue})';

var color:FlxColor = cast 0xff0040; // or cast(0xff0040, FlxColor)
trace(colorToString(color)); // (red: 255 | green: 0 | blue: 64)
color.green = FlxColor.GREEN.green;
trace(colorToString(color)); // (red: 255 | green: 128 | blue: 64)
```


### Imports

the [`import`](https://haxe.org/manual/type-system-import.html) keyword is supported

you can import classes by module or package path (wildcard), similarly to actual haxe. you may also even import a single class or a static field, and give it an alias !

all bottom level classes like Reflect, Type and your Main application class should similarly also be exposed by default in scripts

```hx
import sys.*; // sys package wildcard
import Reflect.getProperty as get;

trace(FileSystem.exists('Main.hx'));
trace(get({hi: 123}, 'hi'));
```

you can also import type alias typedefs ! due to type parameters being mostly stripped at runtime, adding support for importing anonymous structure typedefs is not very practical

all type information is registered in `insanity.backend.TypeCollection.main`


### Using (static extension)

the [`using`](https://haxe.org/manual/lf-static-extension.html) keyword is supported (to most capacity)

```hx
using Lambda;

var array:Array<Int> = [1, 2, 3, 4, 5];

array = array.map(function(item) {
	if (item == 3) return 10;
	else return item;
});

trace(array); // [1, 2, 10, 4, 5]
```


### Enums

enums can be imported or created in hscript and support constructors.

basic enum matching in a switch statement is also implemented !

```hx
// in source code ...
enum TestEnum {
	Hi(message:String);
	Bye;
}

// in script ...
import TestEnum;
trace(Hi('hello!!'));
trace(Bye);
```


### String interpolation

string interpolation with $ is fully supported !

```hx
var test:Int = 1234;

trace('hello $test ${'can also be nested!! $$${test + 3210}'}');
```


### Property accessors

haxe's [property accessors](https://haxe.org/manual/class-field-property.html) can be defined in local variables within scripts and module types

```hx
var customSetter(default, set):Dynamic = 123;

function set_customSetter(v:Dynamic):Dynamic {
	trace('setting to $v !');
	return customSetter = v;
}

customSetter = 456;
```


### Regex

haxe's [special regex syntax](https://haxe.org/manual/std-regex.html) can now be used to make a new regular expression in hscript (instead of `new EReg`)

```hx
trace(~/hx/i.replace('HX is Awesome', 'Haxe')); // Haxe is Awesome
```


### Call stack

script interpreter exceptions now throw an `InterpException`, which contains more detailed error info more akin to Haxe's exception call stack

also imposes a limit for the call stack before a Stack overflow exception (200 by default, can be adjusted with `callStackDepth` in an `Interp` instance)

```
Exception: ouch...
Called from test/TestScript.hxs.crash (test/TestScript.hxs line 2 column 8)
Called from script test/TestScript.hxs (test/TestScript.hxs line 4 column 1)
Called from Main.main (Main.hx line 10 column 3)
```


### Null coalescing operator

albeit partially supported in base hscript (`?.`) the other [null coalescing operators](https://haxe.org/manual/expression-null-coalesce.html) (`??` and `??=`) are now implemented

also fixes unintended behavior with `ident?.method()` throwing an error is the ident is null


### Function arguments

- **Rest**
	
	allows [rest argument](https://api.haxe.org/haxe/Rest.html) to be used in a function
	
- **Optional arguments**
	
	providing a default value for an argument now treats it as optional, regardless of a `?` preceding the argument name (which is , presumably, unintended behavior...)
	
	also fixed a bug where default argument values didn't work as intended in specific conditions
	
	```hx
	function test(?arg = false, arg2 = false) {
		trace(arg);
		trace(arg2); // argument would not be considered optional by the parser previously
	}
	```

## Map declaration

you can declare an empty map with type parameters. in base hscript, `[]` usually just represents an empty array

```hx
var map:Map<String, Dynamic> = [];
trace(Type.typeof(map));

var array = [];
trace(Type.typeof(array));
```


## Why is it called hscript-insanity

it represents my Dwindling mental state as i figure how to modify this library !


## Todo

### compiled

- abstracts
	- [X] static fields
	- [X] instance fields
	- [X] cast from / to types
	- [ ] overload operators (`@:op`)
	
- enum abstracts
	- [X] static fields
	- [X] constructors
	
- enums
	- [X] constructors
	- [X] constructor arguments
	
- typedefs
	- [X] type alias import
	- [ ] ~~anonymous structure~~

### scripted

- types
	- [X] classes
		- [X] extends Nothing (or scripted class)
		- [X] extends Real types
	- [X] enums
	- [X] typedefs (type alias only)
	- [ ] abstracts

- general
	- [X] fix compile errors in HashLink (for now)
	- [X] property getters & setters
		- [ ] accessor error checking in modules
	- [ ] fix module exceptions (can merge call stack?)
	- [ ] abstract type fields (currently untested)

### other

- `using` keyword
	- [ ] explicit type checking?
- `switch` keyword
	- [ ] complex pattern matching
- `Printer` class
	- [ ] fix printed expressions with escape characters
	- [ ] module declaration to string ?
