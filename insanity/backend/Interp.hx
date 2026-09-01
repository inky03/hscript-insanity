/*
 * Copyright (C)2008-2017 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
package insanity.backend;

import insanity.backend.Expr;
import insanity.backend.Exception;
import insanity.backend.CallStack;
import insanity.backend.types.Scripted;
import insanity.backend.macro.AbstractMacro;
import haxe.PosInfos;
import haxe.Constraints.IMap;

import Type as HaxeType;
import Reflect as HaxeReflect;

import insanity.custom.InsanityType.ICustomEnumValueType;
import insanity.custom.InsanityReflect as Reflect;
import insanity.custom.InsanityType as Type;
import insanity.custom.InsanityStd as Std;

using StringTools;
using insanity.tools.Tools;
using insanity.backend.TypeCollection;
using insanity.backend.types.Abstract;

enum Stop {
	SBreak;
	SContinue;
	SReturn;
}

@:structInit class Variable {
	public var r:Dynamic;
	public var a:Null<InsanityAbstractValue> = null;
	
	public var isFinal:Null<Bool> = null;
	public var access:Null<Array<FieldAccess>> = null;
	
	public var get:String = 'default';
	public var set:String = 'default';
}

@:structInit class RestoreVariable {
	public var n:String;
	public var old:Variable;
}

/**
 * Interprets script expressions generated from a `Parser`.
 */
class Interp {
	/**
	 * The interpreter's usings.
	 */
	public var usings : Array<Dynamic>;
	/**
	 * The interpreter's imports.
	 */
	public var imports : Map<String, Dynamic>;
	/**
	 * The interpreter's global variables.
	 */
	public var variables : Map<String, Dynamic>;
	var binops : Map<String, Expr -> Expr -> Dynamic >;
	var mathOps : Map<String, Bool>;
	
	public var parent : Dynamic = null;
	/**
	 * The interpreter's `Environment`.
	 */
	public var environment : Environment;
	
	/**
	 * Whether the interpreter can define global variables and functions or not.
	 */
	public var defineGlobals:Bool = false;
	@:noCompletion public var superConstructorAllowed:Bool = false;
	
	static var localsPool : Array<Map<String, Variable>> = [];
	
	/**
	 * The interpreter's call stack.
	 */
	public var stack : CallStack;
	/**
	 * The interpreter's call stack depth.
	 * 
	 * If the stack exceeds this number, an exception will be thrown to avoid infinite recursion.
	 */
	public var callStackDepth : Int = 200;
	/**
	 * The interpreter's current stack frame's local variables.
	 */
	public var locals : Map<String, Variable>;
	
	var inTry : Bool;
	var metas : Metadata = [];
	var captures : Map<String, Dynamic>;
	var declared : Array<RestoreVariable>;
	var returnValue : Dynamic;
	
	static var void(default, never):Dynamic = {};
	static var accessingInterp:Interp = null;
	var position : Position = { origin: 'hscript', line: 0 };
	var origin (get, set) : String;
	var curAccess : String = '';
	
	@:noCompletion public var canDefer:Bool = false;
	@:noCompletion public var canInit:Bool = false;
	
	/**
	 * Creates a new `Interp`.
	 * 
	 * @param	environment	The `Environment` this script will use.
	 * @param	parent		Unused
	 */
	public function new(?environment:Environment, ?parent:Dynamic) {
		this.environment = environment;
		this.parent = parent;
		
		stack = new CallStack();
		
		imports = new Map();
		usings = new Array();
		captures = new Map();
		variables = new Map();
		declared = new Array();
		
		initOps();
	}
	
	/**
	 * Initializes default variables within the interpreter.
	 * 
	 * @param	wipe			Whether to completely wipe any previously defined imports / usings / variables or not.
	 * @param	includeConfig	Whether to define `Config`'s default variables and imports in this interpreter.
	 */
	public function setDefaults(wipe:Bool = true, includeConfig:Bool = true):Void {
		if (wipe) {
			imports.clear();
			usings.resize(0);
			variables.clear();
		}
		
		if (includeConfig) {
			for (k => v in Config.globalVariables)
				variables.set(k, v);
			
			for (k => v in Config.globalImports)
				importPath(k.split('.'), v);
		}
		
		variables.set('trace', Reflect.makeVarArgs(this.trace));
	}
	
	/**
	 * Outputs to console, including information about the position where the `trace()` call was made.
	 * Can be overridden to execute custom behavior.
	 * 
	 * @param	args	Array of arguments to output
	 */
	public function trace(args:Array<Dynamic>):Void {
		var inf = posInfos();
		var v = args.shift();
		if (args.length > 0) inf.customParams = args;
		haxe.Log.trace(Std.string(v), inf);
	}
	
	public function toString() : String {
		return 'insanity.backend.Interp(parent: $parent | origin: $origin)';
	}
	
	/**
	 * Gets a `haxe.PosInfos` from the interpreter's current position.
	 */
	public function posInfos(): PosInfos {
		return cast { fileName : position.origin, lineNumber : position.line };
	}
	
	inline function set_origin(v:String):String { return position.origin = v; }
	inline function get_origin():String { return position.origin; }
	
	inline function basicOp(op:String, v1:Dynamic, v2:Dynamic):Dynamic {
		if (v1 is Expr) v1 = expr(v1);
		
		if (v1 is InsanityAbstractValue) {
			if (v2 is Expr) v2 = expr(v2);
			
			final ab:InsanityAbstractValue = cast v1, type = AbstractTools.getAbstractTypeCast(v2);
			final field:Null<String> = ab.findOverload(ABinop(op, type), v2);
			
			if (field != null) {
				return v1.binop(op, v2);
			} else if (!InsanityAbstract.needOps.exists(op)) {
				return defaultOp(op, v1.__a, v2 is InsanityAbstractValue ? v2.__a : v2);
			} else {
				return throw 'Cannot perform $op on ${ab.info.name} and ${AbstractTools.abstractTypeCastToString(type)}';
			}
		} else {
			if (op == '??' && v1 != null) {
				return v1;
			} else if (op == '||' && v1 == true) {
				return true;
			} else if (op == '&&' && v1 != true) {
				return false;
			} else {
				if (v2 is Expr) v2 = expr(v2);
				
				if (v2 is InsanityAbstractValue) {
					final ab:InsanityAbstractValue = cast v2, type = AbstractTools.getAbstractTypeCast(v1);
					
					final field:Null<String> = ab.findOverload(ABinop(op, type), v1);
					
					if (field != null && (ab.info.methods.get(field).isCommutative || ab.info.methods.get(field).isStatic)) {
						return v2.binop(op, v1);
					} else if (!InsanityAbstract.needOps.exists(op)) {
						return defaultOp(op, v1, v2.__a);
					} else {
						return throw 'Cannot perform $op on ${AbstractTools.abstractTypeCastToString(type)} and ${ab.info.name}';
					}
				} else {
					return defaultOp(op, v1, v2);
				}
			}
		}
	}
	
	inline function defaultOp(op:String, v1:Dynamic, v2:Dynamic):Dynamic {
		return switch (op) {
			case '+': (v1 + v2);
			case '-': (v1 - v2);
			case '*': (v1 * v2);
			case '/': (v1 / v2);
			case '%': (v1 % v2);
			case '&': (v1 & v2);
			case '|': (v1 | v2);
			case '^': (v1 ^ v2);
			case '<<': (v1 << v2);
			case '>>': (v1 >> v2);
			case '>>>': (v1 >>> v2);
			case '==': (v1 == v2);
			case '!=': (v1 != v2);
			case '>=': (v1 >= v2);
			case '<=': (v1 <= v2);
			case '>': (v1 > v2);
			case '<': (v1 < v2);
			case '||': (v1 == true || v2 == true);
			case '&&': (v1 == true && v2 == true);
			case '...': new IntIterator(v1, v2);
			case '??': (v1 ?? v2);
			default: throw '??? ($op)';
		}
	}
	
