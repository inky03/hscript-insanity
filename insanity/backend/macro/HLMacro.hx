package insanity.backend.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;
using Lambda;

class HLMacro {
	public static macro function fixLongMethods():Array<Field> {
		var fields:Array<Field> = Context.getBuildFields();
		
		if (!Context.defined('hl')) return fields;
		
		var pos = Context.currentPos();
		var type = Context.getLocalType(), cls:ClassType;
		
		switch (type) {
			case TInst(r, _):
				cls = r.get();
				
				if (cls.meta.has(':hlNative') || cls.meta.has(':insanityScripted') || cls.name.indexOf('_Impl_') != -1 || cls.isInterface)
					return fields;
			
			default:
				return fields;
		}
		
		function createHLExpr(name:String, args:Array<FunctionArg>, isStatic:Bool):Expr {
			final callArgs:Array<Expr> = [for (i => arg in args) macro arguments[$v {i}] ?? $e {arg.value ?? macro null}];
			// i forgot expr reification was a thing until like 10 minutes ago ... so cool ...
			return macro return $i {isStatic ? cls.name : 'this'}.$name($a {callArgs});
		}
		
		for (field in fields) {
			if (field.name == 'new') continue; // todo
			
			switch (field.kind) {
				default:
				case FFun(fun) if (fun.args.length >= 9):
					// trace('fix ${cls.module+'.'+cls.name}.${field.name}');
					
					final funName:String = 'insanityhl${field.name}';
					final access:Null<Array<Access>> = field.access?.copy();
					
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
							expr: createHLExpr(field.name, fun.args, access?.contains(AStatic))
						})
					});
			}
		}
		
		return fields;
	}
	
	public static macro function build(e:Expr):Array<Field> {
		var pos = Context.currentPos();
		var fields:Array<Field> = Context.getBuildFields();
		
		var cls = switch (Context.getType(e.toString())) {
			case TInst(t, _):
				t.get();
			default:
				throw 'Not a class';
		}
		
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
					trace(f);
					
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
}
#end