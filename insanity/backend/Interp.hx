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
import haxe.PosInfos;
import haxe.Constraints.IMap;

private enum Stop {
	SBreak;
	SContinue;
	SReturn;
}

class Interp {
	public var imports : Map<String, Dynamic>;
	public var variables : Map<String,Dynamic>;
	var locals (get, never) : Map<String, {r : Dynamic}>;
	var binops : Map<String, Expr -> Expr -> Dynamic >;
	
	var stack:CallStack;
	
	var inTry : Bool;
	var declared : Array<{ n : String, old : { r : Dynamic } }>;
	var returnValue : Dynamic;

	#if hscriptPos
	var curExpr : Expr;
	#end

	public function new() {
		stack = new CallStack();
		
		imports = new Map();
		declared = new Array();
		resetVariables();
		initOps();
	}

	private function resetVariables(){
		variables = new Map<String,Dynamic>();
		variables.set("null",null);
		variables.set("true",true);
		variables.set("false",false);
		variables.set("trace", Reflect.makeVarArgs(function(el) {
			var inf = posInfos();
			var v = el.shift();
			if( el.length > 0 ) inf.customParams = el;
			haxe.Log.trace(Std.string(v), inf);
		}));
	}

	public function posInfos(): PosInfos {
		#if hscriptPos
			if (curExpr != null)
				return cast { fileName : curExpr.origin, lineNumber : curExpr.line };
		#end
		return cast { fileName : "hscript", lineNumber : 0 };
	}
	
	function get_locals():Map<String, {r: Dynamic}> { return stack.last().locals; }