	function initOps() {
		binops = [
			'=' => assign,
			'is' => function(e1:Expr, e2:Expr) return Std.isOfType(expr(e1), expr(e2))
		];
		
		for (op in ['+', '-', '*', '/', '%', '&', '|', '^', '<<', '>>', '>>>', '==', '!=', '>=', '<=', '>', '<', '||', '&&', '...', '??'])
			binops.set(op, basicOp.bind(op));
		
		for (op in ['+', '-', '*', '/', '%', '&', '|', '^', '<<', '>>', '>>>', '??'])
			assignOp('$op=', basicOp.bind(op));
	}

	function setVar( name : String, v : Dynamic ) : Dynamic {
		if (AbstractTools.isAbstract(v))
			v = v.__a;
		
		var iv = imports.get(name);
		if (iv != null) {
			if (iv is Mirror) {
				switch (iv) {
					case MScriptAbstract(a):
						return a.__a = v;
					case MProperty(t, f):
						if (curAccess == f) { return Reflect.setField(t, f, v); }
						else { return Reflect.setProperty(t, f, v); }
						return Reflect.field(t, f);
					default:
				}
			}
			
			error(ECustom('Invalid assign'));
		}
		
		if (variables.exists(name)) {
			var vv = variables.get(name);
			if (vv is Mirror) {
				switch (vv) {
					case MScriptAbstract(a):
						return a.__a = v;
					case MProperty(t, f):
						if (curAccess == f) { return Reflect.setField(t, f, v); }
						else { return Reflect.setProperty(t, f, v); }
						return Reflect.field(t, f);
					default:
				}
			}
			
			variables.set(name, v);
		} else {
			if (stack.length <= 1 && defineGlobals) { // global scope
				variables.set(name, v);
				return v;
			}
			
			error(EUnknownVariable(name));
		}
		
		return v;
	}

	function assign( e1 : Expr, e2 : Expr ) : Dynamic {
		var v = expr(e2);
		switch( Tools.expr(e1) ) {
		case EIdent(id):
			if (locals.exists(id)) {
				setLocal(id, v);
			} else {
				setVar(id,v);
			}
		case EField(e,f,_):
			v = set(expr(e),f,v);
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			
			if (isMap(arr)) {
				setMapValue(arr, index, v);
			} else if (arr is InsanityAbstractValue) {
				return arr.op(AArray(true, AbstractTools.getAbstractTypeCast(index), AbstractTools.getAbstractTypeCast(v)), v, index);
			} else {
				arr[index] = v;
			}

		default:
			error(EInvalidOp("="));
		}
		return v;
	}

	function assignOp( op, fop : Dynamic -> Dynamic -> Dynamic ) {
		binops.set(op,function(e1,e2) return evalAssignOp(op,fop,e1,e2));
	}

	function evalAssignOp(op,fop,e1,e2) : Dynamic {
		var v;
		switch( Tools.expr(e1) ) {
		case EIdent(id):
			v = fop(expr(e1),expr(e2));
			
			if (locals.exists(id)) {
				setLocal(id, v);
			} else {
				setVar(id,v);
			}
		case EField(e,f,_):
			var obj = expr(e);
			v = fop(get(obj,f),expr(e2));
			v = set(obj,f,v);
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			if (isMap(arr)) {
				v = fop(getMapValue(arr, index), expr(e2));
				setMapValue(arr, index, v);
			}
			else {
				v = fop(arr[index],expr(e2));
				arr[index] = v;
			}
		default:
			return error(EInvalidOp(op));
		}
		return v;
	}
	
	/**
	 * Retrieves a local variable.
	 * 
	 * @param	id		The identifier / name of the local variable.
	 * @param	map		Map of locals to use. If none provided, uses the interpreter's locals map.
	 * @return	The value of the local variable, if any.
	 */
	public function getLocal(id:String, ?map:Map<String, Variable>):Dynamic {
		var map:Map<String, Variable> = (map ?? locals);
		var l:Variable = map.get(id);
		if (l == null) return null;
		
		switch (l.get) {
			case 'null':
				if (accessingInterp != this) throw 'This expression cannot be accessed for reading';
				return (l.a ?? l.r);
			case 'never':
				throw 'This expression cannot be accessed for reading'; return null;
			case 'get' | 'dynamic' if (getMeta(':bypassAccessor') != null):
				return (l.a ?? l.r);
			case 'get' | 'dynamic':
				if (curAccess == id) return l.r;
				
				var hasLocal:Bool = locals.exists('get_$id');
				if (hasLocal || variables.exists('get_$id')) {
					var prevAccess:String = curAccess;
					curAccess = id;
					var v = Reflect.callMethod(this, hasLocal ? locals.get('get_$id').r : variables.get('get_$id'), []);
					curAccess = prevAccess;
					return v;
				}
				
				error(ECustom('Method get_$id required by property $id is missing')); return null;
			case 'default':
				return (l.a ?? l.r);
			default:
				throw 'Invalid property accessor'; return null;
		}
	}
	/**
	 * Sets a local variable.
	 * 
	 * @param	id		The identifier / name of the local variable.
	 * @param	v		The value to set this local variable to.
	 * @param	map		Map of locals to use. If none provided, uses the interpreter's locals map.
	 * @return	The new value of the local variable.
	 */
	public function setLocal(id:String, v:Dynamic, ?map:Map<String, Variable>):Dynamic {
		var map:Map<String, Variable> = (map ?? locals);
		var l:Variable = map.get(id);
		if (l == null) return null;
		
		if (v is InsanityAbstractValue)
			v = v.__a;
		
		if (l.isFinal)
			throw 'Cannot assign to final';
		
		if (l.access != null && Reflect.isFunction(l.r) && !l.access.contains(ADynamic))
			throw 'Cannot rebind method $id: please use \'dynamic\' before method declaration';
		
		switch (l.set) {
			case 'null':
				if (accessingInterp != this) throw 'This expression cannot be accessed for writing';
				
				if (l.a != null) return l.a.__a = v;
				
				return l.r = v;
			case 'never':
				throw 'This expression cannot be accessed for writing'; return null;
			case 'set' | 'dynamic' if (getMeta(':bypassAccessor') != null):
				if (l.a != null) return l.a.__a = v;
				
				return l.r = v;
			case 'set' | 'dynamic':
				if (curAccess == id) {
					if (l.a != null) return l.a.__a = v;
					
					return l.r = v;
				}
				
				var hasLocal:Bool = locals.exists('set_$id');
				if (hasLocal || variables.exists('set_$id')) {
					var prevAccess:String = curAccess;
					curAccess = id;
					Reflect.callMethod(this, hasLocal ? locals.get('set_$id').r : variables.get('set_$id'), [v]);
					curAccess = prevAccess;
					return l.r;
				}
				
				error(ECustom('Method set_$id required by property $id is missing')); return null;
			case 'default':
				if (l.a != null) return l.a.__a = v;
				
				return l.r = v;
			default:
				error(ECustom('Invalid property accessor ${l.set}')); return null;
		}
	}

	function increment( e : Expr, prefix : Bool, delta : Int ) : Dynamic {
		position = e.pos;
		var e = e.e;
		
		switch(e) {
		case EIdent(id):
			var l = locals.get(id);
			var v:Dynamic = (locals.exists(id) ? getLocal(id) : resolve(id));
			
			if (v is InsanityAbstractValue && v.increment(prefix, delta)) return v;
			
			if( prefix ) {
				v += delta;
				if (locals.exists(id)) setLocal(id, v) else setVar(id, v);
			} else {
				if (locals.exists(id)) setLocal(id, v + delta) else setVar(id, v + delta);
			}
			
			return v;
		case EField(e,f,_):
			var obj = expr(e);
			var v:Dynamic = get(obj,f);
			
			if (v is InsanityAbstractValue && v.increment(prefix, delta)) return v;
			
			if( prefix ) {
				v += delta;
				set(obj, f, v);
			} else {
				set(obj, f, v + delta);
			}
			
			return v;
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			
			if (isMap(arr)) {
				var v:Dynamic = getMapValue(arr, index);
				
				if (v is InsanityAbstractValue && v.increment(prefix, delta)) return v;
				
				if (prefix) {
					v += delta;
					setMapValue(arr, index, v);
				}
				else {
					setMapValue(arr, index, v + delta);
				}
				
				return v;
			} else {
				var v:Dynamic = arr[index];
				
				if (v is InsanityAbstractValue && v.increment(prefix, delta)) return v;
				
				if( prefix ) {
					v += delta;
					arr[index] = v;
				} else {
					arr[index] = v + delta;
				}
				
				return v;
			}
			
		default:
			return error(EInvalidOp(delta > 0 ? '++' : '--'));
		}
	}
	
