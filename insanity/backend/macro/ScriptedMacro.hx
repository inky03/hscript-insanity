package insanity.backend.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using Lambda;
using StringTools;
using haxe.macro.TypeTools;
using haxe.macro.ExprTools;
using haxe.macro.ComplexTypeTools;
#end

class ScriptedMacro {
	public static var ignoreFields:Array<String> = [
		'reflectHasField', 'reflectGetField', 'reflectSetField', 'reflectListFields', 'reflectGetProperty', 'reflectSetProperty',
		'typeCreateInstance', 'typeGetClass', 'typeGetClassFields', 'typeCreateEmptyInstance', 'typeGetInstanceFields',
		'__isScripted', '__scriptedBase', '__interpSafe', '__interp', '__func', '__fields', '__vars', 'instanceFields', 'inlinedFields', 'unexposedFields', 'new', 'super', '__insanitySuperName'
	];
	
	static var _name:String = 'insanity.backend.macro.ScriptedMacro';
	
	public static macro function buildScriptable():Array<Field> {
		var pos = Context.currentPos();
		var cls = Context.getLocalClass()?.get();
		var fields:Array<Field> = Context.getBuildFields();
		
		if (cls == null || !cls.meta.has(':insanityScriptable')) return fields;
		
		var knownFields:Array<String> = [];
		
		cls.meta.remove(':insanityScriptable');
		cls.meta.add(':insanityScriptable', [macro true], pos);
		cls.meta.add(':access', [macro insanity.backend.Interp], pos);
		cls.meta.add(':access', [macro insanity.backend.types.InsanityScriptedClass], pos);
		
		for (field in fields) {
			final f:String = field.name;
			
			if (f.contains('insanitySuper') || ignoreFields.contains(f)) continue;
			
			final isStatic:Bool = (field?.access.contains(AStatic));
			
			if (!isStatic) knownFields.push(f);
			
			switch (field.kind) {
				default:
				case FFun(fun) if (!isStatic):
					// trace(f + ' - ' + field.access);
					final oldExpr:Expr = fun.expr;
					
					var isVoid:Bool = (fun.ret == null || fun.ret.match(TPath({name: 'Void', pack: _})));
					function checkVoid(expr:Expr):Void {
						if (expr == null) return;
						
						switch (expr.expr) {
							case EFunction(_, _): expr;
							case EReturn(e) if (e != null): isVoid = false;
							default: expr.iter(checkVoid);
						}
					}
					
					checkVoid(fun.expr);
					
					final argsArray:Array<Expr> = [for (arg in fun.args) macro $i {arg.name}];
					
					var rr = {pos: oldExpr.pos, expr: EReturn(null)}; // debugging cus it was pising me off
					var ii = {pos: oldExpr.pos, expr: EConst(CIdent('__isScripted'))}
					
					fun.expr = macro {
						final fname:String = $v {f};
						
						if ($ii && __func != fname && __interp.locals.exists(fname)) {
							final prevFunc:String = __func;
							__func = fname; // prevent loop
							
							var r:Dynamic = null;
							if (__interpSafe) {
								__interp.inTry = true;
								
								try {
									r = Reflect.callMethod(__interp, __interp.getLocal(fname), $a {argsArray});
								} catch (e:Dynamic) {
									__scriptedBase.onInstanceError(e, fname, this);
								}
							} else {
								r = Reflect.callMethod(__interp, __interp.getLocal(fname), $a {argsArray});
							}
							
							__func = prevFunc;
							${isVoid ? rr : macro return cast r};
						} else $oldExpr;
					}
			}
		}
		
		var su = cls.superClass?.t.get();
		
		while (true) {
			if (su == null) break;
			
			for (field in su.fields.get()) {
				if (!knownFields.contains(field.name)) knownFields.push(field.name);
			}
			
			su = su.superClass?.t.get();
		}
		
		var newExpr = macro {
			instanceFields = $v {knownFields};
			
			__vars = [];
			__func = '';
			__isScripted = true;
			
			__scriptedBase = base;
			__interpSafe = base.safe;
			__interp = Type.createInstance(insanity.Config.interpClass, [base.interp.environment, this]);
			__interp.pushStack(insanity.backend.CallStack.StackItem.SModule(base.module?.path ?? base.name));
			
			__interp.setDefaults(false, false);
			__interp.variables.set('this', this);
			__interp.variables.set('interp', __interp);
			
			for (u in base.interp.usings) __interp.usings.push(u);
			for (k => i in base.interp.imports) __interp.imports.set(k, i);
			for (k => v in base.interp.variables) if (!__interp.variables.exists(k)) __interp.variables.set(k, v);
			
			var superConstr = Reflect.field(this, __insanitySuperName);
			
			__fields = [];
			var constructor:Dynamic = null;
			function setInstanceFields(i:Dynamic) {
				var instanceFields:Array<String> = i.instanceFields;
				if (instanceFields == null) return;
				
				var superLocals:Map<String, insanity.backend.Interp.Variable> = __interp.duplicate(__interp.locals);
				
				for (field in instanceFields) {
					if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(field)) continue;
					
					if (!__interp.variables.exists(field)) __interp.variables.set(field, insanity.backend.Expr.Mirror.MProperty(this, field));
					
					var f = Reflect.field(this, field);
					if (Reflect.isFunction(f)) superLocals.set(field, {r: f});
				}
				
				__interp.locals.set('super', {r: insanity.backend.Expr.Mirror.MSuper(superLocals, superConstr)});
			}
			function setFields(t:insanity.backend.types.Scripted.InsanityScriptedClass, isSuper:Bool = false) {
				for (field in t.decl.fields) {
					var f:String = field.name;
					
					if (f == 'new' || field.access.contains(AStatic)) continue;
					
					switch (field.kind) {
						case KFunction(fun):
							__interp.locals.set(f, {r: null, access: field.access});
							
						case KVar(v):
							if (instanceFields.contains(f)) {
								Reflect.setField(this, f, __interp.exprReturn(v.expr));
							} else {
								final l:insanity.backend.Interp.Variable = {r: null, access: field.access, get: v.get, set: v.set};
								if (v.get != null) l.get = v.get;
								if (v.set != null) l.set = v.set;
								
								__interp.locals.set(f, l);
							}
					}
				}
				
				var superLocals:Map<String, insanity.backend.Interp.Variable> = __interp.duplicate(__interp.locals);
				for (loc => v in t.__vars)
					superLocals.set(loc, v);
				
				var instanceFields:Array<String> = t.extending?.instanceFields;
				if (instanceFields != null) {
					for (field in instanceFields) {
						if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(field)) continue;
						
						if (!__interp.variables.exists(field)) __interp.variables.set(field, insanity.backend.Expr.Mirror.MProperty(this, field));
						
						var f = Reflect.field(this, field);
						if (Reflect.isFunction(f)) superLocals.set(field, {r: f});
					}
				}
				
				for (field in t.decl.fields) {
					var f:String = field.name;
					
					if (field.access.contains(AStatic)) continue;
					if (f != 'new') __fields.push(f);
					
					switch (field.kind) {
						case KFunction(fun):
							if (f == 'new') {
								constructor = __interp.buildFunction(f, fun.args, fun.expr, fun.ret, superLocals, true);
								continue;
							}
							
							__interp.locals.get(f).r = __interp.buildFunction(f, fun.args, fun.expr, fun.ret, superLocals);
							
						case KVar(v):
							if (__interp.locals.exists(f))
								__interp.locals.get(f).r = (v.expr == null ? null : __interp.exprReturn(v.expr, v.type));
					}
					
					__vars.set(f, __interp.locals.get(f));
					superLocals.set(f, __interp.locals.get(f));
				}
				
				if (isSuper) __interp.locals.set('super', {r: insanity.backend.Expr.Mirror.MSuper(superLocals, constructor)});
			}
			
