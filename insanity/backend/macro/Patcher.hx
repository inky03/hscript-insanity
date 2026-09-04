package insanity.backend.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;
using StringTools;
using Lambda;

/**
 * Utility macro functions that patch classes to boost their use with Hscript.
 */
class Patcher {
	/**
	 * Patches classes that use `Reflect` and `Type` to use HscriptInsanity's implementations.
	 * Use this with `Compiler.addMetadata` or `Compiler.addGlobalMetadata`!
	 * 
	 * Note using this may impact performance to some degree!!!
	 * 
	 * @param	extreme		If true, additionally turns Class<T> and Enum<T> into simply Dynamics
	 * 						(which can allow scripted classes/enums to be passed to variables and constructed subsequently).
	 * 						Note this will NOT work with every class.
	 * @return	Context fields
	 */
	public static macro function patch(extreme:Bool = false):Array<Field> {
		var fields:Array<Field> = Context.getBuildFields();
		var cls:ClassType = Context.getLocalClass()?.get();
		
		if (cls == null || cls.meta.has(':insanityhl')) return fields;
		switch (cls.pack[0]) {
			case 'haxe' | 'hl' | 'cpp' | 'neko' | 'js' | 'cs' | 'lua' | 'php' | 'macro' | 'java' | 'flash' | 'python' | 'insanity': return fields;
			case null: return fields;
			default:
		}
		
		function mapPatch(expr:Expr):Expr {
			return switch(expr.expr) {
				case EIs(expr, type):
					var pack:Array<String> = [];
					switch (type) {
						default:
							return expr;
						case TPath(p):
							pack = p.pack.copy();
							pack.push(p.name);
					}
					macro insanity.custom.InsanityStd.isOfType($expr, $p{pack});
				case EField({pos: _, expr: EConst(CIdent('Std'))}, 'isOfType', Normal): macro insanity.custom.InsanityStd.isOfType;
				case EConst(CIdent('Reflect')): macro insanity.custom.InsanityReflect;
				case EConst(CIdent('Type')): macro insanity.custom.InsanityUnsafeType;
				/* case EConst(CIdent('Std')): macro insanity.custom.InsanityStd;
				bad performance issues ineed to resolve ? (either way not much point of using this one outside scripts ig)*/
				default: expr.map(mapPatch);
			}
		}
		
		function mapType(t:ComplexType):ComplexType {
			if (t == null) return null;
			
			var t = switch (t) {
				case TPath(p) if (p.name == 'Class'): TPath({sub: 'InsanityClass', name: 'Patcher', pack: ['insanity', 'backend', 'macro'], params: p.params});
				case TPath(p) if (p.name == 'Enum'): TPath({sub: 'InsanityEnum', name: 'Patcher', pack: ['insanity', 'backend', 'macro'], params: p.params});
				default: t;
			}
			
			return t;
		}
		
		for (field in fields) {
			field.kind = switch (field.kind) {
				case FProp(get, set, type, expr):
					FProp(get, set, extreme ? mapType(type) : type, expr?.map(mapPatch));
					
				case FVar(type, expr):
					FVar(extreme ? mapType(type) : type, expr?.map(mapPatch));
					
				case FFun(fun):
					if (extreme) for (i => arg in fun.args) fun.args[i].type = mapType(arg.type);
					fun.expr = fun.expr?.map(mapPatch);
					FFun(fun);
			}
		}
		
		return fields;
	}
	
	/**
	 * Builds a copy (to preserve performance) of a HashLink class for Hscript, to fix accessing properties or functions with `@:hlNative` in Hscript!
	 * Pair with `Config`!
	 * 
	 * @return	Context fields
	 */
	public static macro function buildHLClass(e:Expr):Array<Field> {
		var pos = Context.currentPos();
		var fields:Array<Field> = Context.getBuildFields();
		
		var cls = switch (Context.getType(e.toString())) {
			case TInst(t, _):
				t.get();
			default:
				throw 'Not a class';
		}
		
		Context.getLocalClass().get().meta.add(':insanityhl', [], pos);
		
		var statics:Array<ClassField> = cls.statics.get();
		for (field in statics) {
			var f:String = field.name;
			
			switch (field.kind) {
				case FVar(r, w):
					var t = field.type.toComplexType();
					fields.push({
						pos: pos, name: f, access: [APublic, AStatic],
						kind: FProp('get', 'never', t, null)
					});
					fields.push({
						pos: pos, name: 'get_$f', access: [APublic, AStatic],
						kind: FFun({
							args: [],
							ret: t,
							expr: macro return $e.$f
						})
					});
					
				case FMethod(m):
					var args = null, ret = null; // should put all this stuff in one class instead of repeating code i think ... todo
					
					switch (field.type) {
						default:
						case TFun(aargs, rret): args = aargs; ret = rret;
						case TLazy(lazy):
							switch (lazy()) {
								default: continue;
								case TFun(aargs, rret): args = aargs; ret = rret;
							}
					}
					
					var defaults:Array<Expr> = [];
					switch (field.expr().expr) {
						default:
						case TFunction(fun):
							for (arg in fun.args) {
								if (arg.value == null) {
									defaults.push(null);
									continue;
								}
								var expr = Context.getTypedExpr(arg.value);
								defaults.push(macro cast $expr);
							}
					}
					
					var argsArray:Array<Expr> = [for (arg in args) macro $i {arg.name}];
					
					fields.push({
						pos: pos, name: f, access: [APublic, AStatic],
						kind: FFun({
							args: [for (i => arg in args) {
								var defaultValue:Expr = defaults[i];
								
								{
									name: arg.name,
									value: defaultValue,
									opt: (defaultValue == null ? arg.opt : null),
									type: (defaultValue == null ? arg.t.toComplexType() : null)
								}
							}],
							ret: ret.toComplexType(),
							expr: macro return $e.$f($a {argsArray})
						})
					});
			}
		}
		
		return fields;
	}
	