	/**
	 * Executes an array of module declarations. This only has effect in `import` and `using` statements.
	 * 
	 * @param	decls	The module declarations to execute.
	 * @param	path	Unused
	 */
	public function executeModule(decls:Array<ModuleDecl>, path:String):Void {
		try {
			if (stack.length == 0)
				pushStack(SModule(path));
			
			for (decl in decls) {
				position = decl.pos;
				
				switch (decl.d) {
					default:
					case DUsing(path):
						usingType(path);
					case DImport(path, mode):
						importPath(path, mode);
				}
			}
		} catch (e:haxe.Exception) {
			if (e is InterpException) {
				throw e;
			} else {
				pushStack();
				
				throw new InterpException(stack, e.message);
			}
		}
	}
	
	/**
	 * Executes an expression.
	 * 
	 * @param	expr	The expression to execute.
	 * @return	The expression's return value, if any.
	 */
	public function execute( expr : Expr ) : Dynamic {
		try {
			while (stack.length > 0) shiftStack();
			declared.resize(0);
			
			return exprReturn(expr);
		} catch (e:haxe.Exception) {
			if (e is InterpException) {
				throw e;
			} else {
				pushStack();
				
				throw new InterpException(stack, e.message, e);
			}
		}
		
		return null;
	}

	function exprReturn(e, ?t:CType) : Dynamic {
		try {
			return expr(e, t);
		} catch( e : Stop ) {
			#if cpp if (!(e is Stop)) throw e; #end
			
			switch( e ) {
			case SBreak: throw "Invalid break";
			case SContinue: throw "Invalid continue";
			case SReturn:
				var v = returnValue;
				returnValue = null;
				return v;
			}
		}
		return null;
	}
	
	function pushStack(?item:StackItem, ?locals:Map<String, Variable>):Void {
		var last:Stack = stack.shift();
		
		if (last != null) {
			stack.unshift({locals: last.locals, item: switch (last.item) {
				case SFilePos(item, _, _): SFilePos(item, position.origin, position.line, position.column);
				default: SFilePos(last.item, position.origin, position.line, position.column);
			}});
		}
		
		if (item != null) {
			final newLocals = (locals ?? duplicate(stack.first()?.locals));
			stack.unshift({locals: newLocals, item: item});
			this.locals = newLocals;
			
			if (stack.length > callStackDepth)
				error(ECustom('Stack overflow'));
		}
	}
	inline function shiftStack(put:Bool = true):Stack {
		var item:Stack = stack.shift();
		
		if (put) localsPool.push(item.locals);
		
		locals = stack.first()?.locals;
		
		return item;
	}
	inline function duplicate(?h:Map<String, Variable>):Map<String, Variable> {
		if (localsPool.length > 0) {
			var locals:Map<String, Variable> = localsPool.pop();
			locals.clear();
			
			if (h != null) {
				for (k => v in h)
					locals.set(k, v);
			}
			
			return locals;
		} else {
			return (h?.copy() ?? new Map());
		}
	}

	function restore( old : Int ) {
		while( declared.length > old ) {
			var d = declared.pop();
			
			if (d.old == null) {
				locals.remove(d.n);
			} else {
				locals.set(d.n, d.old);
			}
		}
	}

	function error(e:Error, rethrow:Bool = false):Dynamic {
		pushStack();
		
		var exception:InterpException = new InterpException(stack, Printer.errorToString(e));
		if (rethrow) this.rethrow(exception) else throw exception;
		
		return null;
	}

	inline function rethrow( e : Dynamic ) {
		#if neko
		neko.Lib.rethrow(e);
		#elseif hl
		hl.Api.rethrow(e);
		#else
		throw e;
		#end
	}
	
	function createEnum(t:Enum<Dynamic>, i:Int, ?args:Array<Dynamic>):EnumValue {
		try {
			return Type.createEnumIndex(t, i, args);
		} catch (e:haxe.Exception) {
			throw 'Failed to construct enum of type ${Type.getEnumName(t)}';
		}
	}
	
	inline function resolveMirror(v:Dynamic):Dynamic {
		if (v is Mirror) {
			switch (v) {
				default:
					return v;
				case MScriptAbstract(a):
					return a.__a;
				case MProperty(t, f):
					if (curAccess == f) { return Reflect.field(t, f); }
					else { return Reflect.getProperty(t, f); }
				case MEnumValue(t, i):
					if (!Type.allEnums(t).contains(Type.getEnumConstructs(t)[i]))
						return Reflect.makeVarArgs(function(params:Array<Dynamic>) return createEnum(t, i, params));
					return createEnum(t, i);
			}
		} else {
			return v;
		}
	}

	/**
	 * Resolves an import or global variable. If it can't be resolved, an error will be thrown.
	 * Can be overridden to add custom variable resolution logic.
	 * 
	 * @param	id		The identifier / name of the variable.
	 * @return	The value of the import or global variable.
	 */
	public function resolve(id:String) : Dynamic {
		if (imports.exists(id)) {
			var v:Dynamic = imports.get(id);
			
			if (v == null)
				error(ECustom('Module $id does not define type $id'));
			
			return resolveMirror(v);
		}
		
		if (!variables.exists(id))
			error(EUnknownVariable(id));
		
		return resolveMirror(variables.get(id));
	}
	
	/**
	 * Whether a variable identifier exists or not.
	 * Can be overridden to add custom variable resolution logic.
	 * 
	 * @param	id		The identifier / name of the variable.
	 * @return	Whether the variable identifier exists or not.
	 */
	public function isResolvable(id:String):Bool {
		return (imports.exists(id) || variables.exists(id));
	}
	
	function importType(name:String, t:Dynamic, enumValueImport:Bool = true) {
		if (t == null) return;
		
		if (canInit && t is IInsanityType && t.module != null && !t.initializing && !t.initialized && !t.failed)
			t.module.startType(environment, t);
		
		if (t is InsanityScriptedTypedef) {
			var alias:Dynamic = cast(t, InsanityScriptedTypedef).alias;
			
			if (alias != null)
				imports.set(name, alias);
		} else if (t is InsanityScriptedEnum) {
			imports.set(name, t);
			
			if (enumValueImport)
				importEnumValues(t);
		} else if (t is IInsanityType) {
			imports.set(name, t);
		} else if (t is Class) {
			imports.set(name, t);
		} else if (t is Enum) {
			imports.set(name, t);
			
			if (enumValueImport)
				importEnumValues(t);
		} else if (t is InsanityAbstract) {
			imports.set(name, t);
			
			final ab:InsanityAbstract = cast t;
			
			if (ab.isEnum && enumValueImport) {
				for (name => field in ab.info.properties) {
					if (field.get == ADefault && field.set == ADefault)
						imports.set(name, MProperty(ab, name));
				}
			}
		} else {
			throw 'Invalid import type $t';
		}
	}
	
	function importEnumValues(t:Dynamic) {
		for (i => v in Type.getEnumConstructs(t))
			imports.set(v, MEnumValue(t, i));
	}
	
