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

using StringTools;
using insanity.backend.Tools;
using insanity.backend.types.Abstract;
using insanity.backend.macro.TypeRegistry;

enum Stop {
	SBreak;
	SContinue;
	SReturn;
}

typedef Variable = {
	var r:Dynamic;
	var ?a:InsanityAbstract;
}

class Interp {
	public var usings : Array<Class<Dynamic>>;
	public var imports : Map<String, Dynamic>;
	public var variables : Map<String,Dynamic>;
	
	var locals (get, never) : Map<String, Variable>;
	var binops : Map<String, Expr -> Expr -> Dynamic >;
	
	public var callStackDepth : Int = 200;
	var stack : CallStack;
	
	var inTry : Bool;
	var declared : Array<{ n : String, old : Variable }>;
	var returnValue : Dynamic;
	
	var curExpr : Expr;

	public function new() {
		stack = new CallStack();
		
		declared = new Array();
		setDefaults();
		initOps();
	}

	public function setDefaults() {
		imports ??= new Map();
		usings ??= new Array();
		variables ??= new Map<String, Dynamic>();
		
		imports.clear();
		usings.resize(0);
		variables.clear();
		
		for (type in Tools.listTypes('', true, true)) // import all bottom level classes
			imports.set(type.name, type.resolve());
		
		variables.set('null', null);
		variables.set('true', true);
		variables.set('false', false);
		variables.set('trace', Reflect.makeVarArgs(function(el) {
			var inf = posInfos();
			var v = el.shift();
			if (el.length > 0) inf.customParams = el;
			haxe.Log.trace(Std.string(v), inf);
		}));
	}

	public function posInfos(): PosInfos {
		return cast { fileName : (curExpr?.origin ?? 'hscript'), lineNumber : (curExpr?.line ?? 0) };
	}
	
	function get_locals():Map<String, Variable> { return stack.last().locals; }

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
		var iv = imports.get(name);
		if (iv != null) {
			if (iv is Mirror) {
				switch (iv) {
					case MProperty(t, f): 
						Reflect.setProperty(t, f, v);
						return v;
					default:
				}
			}
			
			error(ECustom('Invalid assign'));
		}
		
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
		curExpr = e;
		var e = e.e;
		
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
	