	/**
	 * Creates copies of long methods (of 9+ arguments) in HashLink, to fix a "Too many arguments" error.
	 * For internal use (this is already called by the library when targetting HashLink automatically!)
	 * 
	 * @return	Context fields
	 */
	public static macro function fixHLLongMethods():Array<Field> {
		var fields:Array<Field> = Context.getBuildFields();
		
		if (!Context.defined('hl')) return fields;
		
		var pos = Context.currentPos();
		var type = Context.getLocalType();
		var cls:ClassType = Context.getLocalClass()?.get();
		
		if (cls == null) return fields;
		if (cls.meta.has(':hlNative') || cls.meta.has(':insanityScripted') || cls.name.indexOf('_Impl_') != -1 || cls.isInterface) return fields;
		
		function createHLExpr(name:String, args:Array<FunctionArg>, isStatic:Bool):Expr {
			final callArgs:Array<Expr> = [for (i => arg in args) {
				(!arg.opt && arg.value == null) ? macro arguments[$v {i}] : macro arguments[$v {i}] ?? $e {arg.value ?? macro null}
			}];
			// i forgot expr reification was a thing until like 10 minutes ago ... so cool ...
			
			if (name == 'new') return macro return $e {{pos: pos, expr: ENew({pack: cls.pack, name: cls.name}, callArgs)}};
			
			return macro return $i {isStatic ? cls.name : 'this'}.$name($a {callArgs});
		}
		
		for (field in fields) {
			switch (field.kind) {
				default:
				case FFun(fun) if (fun.args.length >= 9):
					// trace('fix ${cls.module+'.'+cls.name}.${field.name}');
					
					final funName:String = 'insanityhl${field.name}';
					final access:Array<Access> = (field.access?.copy() ?? []);
					
					if (fields.exists((field:Field) -> field.name == funName) || field.meta?.exists((meta:MetadataEntry) -> meta.name == ':hlNative'))
						continue;
					
					access.remove(APublic);
					fields.push({
						pos: pos,
						meta: field.meta?.copy(),
						access: access,
						name: funName,
						
						kind: FFun({
							params: fun.params?.copy(),
							args: [{opt: false, name: 'arguments', type: macro:Array<Dynamic>}],
							expr: createHLExpr(field.name, fun.args, access.contains(AStatic))
						})
					});
					
					if (field.name == 'new') access.push(AStatic);
			}
		}
		
		return fields;
	}
	