	function importPath(path:Array<String>, mode:ImportMode):Void {
		if (mode == IAll) {
			var fullPath:String = path.join('.');
			var types:Array<TypeInfo> = Tools.listTypesEx(fullPath, true, [TypeCollection.main, environment?.types]);
			
			if (types == null) return;
			
			imports.set(fullPath.substr(fullPath.lastIndexOf('.') + 1), null);
			for (type in types) {
				final std:Bool = (type.module == 'StdTypes'); // on some @:coreType shit
				
				if (type.module != type.name && !std && type.name != 'Main') continue; // lol
				if (type.name.indexOf('_Impl_') > -1) continue;
				
				importType(type.name, type.kind == 'abstract' && !std ? AbstractTools.resolve(type.compilePath()) : type.resolve(environment), false);
			}
			
			return;
		}
		
		var fields:Array<String> = [];
		
		var i:Int = path.length;
		while (i -- > 0) {
			var fullPath:String = path.slice(0, i + 1).join('.');
			
			if (path[i].isTypeIdentifier()) {
				var types:Array<TypeInfo> = Tools.listTypesEx(fullPath, [TypeCollection.main, environment?.types]);
				
				if (types != null) {
					var field:String = fields.shift();
					if (fields.length > 0) error(EUnexpected(field));
					
					if (field != null) {
						var t:Dynamic = null;
						for (type in types) {
							if (type.name == path[i])
								t = type.resolve(environment);
							
							if (type.name == '${path[i]}_Fields_') {
								var t = type.resolve(environment);
								
								if (!Type.getClassFields(t).contains(field)) continue;
								
								switch (mode) {
									case IAsName(alias): return imports.set(alias, MProperty(t, field));
									default: return imports.set(field, MProperty(t, field));
								}
							}
						}
						
						if (t is Class || t is InsanityScriptedClass || t is InsanityAbstract) {
							if (!Type.getClassFields(t).contains(field))
								error(ECustom('Module ${path[i]} does not define field $field'));
							
							switch (mode) {
								case IAsName(alias): return imports.set(alias, MProperty(t, field));
								default: return imports.set(field, MProperty(t, field));
							}
						} else if (t is Enum || t is InsanityScriptedEnum) {
							var i:Int = Type.getEnumConstructs(t).indexOf(field);
							
							if (i >= 0) {
								switch (mode) {
									case IAsName(alias): return imports.set(alias, MEnumValue(t, i));
									default: return imports.set(field, MEnumValue(t, i));
								}
							} else {
								error(EUnknownField(path[i], field));
							}
						} else {
							error(ECustom('Module ${path[i]} does not define type $field'));
						}
					}
					
					switch (mode) {
						case IAsName(alias):
							for (type in types) {
								if (type.name == path[i]) {
									importType(alias, type.resolve(environment));
									
									return;
								}
							}
							
							error(ECustom('Module ${path[i]} does not define ${path[i]}'));
							
						default:
							imports.set(path[i], null);
							
							for (type in types) {
								if (type.name.indexOf('_Impl_') > -1) continue;
								
								if (type.name.endsWith('_Fields_')) {
									var t = type.resolve(environment);
									
									if (imports.get(path[i]) == null)
										imports.set(path[i], t);
									
									for (field in Reflect.fields(t))
										imports.set(field, MProperty(t, field));
									
									continue;
								}
								
								importType(type.name, type.kind == 'abstract' ? AbstractTools.resolve(type.compilePath()) : type.resolve(environment));
							}
					}
					
					return;
				}
			}
			
			fields.unshift(path[i]);
		}
		
		error(EUnknownType(path.join('.')));
	}
	
	function usingType(path:Array<String>):Void {
		var tf:String = null;
		
		var i:Int = path.length;
		while (i -- > 0) {
			var fullPath:String = path.slice(0, i + 1).join('.');
			
			if (path[i].isTypeIdentifier()) {
				var types:Array<TypeInfo> = Tools.listTypesEx(fullPath, [TypeCollection.main, environment?.types]);
				
				if (types != null && types.length > 0) {
					for (type in types) {
						var t = type.resolve();
						if (t is Class && !usings.contains(t)) usings.push(t);
						imports.set(type.name, t);
					}
					
					return;
				}
				
				if (tf != null) error(ECustom('Module ${path[i]} does not define type $tf'));
			}
			
			if (tf != null) break;
			tf = path[i];
		}
		
		error(EUnknownType(path.join('.')));
	}
	
	public function startDecl(decl:ModuleDecl):Void {
		position = decl.pos;
		
		final metas:Array<MetadataEntry> = metas.copy();
		final cls:Null<IInsanityType> = switch (decl.d) {
			case DClass(m):
				if (variables.exists(m.name)) return;
				
				m.meta = metas;
				new InsanityScriptedClass(m);
			
			case DEnum(m):
				if (variables.exists(m.name)) return;
				
				m.meta = metas;
				new InsanityScriptedEnum(m);
			
			case DTypedef(m):
				if (variables.exists(m.name)) return;
				
				m.meta = metas;
				final cls = new InsanityScriptedTypedef(m);
				
				if (cls.alias != null) return imports.set(m.name, cls.alias);
				cls;
			
			case DInterface(m):
				if (variables.exists(m.name)) return;
				
				m.meta = metas;
				new InsanityScriptedInterface(m);
			
			case DAbstract(m):
				if (variables.exists(m.name)) return;
				
				m.meta = metas;
				new InsanityScriptedAbstract(m);
			
			case DPackage(_) | DImport(_) | DField(_) | DUsing(_):
				throw 'Invalid $decl';
				
				null;
		}
		
		if (cls != null) {
			if (cls is IInsanityInterp) {
				final interp:Interp = cast(cls, IInsanityInterp).interp;
				
				interp.position.origin = position.origin;
				interp.position.line = position.line;
			}
			
			cls.init(environment, this);
			cls.initialized = true;
			
			imports.set(cls.name, cls);
		}
	}
	
	var _rest:Array<Dynamic> = [];
	/**
	 * Builds a function from an expression.
	 * 
	 * @param	name			The name of this function, if any.
	 * @param	params			The arguments of this function.
	 * @param	fexpr			The function's expression.
	 * @param	ret				The function's return type. This is used for abstract type casting.
	 * @param	functionLocals	For internal use
	 * @param	su				For internal use
	 * @return	The generated function.
	 */
	public function buildFunction(?name:String, params:Array<Argument>, fexpr:Expr, ?ret:CType, ?id:Int, ?functionLocals:Map<String, Variable>, su:Bool = false) {
		final item:StackItem = (name == null ? SLocalFunction(id) : SMethod(origin, name));
		final capturedLocals = (functionLocals == null ? duplicate(locals) : null);
		
		var minParams:Int = 0, hasRest:Bool = false;
		for (i => param in params) {
			if (param.rest) {
				hasRest = true;
			} else if (!param.opt && i >= minParams) {
				minParams = (i + 1);
			}
		}
		
		final f = Reflect.makeVarArgs(function(args:Array<Dynamic>) {
			superConstructorAllowed = su;
			
			final old:Int = declared.length;
			pushStack(item, functionLocals ?? duplicate(capturedLocals));
			
			if (args.length < minParams) {
				var expect:Argument = params[args.length];
				for (i in args.length ... params.length) {
					if (params[i].opt) continue;
					
					expect = params[i];
					break;
				}
				
				error(ECustom('Not enough arguments, expected ${expect.name}' + (expect.t == null ? '' : ':${new Printer().typeToString(expect.t)}')));
			} else if (!hasRest && args.length > params.length) {
				error(ECustom('Too many arguments'));
			}
			
			var pos:Int = 0;
			for (param in params) {
				final name:String = param.name;
				
				if (functionLocals != null) declared.push({n: name, old: locals.get(name)});
				
				if (param.rest) {
					_rest.resize(0);
					for (i in (params.length - 1) ... args.length) _rest.push(args[i]);
					
					locals.set(name, {r: _rest});
					continue;
				}
				
				final v:Dynamic = args[pos ++];
				
				if (param.opt) {
					locals.set(name, {r: tryCast(v ?? (param.value != null ? expr(param.value) : null), param.t)});
				} else {
					locals.set(name, {r: tryCast(v, param.t)});
				}
			}
			
			var r:Dynamic = null;
			if (inTry) {
				try {
					r = tryCast(exprReturn(fexpr), ret, true);
				} catch( e : Dynamic ) {
					shiftStack(functionLocals == null);
					rethrow(e);
				}
			} else {
				r = tryCast(exprReturn(fexpr), ret, true);
			}
			
			if (functionLocals != null) restore(old);
			shiftStack(functionLocals == null);
			
			superConstructorAllowed = false;
			
			return r;
		});
		
		if (name != null) {
			if (stack.length > 1) { // function-in-function is a local function
				declared.push({n: name, old: locals.get(name)});
				
				final ref:Variable = {r: f};
				capturedLocals.set(name, ref); // allow self-recursion
				locals.set(name, ref);
			} else if (defineGlobals) { // global function
				variables.set(name, f);
			} else {
				locals.set(name, {r: f});
			}
		}
		
		return f;
	}
	
