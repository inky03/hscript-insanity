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
					
					for (field in base.decl.fields) {
						var f:String = field.name;
						
						if (field.access.contains(AStatic)) continue;
						
						switch (field.kind) {
							case KFunction(fun):
								if (f == 'new') {
									constructor = __interp.buildFunction(f, fun.args, fun.expr, fun.ret);
									continue;
								}
								
								__interp.locals.set(f, {
									r: __interp.buildFunction(f, fun.args, fun.expr, fun.ret),
									access: field.access
								});
							case KVar(v):
								__interp.locals.set(f, {
									r: __interp.exprReturn(v.expr),
									access: field.access
								});
						}
					}
					
					if (constructor != null) {
						Reflect.callMethod(this, constructor, arguments);
					}
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
				args: [{name: 'field', type: macro:String}],
				expr: macro {
					if (__interp.locals.exists(field)) {
						return __interp.locals.get(field).r;
					} else {
						return Reflect.getProperty(this, field);
					}
				},
				ret: macro:Dynamic
			})
		}, { // TODO
			pos: pos, access: [APublic], name: 'reflectSetProperty',
			kind: FFun({
				args: [{name: 'field', type: macro:String}, {name: 'value', type: macro:Dynamic}],
				expr: macro {
					if (__interp.locals.exists(field)) {
						return __interp.locals.get(field).r = value;
					} else {
						Reflect.setProperty(this, field, value);
						return Reflect.field(this, field);
					}
				},
				ret: macro:Dynamic
			})
		}, {
			pos: pos, access: [APublic], name: 'reflectListFields',
			kind: FFun({
				args: [],
				expr: macro { return [for (f in Reflect.fields(this)) {
					if (f != '__interp' && f != '__base') f;
				}].concat([for (f in __interp.locals.keys()) {
					f;
				}]); },
				ret: macro:Array<String>
			})
		}]);
		
		return fields;
	}
}
#end