	/**
	 * 
	 */
	public static macro function buildHscript(exclude:Array<String>):Array<Field> {
		var fields:Array<Field> = Context.getBuildFields();
		var cls:ClassType = Context.getLocalClass()?.get();
		var pos = Context.currentPos();
		
		if (Context.defined('display')) return fields;
		if (cls == null || cls.meta.has(':coreApi') || cls.meta.has(':extern') || cls.meta.has(':hlNative') || cls.meta.has(':native') ||
			cls.isInterface || cls.isExtern || cls.name.contains('_Fields_'))
			return fields;
		switch (cls.pack[0]) {
			case 'haxe' | 'hl' | 'cpp' | 'neko' | 'js' | 'cs' | 'lua' | 'php' | 'macro' | 'java' | 'flash' | 'python': return fields;
			case 'insanity' if (cls.name != 'InsanityDummyClass'): return fields;
			default:
		}
		switch (cls.kind) {
			case KAbstractImpl(_): return fields;
			default:
		}
		for (ex in exclude) {
			if (cls.module.indexOf(ex) == 0)
				return fields;
		}
		
		function classHasConstructor(ccls:ClassType):Bool {
			var constr:ClassField = ccls?.constructor?.get();
			
			if (constr == null) return false;
			
			/* i fgiured out a class without a constructor FOR ITSELF actualy just uses the same pos as the entire class . kinda dirty but it gets the job done
			(checking for .constructor isnt enough since haxe fills it in automatically?) */
			return (Std.string(ccls.pos) != Std.string(constr.pos));
		}
		
		var lastClassWithConstr:Null<ClassType> = (classHasConstructor(cls) ? cls : null);
		var hasConstructor:Bool = false;
		
		var superClass = cls.superClass?.t.get();
		var su = superClass;
		
		while (true) {
			if (su == null) break;
			if (su.isExtern || su.meta.has(':coreApi') || su.meta.has(':extern') || su.meta.has(':hlNative') || su.meta.has(':native')) return fields;
			
			switch (su.pack[0]) {
				case 'haxe' | 'hl' | 'cpp' | 'neko' | 'js' | 'cs' | 'lua' | 'php' | 'macro' | 'java' | 'flash' | 'python' | 'insanity': return fields;
				default:
			}
			for (ex in exclude) {
				if (su.module.indexOf(ex) == 0)
					return fields;
			}
			
			lastClassWithConstr ??= (classHasConstructor(su) ? su : null);
			
			su = su?.superClass?.t.get();
		}
		
		var expr:Array<Expr> = [];
		var constrArgs:Array<FunctionArg> = [];
		var constrParams:Null<Array<TypeParamDecl>> = null;
		
		function getName(cls:ClassType):String {
			switch (cls.kind) {
				case KGenericInstance(cl, params):
					cls = cl.get();
					
				default:
			}
			
			var pack:Array<String> = cls.pack.copy();
			pack.push(cls.name);
			
			return pack.join('_');
		}
		
		function mapConstructor(expr:Expr):Expr {
			if (expr == null) return null;
			
			return switch (expr.expr) {
				case ECall({pos: p, expr: EConst(CIdent('super'))}, params):
					{pos: expr.pos, expr: ECall({pos: p, expr: EConst(CIdent('insanitySuper${getName(lastClassWithConstr)}'))}, params)};
				
				default:
					expr.map(mapConstructor);
			}
		}
		
		for (field in fields) {
			switch (field.kind) {
				default:
				
				case FVar(t, e) if (field.access?.contains(AFinal) && !field.access.contains(AInline)):
					field.kind = FProp('default', 'null', t, e);
					field.access.remove(AFinal);
					
				case FFun(fun) if (field.name == 'new'):
					var constr = mapConstructor(fun.expr);
					switch (constr.expr) {
						case EBlock(a): for (e in a) expr.push(e);
						default: expr.push(constr);
					};
					constrParams = fun.params;
					constrArgs = fun.args;
					hasConstructor = true;
					lastClassWithConstr = cls;
			}
		}
		
		for (field in fields) {
			final f:String = field.name;
			
			for (meta in field.meta) {
				if (meta.name != ':allow') continue;
				
				switch (meta.params[0].expr) {
					case EField(e, f, a) if (f == 'new'):
						field.meta.push({
							pos: meta.pos,
							name: ':allow',
							params: [{
								pos: meta.pos,
								expr: EField(e, 'insanitySuper${e.toString().replace('.', '_')}', a) //gay
							}]
						});
						
					default:
				}
			}
			
			if (field?.access.contains(AStatic) || field?.access.contains(AInline)) continue;
			if (field.meta?.exists((meta) -> meta.name == ':deprecated')) continue;
			
			switch (field.kind) {
				default:
				
				case FProp(get, set, _, e) if (e != null && (set == 'set' || set == 'dynamic')):
					expr.unshift(macro Reflect.setField(this, $v {f}, $e));
				
				case FProp(get, set, _, e) if (e != null && set != 'set' && set != 'never'):
					expr.unshift(macro $i {f} = $e);
				
				case FVar(_, e) if (e != null):
					// trace(field.name + ' = ' + e.toString());
					expr.unshift(macro $i {f} = $e);
			}
		}
		
		if (hasConstructor || lastClassWithConstr == null) {
			if (!hasConstructor) expr = [macro throw $v {'${cls.pack.join('.') + (cls.pack.length > 0 ? '.' : '') + cls.name} does not have a constructor'}];
			
			fields.push({
				pos: pos,
				name: 'insanitySuper${getName(cls)}',
				
				kind: FFun({
					ret: macro:Void,
					expr: macro $b {expr},
					args: constrArgs,
					params: constrParams
				})
			});
		}
		
		cls.meta.add(':insanityScriptable', [macro false], pos);
		cls.meta.add(':insanitySuperName', [macro $v {'insanitySuper${getName(hasConstructor ? cls : lastClassWithConstr ?? cls)}'}], pos);
		
		return fields;
	}
}
#else
import insanity.backend.types.Scripted;

abstract InsanityClass<T>(Dynamic) from Class<T> from InsanityScriptedClass to Class<T> to InsanityScriptedClass {}
abstract InsanityEnum<T>(Dynamic) from Enum<T> from InsanityScriptedEnum to Enum<T> to InsanityScriptedEnum {}
#end