	var _advancedResolve:Array<Expr> = [];
	function testAdvancedResolve(expr:Expr, exprs:Array<Expr>):Bool {
		return switch (expr.e) {
			case EIdent(_):
				exprs.push(expr);
				true;
				
			case EField(fexpr, _, _):
				var r:Bool = testAdvancedResolve(fexpr, exprs);
				exprs.push(expr);
				r;
				
			default:
				false;
		}
	}
	
	function testNullCoalesce(expr:Expr):Bool {
		return switch (expr.e) {
			default: false;
			
			case EField(fexpr, _, maybe): (maybe ? true : testNullCoalesce(fexpr));
		}
	}
	
	@:noCompletion public function expr( e : Expr, ?t : CType, void : Bool = false, mapCompr : Bool = false ) : Dynamic {
		Type.environment = environment;
		accessingInterp = this;
		position = e.pos;
		
		if (stack.length == 0)
			pushStack(SScript(position.origin));
		
		switch( e.e ) {
		case EDecl(decl):
			startDecl(decl);
		case EUsing(path):
			usingType(path);
		case EImport(path, mode):
			importPath(path, mode);
		case EConst(c):
			switch( c ) {
			case CInt(v): return v;
			case CFloat(f): return f;
			case CString(s): return s;
			case CReg(p, m): return new EReg(p, m);
			}
		case EIdent(id):
			if (captures.exists(id)) return captures.get(id);
			if (locals.exists(id)) return getLocal(id);
			return resolve(id);
		case EVar(n,t,e,get,set,isFinal):
			declared.push({n: n, old: locals.get(n)});
			
			var v:Dynamic = (e == null ? null : expr(e, t));
			var l:Variable = (AbstractTools.isAbstract(v) ? {r: v.__a, a: v} : {r: v});
			
			if (get != null) l.get = get;
			if (set != null) l.set = set;
			if (isFinal) l.isFinal = isFinal;
			
			locals.set(n, l);
		case EParent(e):
			return expr(e, void, mapCompr);
		case EBlock(exprs):
			var old = declared.length;
			var v = null;
			for( e in exprs )
				v = expr(e, void, mapCompr);
			restore(old);
			return v;
		case EField(fe, f, maybe):
			_advancedResolve.resize(0);
			
			if (!testAdvancedResolve(e, _advancedResolve)) {
				final obj:Dynamic = expr(fe);
				
				if (obj == null && testNullCoalesce(e)) return null;
				
				return get(obj, f);
			}
			
			var fail:Null<String> = null, path:String = '', obj:Dynamic = null;
			
			for (expr in _advancedResolve) {
				if (fail == null) position = expr.pos;
				
				switch (expr.e) {
					default: throw '???';
					
					case EIdent(id):
						if (captures.exists(id)) {
							obj = captures.get(id);
						} else if (locals.exists(id)) {
							obj = getLocal(id);
						} else if (isResolvable(id)) {
							obj = resolve(id);
						} else {
							fail = path = id;
						}
					
					case EField(_, f, maybe) if (path.length == 0):
						if (maybe && obj == null) return null;
						
						obj = get(obj, f);
						
					case EField(_, f, maybe):
						final info = (TypeCollection.main.fromPath(path += '.$f') ?? environment?.types.fromPath(path));
						
						if (info != null) {
							fail = null;
							obj = info[0].resolve(environment);
						} else if (fail == null) {
							if (maybe && obj == null) return null;
							
							obj = get(obj, f);
						}
				}
			}
			
			if (fail != null) error(EUnknownVariable(fail));
			
			return obj;
		case EBinop('=>', e1, e2) if (mapCompr):
			return e;
		case EBinop(op,e1,e2):
			var fop = binops.get(op);
			if (fop == null) error(EInvalidOp(op));
			
			return fop(e1, e2);
		case EUnop(op,prefix,e):
			switch(op) {
			case "!":
				final v:Dynamic = expr(e);
				if (v is InsanityAbstractValue && v.hasOp(AUnop('!', false))) return v.op(AUnop('!', false));
				
				return (v != true);
			case "-":
				final v:Dynamic = expr(e);
				if (v is InsanityAbstractValue && v.hasOp(AUnop('-', false))) return v.op(AUnop('-', false));
				
				return -v;
			case "++":
				return increment(e, prefix, 1);
			case "--":
				return increment(e, prefix, -1);
			case "~":
				final v:Dynamic = expr(e);
				if (v is InsanityAbstractValue && v.hasOp(AUnop('~', false))) return v.op(AUnop('~', false));
				
				return ~v;
			default:
				error(EInvalidOp(op));
			}
		case ECall(e,params):
			final args:Array<Dynamic> = [for (p in params) expr(p)];
			
			switch (Tools.expr(e)) {
				case EField(fe, f, maybe):
					var obj = expr(fe);
					
					if (obj == null && testNullCoalesce(e)) return null;
					
					return fcall(obj, f, args);
					
				default:
					return call(null, expr(e), args);
			}
		case EIf(econd,e1,e2):
			return if (expr(econd)) expr(e1, void, mapCompr) else if (e2 == null) (void ? Interp.void : null) else expr(e2, void, mapCompr);
		case EWhile(econd,e):
			whileLoop(econd,e);
			return null;
		case EDoWhile(econd,e):
			doWhileLoop(econd,e);
			return null;
		case EFor(v,it,e):
			forLoop(v,it,expr.bind(e));
			return null;
		case EForGen(it,e):
			Tools.getKeyIterator(it, function(vk,vv,it) {
				if( vk == null ) {
					position = it.pos;
					error(ECustom("Invalid for expression"));
					return;
				}
				forKeyValueLoop(vk,vv,it,expr.bind(e));
			});
			return null;
		case EBreak:
			throw SBreak;
		case EContinue:
			throw SContinue;
		case EReturn(e):
			returnValue = e == null ? null : expr(e, void, mapCompr);
			throw SReturn;
		case EFunction(params,fexpr,name,ret,id):
			return buildFunction(name, params, fexpr, ret, id);
		case EArrayDecl(arr):
			var compr:Dynamic = null;
			
			var exprCompr:(e:Expr, ?inFor:Bool) -> Dynamic = null;
			
			function forExpr(e:Expr) {
				var v:Dynamic = exprCompr(e, true);
				
				if (v is ExprDef) {
					switch (v) {
						default:
						case EBinop('=>', e1, e2):
							var key:Dynamic = expr(e1);
							
							if (key is String) {
								compr ??= new haxe.ds.StringMap();
							} else if (key is Int) {
								compr ??= new haxe.ds.IntMap();
							} else if (HaxeReflect.isEnumValue(key)) {
								compr ??= new haxe.ds.EnumValueMap();
							} else {
								compr ??= new haxe.ds.ObjectMap();
							}
							
							compr.set(key, expr(e2));
							return;
					}
				}
				
				if (v != Interp.void) {
					compr ??= new Array();
					
					compr.push(v);
				}
			}
			
			exprCompr = function(e:Expr, inFor:Bool = false):Dynamic {
				return switch (Tools.expr(e)) {
					case EBlock(e):
						var v = Interp.void;
						
						for (e in e) v = exprCompr(e, inFor);
						
						v;
						
					case EParent(e):
						exprCompr(e, inFor);
						
					case EFor(n, it, e):
						forLoop(n, it, forExpr.bind(e));
						
						Interp.void;
						
					case EForGen(it, e):
						Tools.getKeyIterator(it, function(vk, vv, it) {
							if (vk == null) {
								position = it.pos;
								error(ECustom('Invalid for expression'));
								return;
							}
							
							forKeyValueLoop(vk, vv, it, forExpr.bind(e));
						});
						
						Interp.void;
						
					default:
						expr(e, inFor, inFor);
				}
			}
			
			if ( arr.length > 0 && Tools.expr(arr[0]).match(EBinop("=>", _)) ) { // infer from keys ...
				var keys = [];
				var values = [];
				for( e in arr ) {
					switch(Tools.expr(e)) {
					case EBinop("=>", eKey, eValue):
						keys.push(expr(eKey));
						values.push(expr(eValue));
					default:
						position = e.pos;
						error(ECustom("Invalid map key=>value expression"));
					}
				}
				return makeMap(keys,values);
			} else { // infer from type declaration ... (empty map)
				if (arr.length == 1) {
					exprCompr(arr[0]);
					
					if (compr != null)
						return compr;
				}
				
				switch (t) {
					case CTPath(path, params): // hell
						var fullPath:String = path.join('.');
						
						if (fullPath == 'Map') { // infer from parameters
							if (params == null || params.length < 2) error(ECustom('Not enough type parameters for Map')); // we dont really care about the value type , but whatever
							else if (params.length > 2) error(ECustom('Too many type parameters for Map'));
							
							switch (params[0]) {
								case CTAnon(_):
									return new haxe.ds.ObjectMap<Dynamic, Dynamic>();
								case CTPath(path, _):
									var fullPath:String = path.join('.');
									
									if (fullPath == 'String') {
										return new Map<String, Dynamic>();
									} else if (fullPath == 'Int') {
										return new Map<Int, Dynamic>();
									} else {
										var type:TypeInfo = null;
										var r = (Tools.resolve(fullPath, environment) ?? imports.get(fullPath));
										if (r is Class) {
											type = TypeCollection.main.fromCompilePath(Type.getClassName(r))[0];
										} else if (r == null) {
											error(EUnknownType(fullPath));
										}
										
										if (/*Reflect.isEnumValue(r)*/false) { // todo resolve enum values??
											return new haxe.ds.EnumValueMap<Dynamic, Dynamic>();
										} else if (type?.kind == 'class') {
											return new haxe.ds.ObjectMap<Dynamic, Dynamic>();
										}
									}
								default:
							}
						
							var p = new Printer();
							error(ECustom('Map of type <${p.typeToString(params[0])}, ${p.typeToString(params[1])}> is not accepted'));
						} else {
							var t:Dynamic = resolve(fullPath); // alias stuff
							
							if (t is haxe.ds.IntMap || t is haxe.ds.StringMap || t is haxe.ds.ObjectMap || t is haxe.ds.EnumValueMap)
								return Type.createInstance(t, []);
						}
					default:
				}
				
				var a = new Array();
				for( e in arr )
					a.push(expr(e));
				return a;
			}
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			
			if (isMap(arr))
				return getMapValue(arr, index);
			
			if (arr is InsanityAbstractValue)
				return arr.op(AArray(false, AbstractTools.getAbstractTypeCast(index), null), null, index);
			
			return arr[index];
		case ENew(cl,params):
			return cnew(cl, [for (e in params) expr(e)]);
		case EThrow(e):
			throw expr(e);
		case ETry(e,n,_,ecatch):
			var old = declared.length;
			var oldTry = inTry;
			try {
				inTry = true;
				var v : Dynamic = expr(e);
				restore(old);
				inTry = oldTry;
				return v;
			} catch( err : Stop ) {
				inTry = oldTry;
				throw err;
			} catch( err : Dynamic ) {
				// restore vars
				restore(old);
				inTry = oldTry;
				// declare 'v'
				declared.push({ n : n, old : locals.get(n) });
				locals.set(n,{ r : err });
				var v : Dynamic = expr(ecatch);
				restore(old);
				return v;
			}
		case EObject(fl):
			if (t != null) {
				switch (t) {
					default:
					case CTPath(p, _):
						final path:Dynamic = p.join('.');
						final cls:Dynamic = (imports.get(path) ?? variables.get(path) ?? Tools.resolve(path, environment));
						
						var structInitFields:Null<Array<StructInitField>> = null, path:Null<String> = Type.getClassName(cls);
						
						if (cls is Class) {
							structInitFields = TypeCollection.main.fromCompilePath(path)[0].structInitFields;
						} else if (cls is InsanityScriptedClass) {
							structInitFields = cls.structInitFields;
						}
						
						if (structInitFields != null) return structInitClass(path, structInitFields, fl);
				}
			}
			
			final o:Dynamic = {};
			for (f in fl) HaxeReflect.setField(o, f.name, expr(f.e));
			
			return o;
		case ETernary(econd,e1,e2):
			return if( expr(econd) == true ) expr(e1) else expr(e2);
		case ESwitch(e, cases, def):
			var hasCapture:Bool = false;
			
			function iterCapture(e:Expr) {
				switch (e.e) {
					case EIdent('_') | EIdent(_.isTypeIdentifier() => false):
						hasCapture = true;
						
					case EIdent(id):
					
					case EVar(_):
						hasCapture = true;
						
					default:
						e.iter(iterCapture);
				}
			}
			
			function checkCapture(e:Expr) {
				hasCapture = false;
				e.iter(iterCapture);
				return hasCapture;
			}
			
			function testCase(e:Expr, match:Dynamic, deep:Bool = true) {
				return switch (e.e) {
					case EIdent(id):
						if (imports.exists(id) || variables.exists(id))
							return matchValues(resolve(id), match);
						
						if (id != '_' && id.isTypeIdentifier())
							throw 'Unknown identifier: $id, pattern variables must be lower-case or with \'var \' prefix';
						
						captures.set(id, match);
						return true;
						
					case EField(ve, f, maybe):
						testCase(ve, match);
						
						final obj:Dynamic = expr(ve);
						matchValues(maybe && obj == null ? null : get(obj, f), match);
						
					case EVar(id):
						captures.set(id, match);
						true;
						
					case EConst(_):
						(expr(e) == match);
						
					case EParent(exr):
						testCase(exr, match);
						
					case EBinop('=>', e1, e2):
						captures.set('_', match);
						
						var a:Dynamic = expr(e1);
						testCase(e2, a);
						
						matchValues(a, expr(e2));
						
					case EBinop('|', e1, e2):
						testCase(e1, match);
						testCase(e2, match);
						(matchValues(match, expr(e1)) || matchValues(match, expr(e2)));
						
					case EObject(f):
						if (!Reflect.isObject(match))
							return false;
						for (f in f) {
							if (!Reflect.hasField(match, f.name) || !testCase(f.e, Reflect.field(match, f.name)))
								return false;
						}
						true;
						
					case EArrayDecl(a):
						if (!match is Array)
							return false;
						if (a.length != match.length)
							return false;
						for (i => e in a) {
							if (!testCase(e, match[i]))
								return false;
						}
						true;
						
					case ECall(ce, params):
						if (checkCapture(ce)) {
							testCase(ce, match);
						} else {
							var v = expr(ce);
							
							var ev = Reflect.callMethod(null, v, [for (_ in params) null]);
							if (Type.getEnum(ev) == Type.getEnum(match) && Type.enumConstructor(ev) == Type.enumConstructor(match)) {
								var matchParams = Type.enumParameters(match);
								
								for (i => param in params) {
									if (!testCase(param, matchParams[i]))
										return false;
								}
							} else {
								return false;
							}
						}
						true;
						
					default:
						error(EUnrecognizedPattern(e));
				}
			}
			
			var val : Dynamic = expr(e);
			var match = false;
			for( c in cases ) {
				for( exr in c.values ) {
					captures.clear();
					
					match = testCase(exr, val);
					
					captures.remove('_');
					
					if (c.guard != null && !expr(c.guard))
						match = false;
					
					if (match) break;
				}
				if( match ) {
					val = expr(c.expr, void, mapCompr);
					break;
				}
			}
			
			if( !match )
				val = def == null ? null : expr(def, void, mapCompr);
			
			captures.clear();
			
			return val;
		case EMeta(meta, args, e):
			final old:Int = metas.length;
			metas.push({name: meta, params: args});
			
			try {
				final r:Dynamic = expr(e);
				metas.resize(old);
				return r;
			} catch (e:Dynamic) {
				metas.resize(old);
				rethrow(e);
			}
		case ECast(e, t):
			return tryCast(expr(e), t);
		case ECheckType(e,_):
			return expr(e);
		}
		return (void ? Interp.void : null);
	}
	
