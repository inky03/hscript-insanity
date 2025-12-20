package insanity.backend.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

class ScriptedMacro {
	public static macro function build():Array<Field> {
		var pos = Context.currentPos();
		var cls = Context.getLocalClass().get();
		var fields:Array<Field> = Context.getBuildFields();
		
		cls.meta.add(':access', [macro insanity.Module], pos);
		cls.meta.add(':access', [macro insanity.backend.Interp], pos);
		cls.meta.add(':access', [macro insanity.backend.types.InsanityScriptedClass], pos);
		
		var hasToString:Bool = false;
		for (field in fields) {
			switch (field.kind) {
				case FFun(fun):
					if (field.name == 'new') {
						
					} else if (field.name == 'toString') {
						hasToString = true;
					} else {
						
					}
				case FVar(t, e):
					// 
				case FProp(get, set, t, e):
					// 
			}
		}
		
		if (!hasToString) {
			fields.push({
				pos: pos, access: [APublic], name: 'toString',
				kind: FFun({
					args: [],
					expr: macro { return __base.path; },
					ret: macro:String
				})
			});
		}
		
		fields = fields.concat([{
			pos: pos, name: '__construct',
			kind: FFun({
				args: [{name: 'base', type: macro:insanity.backend.types.Scripted.InsanityScriptedClass}, {name: 'arguments', type: macro:Array<Dynamic>}],
				expr: macro {
					__base = base;
					__interp = new insanity.backend.Interp(base.interp.environment);
					__interp.setDefaults();
					__interp.variables.set('this', this);
					__interp.pushStack(insanity.backend.CallStack.StackItem.SModule(base.module.path));
					
					var constructor:Dynamic = null;
					
					function setFields(decl:insanity.backend.Expr.ClassDecl, isSuper:Bool = false) {
						var superLocals:Map<String, insanity.backend.Interp.Variable> = __interp.duplicate(__interp.locals);
						
						for (field in decl.fields) {
							var f:String = field.name;
							
							if (field.access.contains(AStatic)) continue;
							
							switch (field.kind) {
								case KFunction(fun):
									__interp.curExpr = fun.expr;
									
									if (f == 'new') {
										constructor = __interp.buildFunction(f, fun.args, fun.expr, fun.ret, superLocals, true);
										continue;
									}
									
									// trace(f + ' -> ' + insanity.backend.Printer.toString(fun.expr));
									__interp.locals.set(f, {
										r: __interp.buildFunction(f, fun.args, fun.expr, fun.ret, superLocals),
										access: field.access
									});
								case KVar(v):
									__interp.locals.set(f, {
										r: __interp.exprReturn(v.expr),
										access: field.access,
										get: v.get,
										set: v.set
									});
							}
							
							if (isSuper) superLocals.set(f, __interp.locals.get(f));
						}
						
						if (isSuper) __interp.locals.set('super', {r: insanity.backend.Expr.Mirror.MSuper(superLocals, constructor)});
					}
					
					function setSuperFields(extending:Dynamic) {
						if (extending is insanity.backend.types.Scripted.InsanityScriptedClass) {
							var extend:insanity.backend.types.Scripted.InsanityScriptedClass = cast extending;
							
							if (extend.extending != null) setSuperFields(extend.extending);
							
							setFields(extend.decl, true);
						}
					}
					
					__interp.locals.set('super', {r: insanity.backend.Expr.Mirror.MSuper(null, null)});
					setSuperFields(base.extending);
					setFields(base.decl);
					
					if (constructor != null)
						Reflect.callMethod(this, constructor, arguments);
				},
				ret: macro:Void
			})
		}]);
		
		fields = fields.concat([/*{
			pos: pos, access: [APublic], name: '__insanityFields',
			kind: FVar(macro:Map<String, insanity.backend.Interp.Variable>, macro { new Map(); }),
		},*/ {
			pos: pos, access: [APublic], name: '__base',
			kind: FVar(macro:insanity.backend.types.Scripted.InsanityScriptedClass),
		}, {
			pos: pos, access: [APublic], name: '__interp',
			kind: FVar(macro:insanity.backend.Interp),
		}, {
			pos: pos, access: [APublic], name: 'reflectHasField',
			kind: FFun({
				args: [{name: 'field', type: macro:String}],
				expr: macro { return (Reflect.hasField(this, field) ?? __interp.locals.exists(field)); },
				ret: macro:Bool
			})
		}, {
			pos: pos, access: [APublic], name: 'reflectGetField',
			kind: FFun({
				args: [{name: 'field', type: macro:String}],
				expr: macro {
					if (__interp.locals.exists(field)) {
						return __interp.locals.get(field).r;
					} else {
						return Reflect.field(this, field);
					}
				},
				ret: macro:Dynamic
			})
		}, {
			pos: pos, access: [APublic], name: 'reflectSetField',
			kind: FFun({
				args: [{name: 'field', type: macro:String}, {name: 'value', type: macro:Dynamic}],
				expr: macro {
					if (__interp.locals.exists(field)) {
						return __interp.locals.get(field).r = value;
					} else {
						Reflect.setField(this, field, value);
						return Reflect.field(this, field);
					}
				},
				ret: macro:Dynamic
			})
		}, { // TODO
			pos: pos, access: [APublic], name: 'reflectGetProperty',
			kind: FFun({
				args: [{name: 'property', type: macro:String}],
				expr: macro {
					if (__interp.locals.exists(property)) {
						return __interp.getLocal(property);
					} else {
						return Reflect.getProperty(this, property);
					}
				},
				ret: macro:Dynamic
			})
		}, { // TODO
			pos: pos, access: [APublic], name: 'reflectSetProperty',
			kind: FFun({
				args: [{name: 'property', type: macro:String}, {name: 'value', type: macro:Dynamic}],
				expr: macro {
					if (__interp.locals.exists(property)) {
						return __interp.setLocal(property, value);
					} else {
						Reflect.setProperty(this, property, value);
						return Reflect.field(this, property);
					}
				},
				ret: macro:Dynamic
			})
		}, {
			pos: pos, access: [APublic], name: 'reflectListFields',
			kind: FFun({
				args: [],
				expr: macro { return [for (f in Reflect.fields(this)) f].concat([for (f in __interp.locals.keys()) f]); },
				ret: macro:Array<String>
			})
		}]);
		
		return fields;
	}
}
#end