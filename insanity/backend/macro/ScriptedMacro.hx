package insanity.backend.macro;

#if macro
import haxe.macro.TypeTools;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using Lambda;
using haxe.macro.TypeTools;
using haxe.macro.ExprTools;
#end

class ScriptedMacro {
	public static var ignoreFields:Array<String> = [
		'reflectHasField', 'reflectGetField', 'reflectSetField', 'reflectListFields', 'reflectGetProperty', 'reflectSetProperty',
		'__construct', '__interp', '__base', '__func', '__fields', 'new', 'super'
	];
	
	static var _name:String = 'insanity.backend.macro.ScriptedMacro';
	
	public static macro function build():Array<Field> {
		var pos = Context.currentPos();
		var cls = Context.getLocalClass().get();
		var fields:Array<Field> = Context.getBuildFields();
		
		cls.meta.add(':access', [macro insanity.Module], pos);
		cls.meta.add(':access', [macro insanity.backend.Interp], pos);
		cls.meta.add(':access', [macro insanity.backend.types.InsanityScriptedClass], pos);
		
		var hasConstructor:Bool = false;
		var hasToString:Bool = false;
		
		function setFields(type:ClassType) {
			var typeFields:Array<ClassField> = type.fields.get();
			
			if (!hasConstructor && type.constructor != null) {
				var constr = type.constructor.get();
				
				var args = null, ret = null;
				switch (constr.type) {
					default:
					case TFun(aargs, rret): args = aargs; ret = rret;
					case TLazy(lazy):
						switch (lazy()) {
							default:
							case TFun(aargs, rret): args = aargs; ret = rret;
						}
				}
				
				function mapConstructor(type:ClassType) {
					var constr = type.constructor.get();
					
					var expr = Context.getTypedExpr(constr.expr());
					switch (expr.expr) {
						default:
						case EFunction(_, fun):
							expr = fun.expr;
					}
					
					function mapSuper(e:Expr) {
						return switch(e.expr) {
							case ECall({pos: _, expr: EConst(CIdent('super'))}, _): // "inlining" super constructor calls
								var superClass = type.superClass.t.get();
								mapConstructor(superClass);
							default:
								e.map(mapSuper);
						}
					}
					
					return expr.map(mapSuper);
				}
				var expr = mapConstructor(type);
				
				hasConstructor = true;
				fields.push({
					pos: pos, name: '__constructSuper',
					kind: FFun({
						args: [for (arg in args) { {name: arg.name, opt: arg.opt, type: arg.t.toComplexType()} }],
						expr: expr,
						ret: ret.toComplexType()
					})
				});
			}
			
			for (field in typeFields) {
				if (ignoreFields.contains(field.name)) continue;
				
				switch (field.kind) {
					case FMethod(kind):
						if (field.name == 'toString') {
							hasToString = true;
						} else {
							var args:Array<{t:Type, opt:Bool, name:String}> = null, ret = null, expr = Context.getTypedExpr(field.expr());
							switch (field.type) {
								default:
								case TFun(aargs, rret): args = aargs; ret = rret;
								case TLazy(lazy):
									switch (lazy()) {
										default:
										case TFun(aargs, rret): args = aargs; ret = rret;
									}
							}
							switch (expr.expr) {
								default:
								case EFunction(_, fun):
									expr = fun.expr;
							}
							
							var argsArray:Array<Expr> = new Array<Expr>();
							for (arg in args)
								argsArray.push(macro $i {arg.name});
							
							var isVoid:Bool = switch (ret) {
								case TAbstract(t, _): (t.get().name == 'Void');
								default: false;
							}
							expr = macro {
								var func:String = $v {field.name};
								if (__func != func && __interp.locals.exists(func)) {
									var prevFunc:String = __func;
									__func = func; // prevent stack overflow ? maybe ??
									var r = Reflect.callMethod(__interp, __interp.getLocal(func), $a {argsArray});
									__func = prevFunc;
									${isVoid ? macro {} : macro { return r; }}
								} else {
									${expr}
								}
							};
							
							var buildField:Field = fields.find(function(f:Field) return f.name == field.name);
							if (buildField == null) {
								var access:Array<Access> = [AOverride];
								if (field.isPublic) access.push(APublic);
								if (field.isFinal) access.push(AFinal);
								if (field.isExtern) access.push(AExtern);
								if (field.isAbstract) access.push(AAbstract);
								
								fields.push({
									pos: pos, access: access, name: field.name,
									kind: FFun({
										args: [for (arg in args) { {name: arg.name, opt: arg.opt, type: arg.t.toComplexType()} }],
										expr: expr,
										ret: ret.toComplexType()
									})
								});
							}
						}
						
					case FVar(_, _):
						// 
				}
			}
			
			if (type.superClass != null)
				setFields(type.superClass.t.get());
		}
		setFields(cls);
		
		if (!hasConstructor) {
			fields.push({
				pos: pos, access: [APublic], name: '__constructSuper',
				kind: FFun({
					args: [],
					expr: macro { },
					ret: macro:Void
				})
			});
		} if (!hasToString) {
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
									if (__fields.contains(f)) {
										Reflect.setField(this, f, __interp.exprReturn(v.expr));
									} else {
										__interp.locals.set(f, {
											r: __interp.exprReturn(v.expr),
											access: field.access,
											get: v.get,
											set: v.set
										});
									}
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
					
					__fields = [];
					var classFields:Map<String, insanity.backend.Interp.Variable> = [];
					for (field in Type.getInstanceFields(Type.getClass(this))) {
						__fields.push(field);
						if (field != '__fields')
							classFields.set(field, {r: Reflect.field(this, field)});
					}
					
					__interp.locals.set('super', {r: insanity.backend.Expr.Mirror.MSuper(classFields, __constructSuper)});
					setSuperFields(base.extending);
					setFields(base.decl);
					
					if (constructor != null)
						Reflect.callMethod(this, constructor, arguments);
				},
				ret: macro:Void
			})
		}]);
		
		var superClass = cls.superClass?.t.get();
		var path:Array<String>;
		
		if (superClass != null) {
			path = superClass.pack.copy();
			path.push(superClass.name);
		} else {
			path = cls.pack.copy();
			path.push(cls.name);
		}
		
		fields = fields.concat([{
			pos: pos, access: [APublic], name: '__base',
			kind: FVar(macro:insanity.backend.types.Scripted.InsanityScriptedClass),
		}, {
			pos: pos, access: [APublic], name: '__fields',
			kind: FVar(macro:Array<String>),
		}, {
			pos: pos, access: [APublic], name: '__func',
			kind: FVar(macro:String, macro $v {''}),
		}, {
			pos: pos, access: [APublic, AStatic], name: 'baseClass',
			kind: FVar(macro:String, macro $v {path.join('.')})
		}, {
			pos: pos, access: [APublic], name: '__interp',
			kind: FVar(macro:insanity.backend.Interp),
		}, {
			pos: pos, access: [APublic], name: 'reflectHasField',
			kind: FFun({
				args: [{name: 'field', type: macro:String}],
				expr: macro {
					if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(field)) return false;
					return (__fields.contains(field) || Reflect.hasField(this, field) || __interp.locals.exists(field));
				},
				ret: macro:Bool
			})
		}, {
			pos: pos, access: [APublic], name: 'reflectGetField',
			kind: FFun({
				args: [{name: 'field', type: macro:String}],
				expr: macro {
					if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(field)) return null;
					if (!__fields.contains(field) && __interp.locals.exists(field)) {
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
					if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(field)) return null;
					if (!__fields.contains(field) && __interp.locals.exists(field)) {
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
					if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(property)) return null;
					if (!__fields.contains(property) && __interp.locals.exists(property)) {
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
					if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(property)) return null;
					if (!__fields.contains(property) && __interp.locals.exists(property)) {
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
				expr: macro {
					return [for (f in Reflect.fields(this)) if (!insanity.backend.macro.ScriptedMacro.ignoreFields.contains(f)) f]
						.concat([for (f in __interp.locals.keys()) if (!insanity.backend.macro.ScriptedMacro.ignoreFields.contains(f)) f]);
				},
				ret: macro:Array<String>
			})
		}]);
		
		return fields;
	}
	
	public static macro function listScriptedClasses() {
		Context.onAfterTyping(function(types) {
			var self = TypeTools.getClass(Context.getType(_name));
			if (self.meta.has('typedScripted')) return;
			
			var map:Array<String> = [];
			
			for (type in types) {
				switch (type) {
					case TClassDecl(r):
						var c = r.get();
						if (c.interfaces.length > 0 && c.interfaces[0].t.get().name == 'IInsanityScripted') {
							var p = c.pack.copy(); p.push(c.name);
							map.push(p.join('.'));
						}
					default:
				}
			}
			
			self.meta.add('typedScripted', [macro $v {map}], self.pos);
		});
		
		return macro {
			var meta:Array<String> = cast haxe.rtti.Meta.getType($p {_name.split('.')}).typedScripted[0];
			var map:Map<String, Dynamic> = [];
			
			insanity.backend.types.Scripted.InsanityDummyClass.baseClass; // shrug
			
			for (cls in meta) {
				var scripted:Dynamic = Type.resolveClass(cls);
				map.set(scripted.baseClass ?? '', cast scripted);
			}
				
			cast map;
		}
	}
}