	public function structInitClass(path:String, structInitFields:Array<StructInitField>, fields:Array<{name:String, e:Expr}>):Dynamic {
		static var fieldIndex:Map<String, Dynamic> = [];
		
		fieldIndex.clear();
		for (field in fields) {
			fieldIndex.set(field.name, expr(field.e));
			
			if (!Lambda.exists(structInitFields, (f:StructInitField) -> f.name == field.name))
				error(ECustom('Object has extra field ${field.name}'));
		}
		
		return cnew(path, [for (field in structInitFields) {
			if (!field.optional && !fieldIndex.exists(field.name)) error(ECustom('Object requires field ${field.name}'));
			
			fieldIndex.get(field.name);
		}]);
	}
	
	inline function getMeta(name:String):MetadataEntry {
		var entry:MetadataEntry = null;
		
		for (meta in metas) {
			if (meta.name == name) {
				entry = meta;
				break;
			}
		}
		
		return entry;
	}
	
	/**
	 * Evaluates equivalence between two values.
	 * 
	 * @param	v		The first type to evaluate.
	 * @param	with	The second type to evaluate.
	 * @return	Whether the two values are equivalent or not.
	 */
	public static function matchValues(v:Dynamic, with:Dynamic):Bool {
		if (v == with) {
			return true;
		} else if (v is InsanityAbstractValue) {
			return (v.__a == (with is InsanityAbstractValue ? with.__a : with));
		} else if (v is ICustomEnumValueType && with is ICustomEnumValueType) {
			return cast(v, ICustomEnumValueType).eq(with);
		} else if (Reflect.isEnumValue(v) && Type.getEnum(v) != null && Type.getEnum(with) != null) {
			return Type.enumEq(v, with);
		}
		
		return false;
	}
	
