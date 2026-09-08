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
package insanity.tools;

import insanity.backend.Expr;
import insanity.custom.InsanityType;

using insanity.backend.TypeCollection;
using insanity.backend.types.Abstract;
using insanity.Environment;

/**
 * Utility to work with Hscript expressions and classes.
 */
class Tools {
	/**
	 * Calls function `f` on each sub-expression of `e`.
	 * 
	 * If `e` has no sub-expressions, this operation has no effect.
	 * 
	 * Otherwise `f` is called once per sub-expression of `e`, with the sub-expression as argument. These calls are done in order of the sub-expression declarations.
	 * 
	 * This method does not call itself recursively. It should instead be used in a recursive function which handles the expression nodes of interest.
	 * 
	 * @param	e	The expression to iterate.
	 * @param	f	The iterator function.
	 */
	public static function iter( e : Expr, f : Expr -> Void ) { // thats just the haxe api descrption isnt that funny
		switch( expr(e) ) {
		case EConst(_), EIdent(_), EImport(_, _), EUsing(_), EDecl(_):
		case EVar(_, _, e): if( e != null ) f(e);
		case EParent(e): f(e);
		case EBlock(el): for( e in el ) f(e);
		case EField(e, _): f(e);
		case EBinop(_, e1, e2): f(e1); f(e2);
		case EUnop(_, _, e): f(e);
		case ECall(e, args): f(e); for( a in args ) f(a);
		case EIf(c, e1, e2): f(c); f(e1); if( e2 != null ) f(e2);
		case EWhile(c, e): f(c); f(e);
		case EDoWhile(c, e): f(c); f(e);
		case EFor(_, it, e): f(it); f(e);
		case EForGen(it, e): f(it); f(e);
		case EBreak,EContinue:
		case EFunction(_, e, _, _): f(e);
		case EReturn(e): if( e != null ) f(e);
		case EArray(e, i): f(e); f(i);
		case EArrayDecl(el): for( e in el ) f(e);
		case ENew(_,el): for( e in el ) f(e);
		case EThrow(e): f(e);
		case ETry(e, _, _, c): f(e); f(c);
		case EObject(fl): for( fi in fl ) f(fi.e);
		case ETernary(c, e1, e2): f(c); f(e1); f(e2);
		case ESwitch(e, cases, def):
			f(e);
			for( c in cases ) {
				for( v in c.values ) f(v);
				f(c.expr);
			}
			if( def != null ) f(def);
		case EMeta(name, args, e): if( args != null ) for( a in args ) f(a); f(e);
		case ECheckType(e,_): f(e);
		case ECast(e,_): f(e);
		}
	}
	
	/**
	 * Transforms the sub-expressions of `e` by calling `f` on each of them.
	 * 
	 * Otherwise `f` is called once per sub-expression of `e`, with the sub-expression as argument. These calls are done in order of the sub-expression declarations.
	 * 
	 * This method does not call itself recursively. It should instead be used in a recursive function which handles the expression nodes of interest.
	 * 
	 * @param	e	The expression to transform.
	 * @param	f	The transformer function.
	 * @return	`e` transformed. If `e` has no sub-expressions, this operation returns `e` unchanged.
	 */
	public static function map( e : Expr, f : Expr -> Expr ) {
		var edef = switch( expr(e) ) {
		case EConst(_), EIdent(_), EBreak, EContinue, EImport(_, _), EUsing(_), EDecl(_): expr(e);
		case EVar(n, t, e): EVar(n, t, if( e != null ) f(e) else null);
		case EParent(e): EParent(f(e));
		case EBlock(el): EBlock([for( e in el ) f(e)]);
		case EField(e, fi): EField(f(e),fi);
		case EBinop(op, e1, e2): EBinop(op, f(e1), f(e2));
		case EUnop(op, pre, e): EUnop(op, pre, f(e));
		case ECall(e, args): ECall(f(e),[for( a in args ) f(a)]);
		case EIf(c, e1, e2): EIf(f(c),f(e1),if( e2 != null ) f(e2) else null);
		case EWhile(c, e): EWhile(f(c),f(e));
		case EDoWhile(c, e): EDoWhile(f(c),f(e));
		case EFor(v, it, e): EFor(v, f(it), f(e));
		case EForGen(it, e): EForGen(f(it), f(e));
		case EFunction(args, e, name, t): EFunction(args, f(e), name, t);
		case EReturn(e): EReturn(if( e != null ) f(e) else null);
		case EArray(e, i): EArray(f(e),f(i));
		case EArrayDecl(el): EArrayDecl([for( e in el ) f(e)]);
		case ENew(cl,el): ENew(cl,[for( e in el ) f(e)]);
		case EThrow(e): EThrow(f(e));
		case ETry(e, v, t, c): ETry(f(e), v, t, f(c));
		case EObject(fl): EObject([for( fi in fl ) { name : fi.name, e : f(fi.e) }]);
		case ETernary(c, e1, e2): ETernary(f(c), f(e1), f(e2));
		case ESwitch(e, cases, def): ESwitch(f(e), [for( c in cases ) { values : [for( v in c.values ) f(v)], expr : f(c.expr) } ], def == null ? null : f(def));
		case EMeta(name, args, e): EMeta(name, args == null ? null : [for( a in args ) f(a)], f(e));
		case ECheckType(e,t): ECheckType(f(e), t);
		case ECast(e,t): ECast(f(e),t);
		}
		return mk(edef, e.pos);
	}
	