			function setSuperFields(extending:Dynamic) {
				if (extending is insanity.backend.types.Scripted.InsanityScriptedClass) {
					var extend:insanity.backend.types.Scripted.InsanityScriptedClass = cast extending;
					
					if (extend.extending != null) setSuperFields(extend.extending);
					
					setFields(extend, true);
				} else if (extending != null) {
					setInstanceFields(extending);
				}
			}
			
			setSuperFields(base.extending);
			setFields(base);
			
			constructor ??= superConstr;
			
			if (__interpSafe) {
				try { Reflect.callMethod(this, constructor, arguments); }
				catch (e:Dynamic) { base.onInstanceError(e, 'new', this); }
			} else {
				Reflect.callMethod(this, constructor, arguments);
			}
		};
		
		fields.concat([{
			pos: pos, name: 'insanityNew',
			access: (cls.superClass == null ? [] : [AOverride]),
			kind: FFun({
				ret: macro:Void,
				args: [{name: 'base', type: macro:insanity.backend.types.Scripted.InsanityScriptedClass}, {name: 'arguments', type: macro:Array<Dynamic>}],
				expr: newExpr
			})
		}]);
		
		if (cls.superClass == null) {
			// trace(cls.name);
			fields = fields.concat([{
				pos: pos, name: 'instanceFields',
				kind: FVar(macro:Array<String>, macro null)
			}, {
				pos: pos, name: '__isScripted',
				kind: FVar(macro:Bool, macro false)
			}, {
				pos: pos, name: '__scriptedBase',
				kind: FVar(macro:Null<insanity.backend.types.Scripted.InsanityScriptedClass>, macro null)
			}, {
				pos: pos, name: '__interpSafe',
				kind: FVar(macro:Bool, macro false)
			}, {
				pos: pos, name: '__interp',
				kind: FVar(macro:Null<insanity.backend.Interp>, macro null)
			}, {
				pos: pos, name: '__func',
				kind: FVar(macro:Null<String>, macro null)
			}, {
				pos: pos, name: '__vars',
				kind: FVar(macro:Map<String, insanity.backend.Interp.Variable>, macro null),
			}, {
				pos: pos, name: '__fields',
				kind: FVar(macro:Array<String>, macro null),
			}, {
				pos: pos, access: [APublic], name: 'reflectHasField',
				kind: FFun({
					args: [{name: 'field', type: macro:String}],
					expr: macro {
						if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(field)) return false;
						return (instanceFields.contains(field) || Reflect.hasField(this, field) || __vars.exists(field));
					},
					ret: macro:Bool
				})
			}, {
				pos: pos, access: [APublic], name: 'reflectGetField',
				kind: FFun({
					args: [{name: 'field', type: macro:String}],
					expr: macro {
						if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(field)) return null;
						if (instanceFields.contains(field) || Reflect.hasField(this, field)) {
							return Reflect.field(this, field);
						} else if (__vars.exists(field)) {
							return __vars.get(field).r;
						}
						return null;
					},
					ret: macro:Dynamic
				})
			}, {
				pos: pos, access: [APublic], name: 'reflectSetField',
				kind: FFun({
					args: [{name: 'field', type: macro:String}, {name: 'value', type: macro:Dynamic}],
					expr: macro {
						if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(field)) return null;
						if (instanceFields.contains(field) || Reflect.hasField(this, field)) {
							Reflect.setField(this, field, value);
							return Reflect.field(this, field);
						} else if (__vars.exists(field)) {
							return __vars.get(field).r = value;
						}
						return null;
					},
					ret: macro:Dynamic
				})
			}, {
				pos: pos, access: [APublic], name: 'reflectGetProperty',
				kind: FFun({
					args: [{name: 'property', type: macro:String}],
					expr: macro {
						if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(property)) return null;
						if (instanceFields.contains(property) || Reflect.hasField(this, property)) {
							return Reflect.getProperty(this, property);
						} else if (__vars.exists(property)) {
							return __interp.getLocal(property, __vars);
						}
						return null;
					},
					ret: macro:Dynamic
				})
			}, {
				pos: pos, access: [APublic], name: 'reflectSetProperty',
				kind: FFun({
					args: [{name: 'property', type: macro:String}, {name: 'value', type: macro:Dynamic}],
					expr: macro {
						if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(property)) return null;
						if (instanceFields.contains(property) || Reflect.hasField(this, property)) {
							Reflect.setProperty(this, property, value);
							return Reflect.field(this, property);
						} else if (__vars.exists(property)) {
							return __interp.setLocal(property, value, __vars);
						}
						return null;
					},
					ret: macro:Dynamic
				})
			}, {
				pos: pos, access: [APublic], name: 'reflectListFields',
				kind: FFun({
					args: [],
					expr: macro {
						var fields = [for (f in Reflect.fields(this)) if (!insanity.backend.macro.ScriptedMacro.ignoreFields.contains(f)) f];
						for (f in __vars.keys()) { if (!insanity.backend.macro.ScriptedMacro.ignoreFields.contains(f) && !fields.contains(f)) fields.push(f); }
						return fields;
					},
					ret: macro:Array<String>
				})
			}, {
				pos: pos, access: [APublic], name: 'typeGetClass',
				kind: FFun({
					args: [],
					expr: macro { return __scriptedBase; },
					ret: macro:insanity.backend.types.Scripted.InsanityScriptedClass
				})
			}, {
				pos: pos, access: [APublic], name: 'typeCreateInstance',
				kind: FFun({
					args: [{name: 'args', type: macro:Array<Dynamic>}],
					expr: macro { throw 'Invalid'; return null; },
					ret: macro:Dynamic
				})
			}, {
				pos: pos, access: [APublic], name: 'typeCreateEmptyInstance',
				kind: FFun({
					args: [],
					expr: macro { throw 'Invalid'; return null; },
					ret: macro:Dynamic
				})
			}, {
				pos: pos, access: [APublic], name: 'typeGetInstanceFields',
				kind: FFun({
					args: [],
					expr: macro { return []; },
					ret: macro:Array<String>
				})
			}, {
				pos: pos, access: [APublic], name: 'typeGetClassFields',
				kind: FFun({
					args: [],
					expr: macro { return []; },
					ret: macro:Array<String>
				})
			}]);
		}
		
		// trace('make ${cls.pack.join('.')}.${cls.name} scriptable');
		
		return fields;
	}
}