	function tryCast(e:Dynamic, ?type:CType, allowStruct:Bool = false):Dynamic {
		switch (type) {
			case CTPath(p, _):
				if (p[0] == 'Void') return e;
				if (e == null) return null;
				
				final path:String = p.join('.');
				final t:Dynamic = (imports.get(path) ?? variables.get(path) ?? Tools.resolve(path, environment));
				
				if (t == null) return e;
				
				if (t is InsanityAbstract) {
					return t.castFrom(e);
				} else if (e is InsanityAbstractValue) {
					return e.castTo(t);
				} else if (allowStruct && HaxeReflect.isObject(e)) {
					static var structInitIndex:Map<String, Null<Array<StructInitField>>> = [];
					
					var structInitFields:Null<Array<StructInitField>> = null, path:Null<String> = Type.getClassName(t);
					
					if (structInitIndex.exists(path)) {
						structInitFields = structInitIndex.get(path);
					} else {
						if (t is Class) {
							structInitFields = TypeCollection.main.fromCompilePath(path)[0].structInitFields;
						} else if (t is InsanityScriptedClass) {
							structInitFields = t.structInitFields;
						}
						
						structInitIndex.set(path, structInitFields);
					}
					
					if (structInitFields != null) {
						for (field in HaxeReflect.fields(e)) {
							if (!Lambda.exists(structInitFields, (f:StructInitField) -> f.name == field))
								error(ECustom('Object has extra field $field'));
						}
						
						return cnew(path, [for (field in structInitFields) {
							if (!field.optional && !HaxeReflect.hasField(e, field.name)) error(ECustom('Object requires field ${field.name}'));
							
							HaxeReflect.field(e, field.name);
						}]);
					}
				}
				
				// if (t != null) throw 'Type not found: $path';
				
				return e;
				
			default:
		}
		
		return e;
	}

	function doWhileLoop(econd,e) {
		var old = declared.length;
		do {
			if( !loopRun(expr.bind(e)) )
				break;
		}
		while( expr(econd) == true );
		restore(old);
	}

	function whileLoop(econd,e) {
		var old = declared.length;
		while( expr(econd) == true ) {
			if( !loopRun(expr.bind(e)) )
				break;
		}
		restore(old);
	}