	function pushStack(?item:StackItem, ?locals:Map<String, Variable>) {
		var last:Stack = stack.stack.shift();
		
		if (last != null)
			stack.stack.unshift({locals: last.locals, item: SFilePos(last.item, curExpr.origin, curExpr.line, curExpr.column)});
		if (item != null) {
			stack.stack.unshift({locals: locals ?? new Map(), item: item});
			
			if (stack.length > callStackDepth)
				error(ECustom('Stack overflow'));
		}
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
	
	function createEnum(t:Enum<Dynamic>, i:Int, ?args:Array<Dynamic>):EnumValue {
		try {
			return Type.createEnumIndex(t, i, args);
		} catch (e:haxe.Exception) {
			throw 'Failed to construct enum of type ${Type.getEnumName(t)}';
		}
	}
	
	function createAbstractEnum(t:Class<InsanityAbstract>, i:Int):Class<InsanityAbstract> {
		try {
			return AbstractTools.createEnumIndex(t, i);
		} catch (e:haxe.Exception) {
			var t:Dynamic = t;
			throw 'Failed to construct enum of type ${t.impl}';
		}
	}

	function resolve(id:String, calling:Bool = false) : Dynamic {
		if (imports.exists(id)) {
			var v:Dynamic = imports.get(id);
			
			if (v == null) {
				error(ECustom('Module $id does not define type $id'));
			} else if (v is Mirror) {
				switch (v) {
					case MProperty(t, f): 
						return Reflect.getProperty(t, f);
					case MEnumValue(t, i):
						if (calling) return Reflect.makeVarArgs(function(params:Array<Dynamic>) return createEnum(t, i, params));
						return createEnum(t, i);
					case MAbstractEnumValue(t, i):
						return createAbstractEnum(t, i);
				}
			}
			
			return v;
		}
		
		var v = variables.get(id);
		if( v == null && !variables.exists(id) )
			error(EUnknownVariable(id));
		
		return v;
	}
	
	function importType(name:String, t:Dynamic) {
		if (t is Class) {
			if (Type.getSuperClass(t) == InsanityAbstract && t.isEnum) {
				for (i => construct in AbstractTools.getEnumConstructs(t))
					imports.set(construct, MAbstractEnumValue(t, i));
				imports.set(name, t);
				return;
			}
			
			imports.set(name, t);
		} else if (t is Enum) {
			imports.set(name, t);
			importEnumValues(t);
		} else {
			throw 'Invalid import type $t';
		}
	}
	
	function importEnumValues(t:Enum<Dynamic>) {
		for (i => v in Type.getEnumConstructs(t))
			imports.set(v, MEnumValue(t, i));
	}
	
	function importPath(path:Array<String>, mode:ImportMode):Void {
		if (mode == IAll) {
			var fullPath:String = path.join('.');
			var types:Array<TypeInfo> = Tools.listTypes(fullPath, true);
			
			if (types == null) return;
			
			imports.set(fullPath.substr(fullPath.lastIndexOf('.') + 1), null);
			for (type in types) {
				if (type.name.indexOf('_Impl_') > -1 || type.name.startsWith('InsanityAbstract_')) continue;
				
				importType(type.name, type.kind == 'abstract' ? AbstractTools.resolve(type.compilePath()) : type.resolve());
			}
			
			return;
		}
		
		var fields:Array<String> = [];
		
		var i:Int = path.length;
		while (i -- > 0) {
			var fullPath:String = path.slice(0, i + 1).join('.');
			
			if (path[i].isTypeIdentifier()) {
				var types:Array<TypeInfo> = Tools.listTypes(fullPath);
				
				if (types != null) {
					var field:String = fields.shift();
					if (fields.length > 0) error(EUnexpected(field));
					
					if (field != null) {
						var t:Dynamic = null;
						for (type in types) {
							if (type.name == path[i]) {
								t = type.resolve();
								break;
							}
						}
						
						if (t is Class) {
							if (!Type.getClassFields(t).contains(field))
								error(ECustom('Module ${path[i]} does not define field $field'));
							
							switch (mode) {
								case IAsName(alias): imports.set(alias, MProperty(t, field));
								default: imports.set(field, MProperty(t, field));
							}
						} else if (t is Enum) {
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
									importType(alias, type.resolve());
									
									return;
								}
							}
							
							error(ECustom('Module ${path[i]} does not define ${path[i]}'));
							
						default:
							imports.set(path[i], null);
							
							for (type in types) {
								if (type.name.indexOf('_Impl_') > -1) continue;
								
								importType(type.name, type.kind == 'abstract' ? AbstractTools.resolve(type.compilePath()) : type.resolve());
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
				var types:Array<TypeInfo> = Tools.listTypes(fullPath);
				
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

	public function expr( e : Expr, ?t : CType, calling:Bool = false ) : Dynamic {
		curExpr = e;
		var e = e.e;
		
		if (stack.length == 0)
			pushStack(SScript(curExpr.origin));
		
		switch( e ) {
		case EUsing(path):
			usingType(path);
		case EImport(path, mode):
			importPath(path, mode);
		case EConst(c):
			switch( c ) {
			case CInt(v): return v;
			case CFloat(f): return f;
			case CString(s): return s;
			}
		case EIdent(id):
			var l = locals.get(id);
			if( l != null ) {
				if (l.a != null)
					return l.a;
				return l.r;
			}
			return resolve(id, calling);
		case EVar(n,t,e):
			var ne:Dynamic = (e == null ? null : expr(e, t));
			
			declared.push({ n : n, old : locals.get(n) });
			
			if (AbstractTools.isAbstract(ne)) {
				locals.set(n,{ r : ne.__a, a: ne });
			} else {
				locals.set(n,{ r : ne });
			}
			
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
					var obj = expr(e, true);
					if ( obj == null ) {
						if (m) return null;
						error(EInvalidAccess(f));
					}
					return fcall(obj,f,args);
				default:
					return call(null,expr(e, true),args);
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
					curExpr = it;
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
		case EFunction(params,fexpr,name,ret,id):
			var capturedLocals = duplicate(locals);
			var hasOpt = false, hasRest = false, minParams = 0;
			for( p in params )
				if (p.opt) {
					hasOpt = true;
				} else if (p.rest) {
					hasRest = true;
				} else {
					minParams++;
				}
			var f = Reflect.makeVarArgs(function(args:Array<Dynamic>) {
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
					for( p in params ) {
						if (p.rest) {
							if (pos < args.length)
								args2.push(args[pos++]);
						} else if( p.opt ) {
							if( extraParams > 0 ) {
								args2.push(args[pos++]);
								extraParams--;
							} else {
								args2.push(p.value == null ? null : expr(p.value));
							}
						} else
							args2.push(args[pos++]);
					}
					if (hasRest)
						args2 = args2.concat(args.slice(params.length));
					args = args2;
				}
				var old = locals;
				pushStack(name == null ? SLocalFunction(id) : SMethod(curExpr.origin, name), duplicate(capturedLocals));
				for( i in 0...params.length ) {
					if (i == params.length - 1 && hasRest) {
						locals.set(params[i].name, {r: args.slice(params.length - 1)});
					} else {
						locals.set(params[i].name, {r: tryCast(args[i], params[i].t)});
					}
				}
				var r = null;
				if( inTry )
					try {
						r = tryCast(exprReturn(fexpr), ret);
					} catch( e : Dynamic ) {
						stack.stack.shift();
						#if neko
						neko.Lib.rethrow(e);
						#else
						throw e;
						#end
					}
				else {
					r = tryCast(exprReturn(fexpr), ret);
				}
				stack.stack.shift();
				return r;
			});
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
						curExpr = e;
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
										var r = (Tools.resolve(fullPath) ?? imports.get(fullPath));
										if (r is Class) {
											type = TypeRegistry.fromCompilePath(Type.getClassName(r))[0];
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
						}
						
						var p = new Printer();
						error(ECustom('Map of type <${p.typeToString(params[0])}, ${p.typeToString(params[1])}> is not accepted'));
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
			throw new InterpException(stack, expr(e));
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
		case ECast(e, t):
			return tryCast(expr(e), t);
		case ECheckType(e,_):
			return expr(e);
		}
		return null;
	}
	
	function tryCast(e, ?type):Dynamic {
		switch (type) {
			case CTPath(p, _):
				var path = p.join('.');
				var t = imports.get(path);
				
				if (t == null) {
					var info = TypeRegistry.fromPath(path);
					if (info != null)
						t = info[0].compilePath().resolve();
				}
				
				if (t == null) throw 'Type not found: $path';
				
				if (Type.getSuperClass(t) == InsanityAbstract) {
					return Type.createInstance(t, [t.resolveFrom(e)]);
				} else {
					var c:Dynamic = Type.getClass(e);
					if (c != null && Type.getSuperClass(c) == InsanityAbstract) {
						var r = e.resolveTo(Type.getClassName(t));
						if (r == null) throw 'Can\'t cast ${c.impl} to $path';
						else return r;
					}
				}
				
			default:
		}
		
		return e;
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
		if (AbstractTools.isAbstract(v))
			v = v.__a;
		
		if( o == null ) error(EInvalidAccess(f));
		Reflect.setProperty(o,f,v);
		return v;
	}

	function fcall( o : Dynamic, f : String, args : Array<Dynamic> ) : Dynamic {
		var fun = get(o, f);
		
		if (o != Std || f != 'string') { // dirty solution but Yeah what ever
			for (i => arg in args)
				args[i] = (AbstractTools.isAbstract(arg) ? arg.__a : arg);
		}
		
		if (!Reflect.isFunction(fun)) {
			for (t in usings) {
				var fun = get(t, f, true);
				if (Reflect.isFunction(fun)) {
					try {
						args.unshift(o);
						return Reflect.callMethod(t, fun, args);
					} catch (e:Dynamic) {}
				}
			}
			
			error(ECustom('Cannot call $fun'));
		}
		
		return call(o, fun, args);
	}

	function call( o : Dynamic, f : Dynamic, args : Array<Dynamic> ) : Dynamic {
		if (f != Std.string) {
			for (i => arg in args)
				args[i] = (AbstractTools.isAbstract(arg) ? arg.__a : arg);
		}
		
		return Reflect.callMethod(o,f,args);
	}

	function cnew( cl : String, args : Array<Dynamic> ) : Dynamic {
		var c = Type.resolveClass(cl);
		if( c == null ) c = resolve(cl);
		return Type.createInstance(c,args);
	}

}