	/**
	 * Gets the `ExprDef` of `e`.
	 * 
	 * @param	e	The expression.
	 * @return	The definition of `e`.
	 */
	public static inline function expr( e : Expr ) : ExprDef {
		return e.e;
	}
	
	/**
	 * Quickly builds an expression from an `ExprDef` and `Position`.
	 * 
	 * @param	e	The definition.
	 * @param	pos	The position.
	 * @return	The new expression.
	 */
	public static inline function mk( e : ExprDef, pos : Position ) : Expr {
		return { e : e, pos: { pmin : pos.pmin, pmax : pos.pmax, origin : pos.origin, line : pos.line, column : pos.column } };
	}
	
	/**
	 * Generates a key/value iterator from an expression.
	 */
	public static inline function getKeyIterator<T>( e : Expr, callb : String -> String -> Expr -> T ) {
		var key = null, value = null, it = e;
		switch( expr(it) ) {
		case EBinop("in", ekv, eiter):
			switch( expr(ekv) ) {
			case EBinop("=>",v1,v2):
				switch( [expr(v1),expr(v2)] ) {
				case [EIdent(v1), EIdent(v2)]:
					key = v1;
					value = v2;
					it = eiter;
				default:
				}
			default:
			}
		default:
		}
		return callb(key,value,it);
	}
	
	/**
	 * Converts a class path to a string.
	 * 
	 * @param	name	The name of the class.
	 * @param	pack	The class' packages.
	 * @return	The resulting string.
	 */
	public static inline function pathToString(name:String, ?pack:Array<String>):String {
		var pack:String = (pack?.join('.') ?? '');
		return (pack.length > 0 ? '$pack.$name' : name);
	}
	
	/**
	 * Checks if an identifier is a valid type identifier.
	 * 
	 * @param	id	The identifier.
	 * @return	Whether the identifier is valid or not.
	 */
	public static inline function isTypeIdentifier(id:String):Bool {
		return (id.charAt(0) == id.charAt(0).toUpperCase());
	}
	
	/**
	 * Resolves a type from a path.
	 * 
	 * Unlike `Type` or `InsanityType`, this should also resolve abstract implementations if they're available.
	 * 
	 * @param	path	The path to the type.
	 * @return	The type, if available.
	 */
	public static inline function resolve(path:String, ?env:Environment):Dynamic {
		var info = (TypeCollection.main.fromPath(path) ?? env?.types.fromPath(path));
		if (info != null) path = TypeCollection.compilePath(info[0]);
		
		var type:Dynamic = env?.resolve(path);
		type ??= AbstractTools.resolve(path);
		type ??= InsanityType.resolveClass(path);
		type ??= InsanityType.resolveEnum(path);
		
		return type;
	}
	
	/**
	 * Indexes types inside a path (as `TypeInfo`).
	 * 
	 * @param	path				The path to search.
	 * @param	fromPack			Whether to index all types from a package or not (from a module).
	 * @param 	canIgnoreWarnings	Deprecated
	 * @param	collection			The `TypeCollection` to search.
	 * @return	The found types, or null if the path doesn't exist.
	 */
	public static inline function listTypes(path:String, fromPack:Bool = false, canIgnoreWarnings:Bool = false, ?collection:TypeCollection):Array<TypeInfo> {
		var typeInfos:Array<TypeInfo> = [];
		
		collection ??= TypeCollection.main;
		if (fromPack) {
			typeInfos = collection.fromPackage(path);
		} else {
			typeInfos = (collection.fromModule(path) ?? collection.fromPath(path) ?? collection.fromCompilePath(path));
		}
		
		if (typeInfos == null) return null;
		
		return [for (type in typeInfos) type];
	}
	
	/**
	 * Indexes types inside a path (as `TypeInfo`) across multiple `TypeCollection`s.
	 * 
	 * @param	path				The path to search.
	 * @param	fromPack			Whether to index all types from a package or not (from a module).
	 * @param 	canIgnoreWarnings	Deprecated
	 * @param	collections			The `TypeCollection`s to search.
	 * @return	The found types, or null if the path doesn't exist.
	 */
	public static inline function listTypesEx(path:String, fromPack:Bool = false, canIgnoreWarnings:Bool = false, collections:Array<TypeCollection>):Array<TypeInfo> {
		var types:Array<TypeInfo> = null;
		
		for (collection in collections) {
			if (collection == null) continue;
			
			var newTypes:Array<TypeInfo> = listTypes(path, fromPack, canIgnoreWarnings, collection);
			if (newTypes == null) continue;
			
			types = (types == null ? newTypes : types.concat(newTypes));
		}
		
		return types;
	}
	
	/**
	 * Converts the type of a field declaration, into a String representation.
	 * 
	 * Only used for interface exceptions.
	 * 
	 * @param	field	The field declaration.
	 * @return	The resulting string.
	 */
	public static function fieldDeclToErrorString(field:FieldDecl):String { // i forgot why i put this one here
		switch (field.kind) {
			case KVar(v):
				if (v.isFinal) return 'final'; // haxe errors with (default,ctor) but i say thats mid
				
				return Printer.varAccessToString(v.get, v.set);
				
			case KFunction(f):
				if (field.access.contains(ADynamic)) return 'dynamic method';
				
				return 'method';
		}
		
		return '???';
	}
}