	inline function makeIterator(v:Dynamic):Iterator<Dynamic>
	{
		if (v is Array) {
			return (v : Array<Dynamic>).iterator();
		} else {
			var iter:Dynamic = v.iterator;
			v = (iter != null ? #if hl Reflect.callMethod(v, iter, []) #else (iter : haxe.Constraints.Function)() #end : v);
			
			if (v.hasNext == null || v.next == null)
				error(EInvalidIterator(v));
			
			return v;
		}
	}
	
	inline function makeKeyValueIterator(v:Dynamic):KeyValueIterator<Dynamic, Dynamic>
	{
		if ((v is haxe.ds.IntMap) || (v is haxe.ds.StringMap) || (v is haxe.ds.ObjectMap) || (v is haxe.ds.EnumValueMap)) {
			return (v : haxe.Constraints.IMap<Dynamic, Dynamic>).keyValueIterator();
		} else if (v is Array) {
			return (v : Array<Dynamic>).keyValueIterator();
		} else {
			var iter:Dynamic = v.keyValueIterator;
			v = (iter != null ? #if hl Reflect.callMethod(v, iter, []) #else (iter : haxe.Constraints.Function)() #end : v);
			
			if (v.hasNext == null || v.next == null)
				error(EInvalidIterator(v));
			
			return v;
		}
	}

	function forLoop(n,it,ef:Dynamic) {
		var old = declared.length;
		declared.push({n: n, old: locals.get(n)});
		
		var it = makeIterator(expr(it));
		var next:Void -> Dynamic = Reflect.field(it, 'next'), hasNext:Void -> Bool = Reflect.field(it, 'hasNext');
		
		final iterV:Variable = {r: null};
		locals.set(n, iterV);
		
		while( hasNext() ) {
			iterV.r = next();
			
			if (!loopRun(ef))
				break;
		}
		
		restore(old);
	}

	function forKeyValueLoop(vk,vv,it,ef:Dynamic) {
		var old = declared.length;
		declared.push({ n : vk, old : locals.get(vk) });
		declared.push({ n : vv, old : locals.get(vv) });
		
		var it = makeKeyValueIterator(expr(it));
		var next:Void -> Dynamic = Reflect.field(it, 'next'), hasNext:Void -> Bool = Reflect.field(it, 'hasNext');
		
		final iterV:Variable = {r: null}, iterK:Variable = {r: null};
		locals.set(vk, iterV);
		locals.set(vv, iterK);
		
		while( hasNext() ) {
			final v = next();
			
			if (v.key == null) error(EUnknownField(v, 'key'));
			if (v.value == null) error(EUnknownField(v, 'value'));
			
			iterV.r = v.key;
			iterK.r = v.value;
			
			if (!loopRun(ef))
				break;
		}
		
		restore(old);
	}

	inline function loopRun( f : Void -> Void ) {
		var cont = true;
		try {
			f();
		} catch( err : Stop ) {
			switch( err ) {
			case SContinue:
			case SBreak:
				cont = false;
			case SReturn:
				throw err;
			}
		}
		return cont;
	}

	inline function isMap(o:Dynamic):Bool {
		return (o is IMap);
	}

	inline function getMapValue(map:Dynamic, key:Dynamic):Dynamic {
		return cast(map, haxe.Constraints.IMap<Dynamic, Dynamic>).get(key);
	}

	inline function setMapValue(map:Dynamic, key:Dynamic, value:Dynamic):Void {
		cast(map, haxe.Constraints.IMap<Dynamic, Dynamic>).set(key, value);
	}

	function makeMap( keys : Array<Dynamic>, values : Array<Dynamic> ) : Dynamic {
		var isAllString:Bool = true;
		var isAllInt:Bool = true;
		var isAllObject:Bool = true;
		var isAllEnum:Bool = true;
		for( key in keys ) {
			isAllString = isAllString && (key is String);
			isAllInt = isAllInt && (key is Int);
			isAllObject = isAllObject && Reflect.isObject(key);
			isAllEnum = isAllEnum && HaxeReflect.isEnumValue(key);
		}

		#if (haxe_ver >= 4.1)
		if( isAllInt ) {
			var m = new Map<Int,Dynamic>();
			for( i => key in keys )
				m.set(key, values[i]);
			return m;
		}
		if( isAllString ) {
			var m = new Map<String,Dynamic>();
			for( i => key in keys )
				m.set(key, values[i]);
			return m;
		}
		if( isAllEnum ) {
			var m = new haxe.ds.EnumValueMap<Dynamic,Dynamic>();
			for( i => key in keys )
				m.set(key, values[i]);
			return m;
		}
		if( isAllObject ) {
			var m = new Map<{},Dynamic>();
			for( i => key in keys )
				m.set(key, values[i]);
			return m;
		}
		#else
		var m:Dynamic = {
			if ( isAllInt ) new haxe.ds.IntMap<Dynamic>();
			else if ( isAllString ) new haxe.ds.StringMap<Dynamic>();
			else if ( isAllEnum ) new haxe.ds.EnumValueMap<Dynamic, Dynamic>();
			else if ( isAllObject ) new haxe.ds.ObjectMap<Dynamic, Dynamic>();
			else null;
		}
		if( m != null ) {
			for ( n in 0...keys.length )
				setMapValue(m, keys[n], values[n]);
			return m;
		}
		#end
		error(ECustom("Invalid map keys "+keys));
		return null;
	}
	
	#if hl
	var insanityhlFunctions:Array<Dynamic> = [];
	#end

	function get( o : Dynamic, f : String ) : Dynamic {
		if (canDefer && o is IInsanityType && !o.initialized)
			throw DDefer;
		
		if ( o == null ) error(EInvalidAccess(f));
		
		if (o is Mirror) {
			switch (cast(o, Mirror)) {
				case MSuper(locals, _):
					if (locals == null) {
						error(EHasNoSuper);
					} else if (locals.exists(f)) {
						return (locals.get(f).a ?? locals.get(f).r);
					} else {
						error(EUnknownVariable(f));
					}
				default:
			}
		}
		
		var bypassAccessor:Bool = (getMeta(':bypassAccessor') != null);
		var prop = (
			if (bypassAccessor) {
				Reflect.field(o, f);
			} else {
				#if hl
				if (!(o is IInsanityScripted || o is IInsanityType)) {
					final v:Dynamic = Reflect.field(o, 'insanityhl$f');
					
					if (v != null) { // maybe should index this to avoid slowdown...
						if (!insanityhlFunctions.contains(v))
							insanityhlFunctions.push(v);
						
						return v;
					}
				}
				#end
				
				Reflect.getProperty(o, f);
			}
		);
		
		if (prop == null && hasField(o, f) == false) {
			var fields = getFieldsClass((o is Class || o is InsanityScriptedClass) ? Type.getClassName(o) : Type.getEnumName(o));
			if (fields != null) return (bypassAccessor ? Reflect.field(fields, f) : Reflect.getProperty(fields, f));
		}
		
		return prop;
	}

	function set( o : Dynamic, f : String, v : Dynamic ) : Dynamic {
		if (o == null) error(EInvalidAccess(f));
		
		if (canDefer && o is IInsanityType && !o.initialized)
			throw DDefer;
		
		if (AbstractTools.isAbstract(v))
			v = v.__a;
		
		var bypassAccessor:Bool = (getMeta(':bypassAccessor') != null);
		
		var field:Dynamic = Reflect.field(o, f);
		if (field is InsanityAbstractValue) return #if cpp Reflect.setProperty(field, '__a', v) #else field.__a = v #end ;
		
		if (field == null && hasField(o, f) == false) {
			var fields = getFieldsClass((o is Class || o is InsanityScriptedClass) ? Type.getClassName(o) : Type.getEnumName(o));
			if (fields != null) return (bypassAccessor ? Reflect.setField(fields, f, v) : Reflect.setProperty(fields, f, v));
		} else if (bypassAccessor) {
			return Reflect.setField(o, f, v);
		} else {
			return Reflect.setProperty(o, f, v);
		}
		
		return null;
	}
	
	inline function hasField(o:Dynamic, f:String):Null<Bool> {
		if (o is Class || o is InsanityScriptedClass) {
			return Type.getClassFields(o).contains(f);
		} else if (o is Enum || o is InsanityScriptedEnum) {
			return Type.getEnumConstructs(o).contains(f);
		} else {
			return null;
		}
	}
	
	inline function getFieldsClass(path:String):Dynamic {
		if (path.endsWith('_Fields_')) return null;
		
		var pack = path.substr(0, path.lastIndexOf('.') + 1);
		var name = path.substr(path.lastIndexOf('.') + 1);
		
		return Tools.resolve('${pack}_$name.${name}_Fields_', environment);
	}

	function fcall( o : Dynamic, f : String, args : Array<Dynamic> ) : Dynamic {
		final fun:Dynamic = get(o, f);
		
		if (o != Std || f != 'string') { // dirty solution but Yeah what ever
			for (i => arg in args)
				args[i] = (AbstractTools.isAbstract(arg) ? arg.__a : arg);
		}
		
		if (!Reflect.isFunction(fun)) {
			for (t in usings) {
				var fun = get(t, f);
				
				if (Reflect.isFunction(fun)) {
					try {
						args.unshift(o);
						return Reflect.callMethod(t, fun, args);
					} catch (e:Dynamic) {}
				}
			}
			
			error(ECustom('Cannot call $fun'));
		}
		
		#if hl if (insanityhlFunctions.contains(fun)) return fun(args); #end
		return call(o, fun, args);
	}

	function call( o : Dynamic, f : Dynamic, args : Array<Dynamic> ) : Dynamic {
		if (f is Mirror) {
			switch (cast(f, Mirror)) {
				case MSuper(locals, constructor):
					if (constructor == null) {
						error(EHasNoSuper);
					} else if (!superConstructorAllowed) {
						error(ECustom('Cannot call super constructor outside class constructor'));
					} else {
						f = constructor;
					}
				default:
			}
		}
		
		if (f != Std.string) {
			for (i => arg in args) {
				if (AbstractTools.isAbstract(arg))
					args[i] = arg.__a;
			}
		}
		
		return Reflect.callMethod(o, f, args);
	}
	
	var _constructCache:Map<String, Dynamic> = [];
	inline function cnew( cl : String, args : Array<Dynamic> ) : Dynamic {
		final c:Dynamic = (_constructCache.get(cl) ?? variables.get(cl) ?? imports.get(cl) ?? Tools.resolve(cl, environment));
		
		if (c == null) EUnknownType(cl);
		
		if (!_constructCache.exists(cl)) _constructCache.set(cl, c);
		
		if (canDefer && c is IInsanityType && !c.initialized)
			throw DDefer;
		
		#if hl if (c is Class && c.insanityhlnew != null) return c.insanityhlnew(args); else #end
		
		return Type.createInstance(c, args);
	}
}