	function initOps() {
		binops = new Map();
		binops.set("+",function(e1,e2) return expr(e1) + expr(e2));
		binops.set("-",function(e1,e2) return expr(e1) - expr(e2));
		binops.set("*",function(e1,e2) return expr(e1) * expr(e2));
		binops.set("/",function(e1,e2) return expr(e1) / expr(e2));
		binops.set("%",function(e1,e2) return expr(e1) % expr(e2));
		binops.set("&",function(e1,e2) return expr(e1) & expr(e2));
		binops.set("|",function(e1,e2) return expr(e1) | expr(e2));
		binops.set("^",function(e1,e2) return expr(e1) ^ expr(e2));
		binops.set("<<",function(e1,e2) return expr(e1) << expr(e2));
		binops.set(">>",function(e1,e2) return expr(e1) >> expr(e2));
		binops.set(">>>",function(e1,e2) return expr(e1) >>> expr(e2));
		binops.set("==",function(e1,e2) return expr(e1) == expr(e2));
		binops.set("!=",function(e1,e2) return expr(e1) != expr(e2));
		binops.set(">=",function(e1,e2) return expr(e1) >= expr(e2));
		binops.set("<=",function(e1,e2) return expr(e1) <= expr(e2));
		binops.set(">",function(e1,e2) return expr(e1) > expr(e2));
		binops.set("<",function(e1,e2) return expr(e1) < expr(e2));
		binops.set("||",function(e1,e2) return expr(e1) == true || expr(e2) == true);
		binops.set("&&",function(e1,e2) return expr(e1) == true && expr(e2) == true);
		binops.set("=",assign);
		binops.set("...",function(e1,e2) return new IntIterator(expr(e1),expr(e2)));
		binops.set("is",function(e1,e2) return #if (haxe_ver >= 4.2) Std.isOfType #else Std.is #end (expr(e1), expr(e2)));
		binops.set("??",function(e1,e2) return expr(e1) ?? expr(e2));
		assignOp("+=",function(v1:Dynamic,v2:Dynamic) return v1 + v2);
		assignOp("-=",function(v1:Float,v2:Float) return v1 - v2);
		assignOp("*=",function(v1:Float,v2:Float) return v1 * v2);
		assignOp("/=",function(v1:Float,v2:Float) return v1 / v2);
		assignOp("%=",function(v1:Float,v2:Float) return v1 % v2);
		assignOp("&=",function(v1,v2) return v1 & v2);
		assignOp("|=",function(v1,v2) return v1 | v2);
		assignOp("^=",function(v1,v2) return v1 ^ v2);
		assignOp("<<=",function(v1,v2) return v1 << v2);
		assignOp(">>=",function(v1,v2) return v1 >> v2);
		assignOp(">>>=",function(v1,v2) return v1 >>> v2);
		assignOp("??=",function(v1,v2) return v1 ?? v2);
	}

	function setVar( name : String, v : Dynamic ) {
		if (imports.exists(name))
			error(ECustom('Invalid assign'));
		
		if (variables.exists(name)) {
			variables.set(name, v);
		} else {
			error(EUnknownVariable(name));
		}
		
		return v;
	}

	function assign( e1 : Expr, e2 : Expr ) : Dynamic {
		var v = expr(e2);
		switch( Tools.expr(e1) ) {
		case EIdent(id):
			var l = locals.get(id);
			if( l == null )
				setVar(id,v)
			else
				l.r = v;
		case EField(e,f,_):
			v = set(expr(e),f,v);
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			if (isMap(arr)) {
				setMapValue(arr, index, v);
			}
			else {
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
			var l = locals.get(id);
			v = fop(expr(e1),expr(e2));
			if( l == null )
				setVar(id,v)
			else
				l.r = v;
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

	function increment( e : Expr, prefix : Bool, delta : Int ) : Dynamic {
		#if hscriptPos
		curExpr = e;
		var e = e.e;
		#end
		switch(e) {
		case EIdent(id):
			var l = locals.get(id);
			var v : Dynamic = (l == null) ? resolve(id) : l.r;
			if( prefix ) {
				v += delta;
				if( l == null ) setVar(id,v) else l.r = v;
			} else
				if( l == null ) setVar(id,v + delta) else l.r = v + delta;
			return v;
		case EField(e,f,_):
			var obj = expr(e);
			var v : Dynamic = get(obj,f);
			if( prefix ) {
				v += delta;
				set(obj,f,v);
			} else
				set(obj,f,v + delta);
			return v;
		case EArray(e, index):
			var arr:Dynamic = expr(e);
			var index:Dynamic = expr(index);
			if (isMap(arr)) {
				var v = getMapValue(arr, index);
				if (prefix) {
					v += delta;
					setMapValue(arr, index, v);
				}
				else {
					setMapValue(arr, index, v + delta);
				}
				return v;
			}
			else {
				var v = arr[index];
				if( prefix ) {
					v += delta;
					arr[index] = v;
				} else
					arr[index] = v + delta;
				return v;
			}
		default:
			return error(EInvalidOp((delta > 0)?"++":"--"));
		}
	}

	public function execute( expr : Expr ) : Dynamic {
		try {
			stack.stack.resize(0);
			declared = new Array();
			
			return exprReturn(expr);
		} catch (e:haxe.Exception) {
			if (e is InterpException) {
				throw e;
			} else {
				pushStack();
				
				throw new InterpException(stack, e.message);
			}
		}
		
		return null;
	}

	function exprReturn(e) : Dynamic {
		try {
			return expr(e);
		} catch( e : Stop ) {
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

	function duplicate<T>( h : Map<String,T> ) {
		var h2 = new Map();
		for (k => v in h) h2.set(k, v);
		return h2;
	}
	
	function pushStack(?item:StackItem, ?locals:Map<String, {r:Dynamic}>) {
		var last:Stack = stack.stack.shift();
		
		if (last != null) stack.stack.unshift({locals: last.locals, item: SFilePos(last.item, curExpr.origin, curExpr.line, curExpr.column)});
		if (item != null) stack.stack.unshift({locals: locals ?? new Map(), item: item});
	}

	function restore( old : Int ) {
		while( declared.length > old ) {
			var d = declared.pop();
			locals.set(d.n,d.old);
		}
	}

	inline function error(e : Error, rethrow=false ) : Dynamic {
		pushStack();
		
		var exception:InterpException = new InterpException(stack, Printer.errorToString(e));
		if ( rethrow ) this.rethrow(exception) else throw exception;
		
		return null;
	}

	inline function rethrow( e : Dynamic ) {
		#if hl
		hl.Api.rethrow(e);
		#else
		throw e;
		#end
	}

	function resolve( id : String ) : Dynamic {
		if (imports.exists(id))
			return imports.get(id);
		
		var v = variables.get(id);
		if( v == null && !variables.exists(id) )
			error(EUnknownVariable(id));
		
		return v;
	}

	public function expr( e : Expr, ?t : CType ) : Dynamic {
		#if hscriptPos
		curExpr = e;
		var e = e.e;
		#end
		
		if (stack.length == 0)
			pushStack(SScript(curExpr.origin));
		
		switch( e ) {
		case EImport(path, mode):
			var id:String;
			
			switch (mode) {
				case INormal:
					id = path.substr(path.lastIndexOf('.') + 1);
				case IAsName(alias):
					id = alias;
				case IAll:
					trace('Wildcard is currently unsupported');
					return null;
			}
			
			var type:Dynamic = Tools.resolve(path);
			if (type == null) error(EUnknownType(path));
			
			imports.set(id, type);
		case EConst(c):
			switch( c ) {
			case CInt(v): return v;
			case CFloat(f): return f;
			case CString(s): return s;
			}
		case EIdent(id):
			var l = locals.get(id);
			if( l != null )
				return l.r;
			return resolve(id);
		case EVar(n,t,e):
			declared.push({ n : n, old : locals.get(n) });
			locals.set(n,{ r : (e == null)?null:expr(e, t) });
			return null;
		case EParent(e):
			return expr(e);
		case EBlock(exprs):
			var old = declared.length;
			var v = null;
			for( e in exprs )
				v = expr(e);
			restore(old);
			return v;
		case EField(e,f,m):
			return get(expr(e),f,m);
		case EBinop(op,e1,e2):
			var fop = binops.get(op);
			if( fop == null ) error(EInvalidOp(op));
			return fop(e1,e2);
		case EUnop(op,prefix,e):
			switch(op) {
			case "!":
				return expr(e) != true;
			case "-":
				return -expr(e);
			case "++":
				return increment(e,prefix,1);
			case "--":
				return increment(e,prefix,-1);
			case "~":
				return ~expr(e);
			default:
				error(EInvalidOp(op));
			}
		case ECall(e,params):
			var args = new Array();
			for( p in params )
				args.push(expr(p));

			switch( Tools.expr(e) ) {
				case EField(e,f,m):
					var obj = expr(e);
					if ( obj == null ) {
						if (m) return null;
						error(EInvalidAccess(f));
					}
					return fcall(obj,f,args);
				default:
					return call(null,expr(e),args);
			}
		case EIf(econd,e1,e2):
			return if( expr(econd) == true ) expr(e1) else if( e2 == null ) null else expr(e2);
		case EWhile(econd,e):
			whileLoop(econd,e);
			return null;
		case EDoWhile(econd,e):
			doWhileLoop(econd,e);
			return null;
		case EFor(v,it,e):
			forLoop(v,it,e);
			return null;
		case EForGen(it,e):
			Tools.getKeyIterator(it, function(vk,vv,it) {
				if( vk == null ) {
					#if hscriptPos
					curExpr = it;
					#end
					error(ECustom("Invalid for expression"));
					return;
				}
				forKeyValueLoop(vk,vv,it,e);
			});
			return null;
		case EBreak:
			throw SBreak;
		case EContinue:
			throw SContinue;
		case EReturn(e):
			returnValue = e == null ? null : expr(e);
			throw SReturn;
		case EFunction(params,fexpr,name,_,id):
			var capturedLocals = duplicate(locals);
			var hasOpt = false, minParams = 0;
			for( p in params )
				if( p.opt )
					hasOpt = true;
				else
					minParams++;
			var f = function(args:Array<Dynamic>) {
				if( args?.length ?? 0 != params.length ) {
					if( args.length < minParams ) {
						var str = "Invalid number of parameters. Got " + args.length + ", required " + minParams;
						if( name != null ) str += " for function '" + name+"'";
						error(ECustom(str));
					}
					// make sure mandatory args are forced
					var args2 = [];
					var extraParams = args.length - minParams;
					var pos = 0;
					for( p in params )
						if( p.opt ) {
							if( extraParams > 0 ) {
								args2.push(args[pos++]);
								extraParams--;
							} else {
								args2.push(p.value == null ? null : expr(p.value));
							}
						} else
							args2.push(args[pos++]);
					args = args2;
				}
				var old = locals;
				pushStack(name == null ? SLocalFunction(id) : SMethod(curExpr.origin, name), duplicate(capturedLocals));
				for( i in 0...params.length )
					locals.set(params[i].name,{ r : args[i] });
				var r = null;
				if( inTry )
					try {
						r = exprReturn(fexpr);
					} catch( e : Dynamic ) {
						stack.stack.shift();
						#if neko
						neko.Lib.rethrow(e);
						#else
						throw e;
						#end
					}
				else
					r = exprReturn(fexpr);
				stack.stack.shift();
				return r;
			};
			var f = Reflect.makeVarArgs(f);
			if( name != null ) {
				if( stack.length > 1 ) {
					// function-in-function is a local function
					declared.push( { n : name, old : locals.get(name) } );
					var ref = { r : f };
					locals.set(name, ref);
					capturedLocals.set(name, ref); // allow self-recursion
				} else {
					// global function
					variables.set(name, f);
				}
			}
			return f;
		case EArrayDecl(arr):
			if ( arr.length > 0 && Tools.expr(arr[0]).match(EBinop("=>", _)) ) { // infer from keys ...
				var keys = [];
				var values = [];
				for( e in arr ) {
					switch(Tools.expr(e)) {
					case EBinop("=>", eKey, eValue):
						keys.push(expr(eKey));
						values.push(expr(eValue));
					default:
						#if hscriptPos
						curExpr = e;
						#end
						error(ECustom("Invalid map key=>value expression"));
					}
				}
				return makeMap(keys,values);
			} else { // infer from type declaration ... (empty map)
				switch (t) {
					case CTPath(path, params): // hell
						var fullPath:String = path.join('.');
						
						if (fullPath == 'Map') { // infer from parameters
							if (params == null || params.length < 2) error(ECustom('Not enough type parameters for Map')); // we dont really care about the value type , but whatever
							else if (params.length > 2) error(ECustom('Too many type parameters for Map'));
							
							switch (params[0]) {
								case CTPath(path, _):
									var fullPath:String = path.join('.');
									
									if (fullPath == 'String') {
										return new Map<String, Dynamic>();
									} else if (fullPath == 'Int') {
										return new Map<Int, Dynamic>();
									} else {
										var type = (Tools.resolve(fullPath) ?? imports.get(fullPath));
										
										if (type is Class) {
											return new haxe.ds.ObjectMap<Dynamic, Dynamic>();
										} else if (type is Enum) {
											return new haxe.ds.EnumValueMap<Dynamic, Dynamic>();
										} else {
											error(EUnknownType(type));
										}
									}
								default:
									error(ECustom('What'));
							}
						}
						
						var type = (Tools.resolve(fullPath) ?? imports.get(fullPath));
						if (type != null && type is IMap)
							return Type.createInstance(type, []);
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
			if( isMap(arr) )
				return getMapValue(arr, index);
			return arr[index];
		case ENew(cl,params):
			var a = new Array();
			for( e in params )
				a.push(expr(e));
			return cnew(cl,a);
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
			var o = {};
			for( f in fl )
				set(o,f.name,expr(f.e));
			return o;
		case ETernary(econd,e1,e2):
			return if( expr(econd) == true ) expr(e1) else expr(e2);
		case ESwitch(e, cases, def):
			var val : Dynamic = expr(e);
			var match = false;
			for( c in cases ) {
				for( v in c.values )
					if( expr(v) == val ) {
						match = true;
						break;
					}
				if( match ) {
					val = expr(c.expr);
					break;
				}
			}
			if( !match )
				val = def == null ? null : expr(def);
			return val;
		case EMeta(meta, args, e):
			return exprMeta(meta, args, e);
		case ECheckType(e,_), ECast(e,_):
			return expr(e);
		}
		return null;
	}

	function exprMeta(meta,args,e) : Dynamic {
		return expr(e);
	}

	function doWhileLoop(econd,e) {
		var old = declared.length;
		do {
			if( !loopRun(() -> expr(e)) )
				break;
		}
		while( expr(econd) == true );
		restore(old);
	}

	function whileLoop(econd,e) {
		var old = declared.length;
		while( expr(econd) == true ) {
			if( !loopRun(() -> expr(e)) )
				break;
		}
		restore(old);
	}

	function makeIterator( v : Dynamic ) : Iterator<Dynamic> {
		#if js
		// don't use try/catch (very slow)
		if( v is Array )
			return (v : Array<Dynamic>).iterator();
		if( v.iterator != null ) v = v.iterator();
		#else
		#if (cpp) if ( v.iterator != null ) #end
			try v = v.iterator() catch( e : Dynamic ) {};
		#end
		if( v.hasNext == null || v.next == null ) error(EInvalidIterator(v));
		return v;
	}

	function makeKeyValueIterator( v : Dynamic ) : KeyValueIterator<Dynamic,Dynamic> {
		#if js
		// don't use try/catch (very slow)
		if( v is Array )
			return (v : Array<Dynamic>).keyValueIterator();
		if( v.keyValueIterator != null ) v = v.keyValueIterator();
		#else
		try v = v.keyValueIterator() catch( e : Dynamic ) {};
		#end
		if( v.hasNext == null || v.next == null ) error(EInvalidIterator(v));
		return v;
	}

	function forLoop(n,it,e) {
		var old = declared.length;
		declared.push({ n : n, old : locals.get(n) });
		var it = makeIterator(expr(it));
		while( it.hasNext() ) {
			locals.set(n,{ r : it.next() });
			if( !loopRun(() -> expr(e)) )
				break;
		}
		restore(old);
	}

	function forKeyValueLoop(vk,vv,it,e) {
		var old = declared.length;
		declared.push({ n : vk, old : locals.get(vk) });
		declared.push({ n : vv, old : locals.get(vv) });
		var it = makeKeyValueIterator(expr(it));
		while( it.hasNext() ) {
			var v = it.next();
			locals.set(vk,{ r : v.key });
			locals.set(vv,{ r : v.value });
			if( !loopRun(() -> expr(e)) )
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
			isAllEnum = isAllEnum && Reflect.isEnumValue(key);
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

	function get( o : Dynamic, f : String, maybe : Bool = false ) : Dynamic {
		if ( o == null ) {
			if (!maybe) {
				error(EInvalidAccess(f));
			} else {
				return null;
			}
		}
		return {
			#if php
				// https://github.com/HaxeFoundation/haxe/issues/4915
				try {
					Reflect.getProperty(o, f);
				} catch (e:Dynamic) {
					Reflect.field(o, f);
				}
			#else
				Reflect.getProperty(o, f);
			#end
		}
	}

	function set( o : Dynamic, f : String, v : Dynamic ) : Dynamic {
		if( o == null ) error(EInvalidAccess(f));
		Reflect.setProperty(o,f,v);
		return v;
	}

	function fcall( o : Dynamic, f : String, args : Array<Dynamic> ) : Dynamic {
		var fun = get(o, f);
		
		if (!Reflect.isFunction(fun)) error(ECustom('Cannot call $fun'));
		
		return call(o, fun, args);
	}

	function call( o : Dynamic, f : Dynamic, args : Array<Dynamic> ) : Dynamic {
		return Reflect.callMethod(o,f,args);
	}

	function cnew( cl : String, args : Array<Dynamic> ) : Dynamic {
		var c = Type.resolveClass(cl);
		if( c == null ) c = resolve(cl);
		return Type.createInstance(c,args);
	}

}
