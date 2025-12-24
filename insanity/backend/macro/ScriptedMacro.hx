package insanity.backend.macro;

#if macro
import haxe.macro.TypeTools;
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
		'__construct', '__constructSuper', '__interp', '__base', '__safe', '__func', '__fields', 'instanceFields', 'inlinedFields', 'unexposedFields', 'new', 'super'
	];
	
	static var _name:String = 'insanity.backend.macro.ScriptedMacro';
	
	public static macro function build():Array<Field> {
		var pos = Context.currentPos();
		var cls = Context.getLocalClass().get();
		var fields:Array<Field> = Context.getBuildFields();
		
		trace('Preparing ${cls.name}');
		
		cls.meta.add(':access', [macro insanity.Module], pos);
		cls.meta.add(':access', [macro insanity.backend.Interp], pos);
		cls.meta.add(':access', [macro insanity.backend.types.InsanityScriptedClass], pos);
		
		var knownFields:Array<String> = [];
		var inlinedFields:Array<String> = [];
		var omittedFields:Array<String> = [];
		
		var constructorExpr:Expr = null;
		var hasConstructor:Bool = false;
		var hasToString:Bool = false;
		
		function setFields(type:ClassType, ?types:Array<Type>) {
			var typeFields:Array<ClassField> = type.fields.get();
			
			var generics:Map<String, ComplexType> = [];
			if (types != null) {
				for (i => t in types) {
					var classParam = type.params[i];
					generics.set(classParam.name, t.follow().toComplexType());
				}
			}
			
			if (!hasConstructor && type.constructor != null) {
				var constr = type.constructor.get();
				
				function mapConstructor(type:ClassType):Expr {
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
					
					var expr = Context.getTypedExpr(constr.expr());
					switch (expr.expr) {
						default:
						case EFunction(_, fun):
							expr = fun.expr;
					}
					
					function mapSuper(e:Expr) {
						return switch(e.expr) {
							case ECall({pos: _, expr: EConst(CIdent('super'))}, params): // "inlining" super constructor calls
								var superClass = type.superClass.t.get();
								
								{pos: pos, expr: ECall(mapConstructor(superClass), params)};
							default:
								e.map(mapSuper);
						}
					}
					
					var constr = expr.map(mapSuper);
					var body:Array<Expr> = [constr];
					
					for (field in type.fields.get()) {
						switch (field.kind) {
							default:
							case FVar(_, write):
								switch (write) {
									case AccNormal, AccCall, AccInline, AccNo:
									default: continue;
								}
								
								var e = field.expr();
								if (e == null) continue;
								
								//trace(e);
								function mapTyped(e:TypedExpr) {
									return switch (e.expr) {
										case TNew(c, tp, params):
											//ENew();
											var c = c.get();
											
											var n = c.name;
											var p = c.pack.copy();
											if (n.endsWith('_Impl_')) {
												p = c.module.split('.');
												n = p.pop();
											}
											
											// trace('$p ; $n');
											{
												pos: pos,
												expr: ENew(
													{pack: p, name: n, params: [for (p in tp) TPType(p.toComplexType())]},
													[for (param in params) {
														switch (param.t) {
															case TAbstract(a, p):
																var a = a.get();
																// trace(a);
																if (a.name != 'Null') {
																	mapTyped(param);
																} else {
																	continue;
																}
															default:
																mapTyped(param);
														}
													}]
												)
											};
										default:
											Context.getTypedExpr(e);
									}
								}
								var expr = mapTyped(e);
								// body.unshift(macro trace($v {field.name} + ' -> ' + $i {field.name}));
								body.unshift(macro Reflect.setField(this, $v {field.name}, $expr));
						}
					}
					constr = macro $b {body};
					
					return {pos: pos, expr: EFunction(FAnonymous, {
						args: [for (arg in args) { {name: arg.name, opt: arg.opt, type: arg.t.toComplexType()} }],
						expr: constr,
						ret: ret.toComplexType()
					})};
				}
				
				hasConstructor = true;
				constructorExpr = {pos: pos, expr: EMeta({pos: pos, name: ':privateAccess'}, mapConstructor(type))};
				// trace(constructorExpr.toString());
			}
			
			for (field in typeFields) {
				if (ignoreFields.contains(field.name)) continue;
				
				if (!knownFields.contains(field.name)) knownFields.push(field.name);
				
				switch (field.kind) {
					case FMethod(kind):
						if (omittedFields.contains(field.name)) continue;
						switch (kind) {
							case MethInline:
								if (!inlinedFields.contains(field.name)) inlinedFields.push(field.name);
								omittedFields.push(field.name);
								continue;
							case MethMacro:
								omittedFields.push(field.name);
								continue;
							default:
								if (field.isFinal) {
									omittedFields.push(field.name);
									continue;
								}
						}
						
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
							expr = {pos: pos, expr: EMeta({pos: pos, name: ':privateAccess'}, expr)};
							
							var argsArray:Array<Expr> = new Array<Expr>();
							for (arg in args)
								argsArray.push(macro cast $i {arg.name});
							
							var isVoid:Bool = switch (ret) {
								case TAbstract(t, _): (t.get().name == 'Void');
								default: false;
							}
							var f:String = field.name;
							expr = macro {
								var fname:String = $v {f};
								if (__interp != null && __func != fname && __interp.locals.exists(fname)) {
									var prevFunc:String = __func;
									__func = fname; // prevent loop
									var r:Dynamic;
									if (__safe) {
										__interp.inTry = true;
										try { r = Reflect.callMethod(__interp, __interp.getLocal(fname), $a {argsArray}); }
										catch (e:Dynamic) { __base.onInstanceError(e, this); r = null; }
									} else {
										r = Reflect.callMethod(__interp, __interp.getLocal(fname), $a {argsArray});
									}
									__func = prevFunc;
									${isVoid ? macro return : macro return cast r}
								}
								
								if (__safe) {
									try { ${isVoid ? macro super.$f ($a {argsArray}) : macro return super.$f($a{argsArray})} }
									catch (e:Dynamic) { __base.onInstanceError(e, this); ${isVoid ? macro return : macro return cast null} }
								} else {
									${isVoid ? macro super.$f ($a {argsArray}) : macro return super.$f ($a {argsArray})}
								}
							};
							
							var buildField:Field = fields.find(function(f:Field) return (f.name == field.name));
							if (buildField == null) {
								var access:Array<Access> = [AOverride];
								if (field.isPublic) access.push(APublic);
								if (field.isExtern) access.push(AExtern);
								if (field.isAbstract) access.push(AAbstract);
								
								//Context.info(field.name, pos);
								//Context.info(Std.string(ret.toComplexType()), pos);
											//trace(f);
								
								var cantInfer:Bool = false;
								function mapGeneric(t:ComplexType) {
									switch (t) {
										case TPath(p):
											if (generics.exists(p.name)) {
												return generics.get(p.name);
											} else if (p.name.length == 1) {
												cantInfer = true;
												return t;
											} else {
												if (p != null) {
													for (i => param in p.params)
														p.params[i] = switch(param) {
															case TPType(p): TPType(mapGeneric(p));
															default: param;
														}
												}
												return t;
											}
										case TOptional(t):
											return TOptional(mapGeneric(t));
										case TNamed(n, t):
											return TNamed(n, mapGeneric(t));
										case TFunction(args, ret):
											return TFunction([for (arg in args) mapGeneric(arg)], mapGeneric(ret));
										case TParent(t):
											return TParent(mapGeneric(t));
										default:
											return t;
									}
								}
								
								var args = [for (arg in args) {
									var twist:Bool = arg.opt;
									var t = mapGeneric(arg.t.toComplexType());
									switch (t) {
										case TPath(p):
											if (p.sub == 'Null')
												twist = false;
										default:
									}
									{
										name: arg.name,
										opt: arg.opt,
										type: (twist ? macro:Dynamic /* ?!?!?!?!?!?? */ : t)
									}
								}];
								var ret = mapGeneric(ret.toComplexType());
								
								if (cantInfer) {
									omittedFields.push(f);
									trace('Couldn\'t override field $f ...');
									continue;
								}
								
								fields.push({
									pos: pos, access: access, name: f,
									kind: FFun({
										args: args,
										expr: expr,
										ret: ret
									})
								});
							}
						}
						
					case FVar(_, _):
						// 
				}
			}
			
			if (type.superClass != null)
				setFields(type.superClass.t.get(), type.superClass.params);
		}
		setFields(cls/*, [for (param in cls.params) param.t]*/);
		
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
		
		var constructExpr = macro {
			__base = base;
			__safe = base.safe;
			__interp = new insanity.backend.Interp(base.interp.environment);
			__interp.pushStack(insanity.backend.CallStack.StackItem.SModule(base.module?.path ?? base.name));
			
			__interp.setDefaults();
			__interp.variables.set('this', this);
			for (u in base.interp.usings) __interp.usings.push(u);
			for (k => i in base.interp.imports) __interp.imports.set(k, i);
			// for (k => v in base.interp.variables) __interp.variables.set(k, v);
			
			__fields = [];
			var constructor:Dynamic = null;
			function setFields(t:insanity.backend.types.Scripted.InsanityScriptedClass, isSuper:Bool = false) {
				for (field in t.decl.fields) {
					var f:String = field.name;
					
					if (field.access.contains(AStatic)) continue;
					
					switch (field.kind) {
						case KFunction(fun):
							if (!__interp.locals.exists(f)) __interp.locals.set(f, {r: null, access: field.access});
						case KVar(v):
							if (instanceFields.contains(f)) { Reflect.setField(this, f, __interp.exprReturn(v.expr)); }
							else if (!__interp.locals.exists(f)) { __interp.locals.set(f, {r: null, access: field.access, get: v.get, set: v.set}); }
					}
				}
				
				var superLocals:Map<String, insanity.backend.Interp.Variable> = __interp.duplicate(__interp.locals);
				for (loc => v in t.interp.locals)
					superLocals.set(loc, v);
				
				for (field in t.decl.fields) {
					var f:String = field.name;
					
					if (field.access.contains(AStatic)) continue;
					if (f != 'new') __fields.push(f);
					
					switch (field.kind) {
						case KFunction(fun):
							__interp.position = fun.expr.pos;
							
							if (f == 'new') {
								constructor = __interp.buildFunction(f, fun.args, fun.expr, fun.ret, superLocals, true);
								continue;
							}
							
							__interp.locals.get(f).r = __interp.buildFunction(f, fun.args, fun.expr, fun.ret, superLocals);
						case KVar(v):
							__interp.locals.get(f).r = __interp.exprReturn(v.expr);
					}
					
					if (isSuper) superLocals.set(f, __interp.locals.get(f));
				}
				
				if (isSuper) __interp.locals.set('super', {r: insanity.backend.Expr.Mirror.MSuper(superLocals, constructor)});
			}
			
			function setSuperFields(extending:Dynamic) {
				if (extending is insanity.backend.types.Scripted.InsanityScriptedClass) {
					var extend:insanity.backend.types.Scripted.InsanityScriptedClass = cast extending;
					
					if (extend.extending != null) setSuperFields(extend.extending);
					
					setFields(extend, true);
				}
			}
			
			var locals:Map<String, insanity.backend.Interp.Variable> = [];
			for (field in instanceFields) {
				if (!insanity.backend.macro.ScriptedMacro.ignoreFields.contains(field)) {
					__interp.variables.set(field, insanity.backend.Expr.Mirror.MProperty(this, field));
					
					var f = Reflect.field(this, field);
					if (Reflect.isFunction(f)) locals.set(field, {r: f});
				}
				
				field;
			};
			
			var superConstructor = ${hasConstructor ? constructorExpr : macro { null; }};
			
			__interp.locals.set('super', {r: insanity.backend.Expr.Mirror.MSuper(locals, superConstructor)});
			setSuperFields(base.extending);
			setFields(base);
			
			if (constructor == null) constructor = superConstructor;
			if (constructor != null) {
				if (__safe) {
					try { Reflect.callMethod(this, constructor, arguments); }
					catch (e:Dynamic) { __base.onInstanceError(e, this); }
				} else {
					Reflect.callMethod(this, constructor, arguments);
				}
			} else {
				if (__safe) {
					__base.onInstanceError('${base.path} does not have a constructor', this);
				} else {
					throw '${base.path} does not have a constructor';
				}
			}
		};
		fields.push({
			pos: pos, name: '__construct',
			kind: FFun({
				args: [{name: 'base', type: macro:insanity.backend.types.Scripted.InsanityScriptedClass}, {name: 'arguments', type: macro:Array<Dynamic>}],
				expr: constructExpr,
				ret: macro:Void
			})
		});
		
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
			pos: pos, name: '__base',
			kind: FVar(macro:insanity.backend.types.Scripted.InsanityScriptedClass),
		}, {
			pos: pos, name: '__safe',
			kind: FVar(macro:Bool),
		}, {
			pos: pos, access: [AStatic, APublic], name: 'instanceFields',
			kind: FVar(macro:Array<String>, macro $v {knownFields}),
		}, {
			pos: pos, access: [AStatic, APublic], name: 'inlinedFields',
			kind: FVar(macro:Array<String>, macro $v {inlinedFields}),
		}, {
			pos: pos, access: [AStatic, APublic], name: 'unexposedFields',
			kind: FVar(macro:Array<String>, macro $v {omittedFields}),
		}, {
			pos: pos, name: '__fields',
			kind: FVar(macro:Array<String>),
		}, {
			pos: pos, name: '__func',
			kind: FVar(macro:String, macro $v {''}),
		}, {
			pos: pos, name: '__interp',
			kind: FVar(macro:insanity.backend.Interp),
		}, {
			pos: pos, access: [APublic, AStatic], name: 'baseClass',
			kind: FVar(macro:String, macro $v {path.join('.')})
		}, {
			pos: pos, access: [APublic], name: 'reflectHasField',
			kind: FFun({
				args: [{name: 'field', type: macro:String}],
				expr: macro {
					if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(field)) return false;
					return (instanceFields.contains(field) || Reflect.hasField(this, field) || __fields.contains(field));
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
					} else if (__interp.locals.exists(field)) {
						return __interp.locals.get(field).r;
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
					} else if (__interp.locals.exists(field)) {
						return __interp.locals.get(field).r = value;
					}
					return null;
				},
				ret: macro:Dynamic
			})
		}, { // TODO
			pos: pos, access: [APublic], name: 'reflectGetProperty',
			kind: FFun({
				args: [{name: 'property', type: macro:String}],
				expr: macro {
					if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(property)) return null;
					if (instanceFields.contains(property) || Reflect.hasField(this, property)) {
						return Reflect.getProperty(this, property);
					} else if (__interp.locals.exists(property)) {
						return __interp.getLocal(property);
					}
					return null;
				},
				ret: macro:Dynamic
			})
		}, { // TODO
			pos: pos, access: [APublic], name: 'reflectSetProperty',
			kind: FFun({
				args: [{name: 'property', type: macro:String}, {name: 'value', type: macro:Dynamic}],
				expr: macro {
					if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(property)) return null;
					if (instanceFields.contains(property) || Reflect.hasField(this, property)) {
						Reflect.setProperty(this, property, value);
						return Reflect.field(this, property);
					} else if (__interp.locals.exists(property)) {
						return __interp.setLocal(property, value);
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
					for (f in __fields) { if (!fields.contains(f)) fields.push(f); }
					return fields;
				},
				ret: macro:Array<String>
			})
		}, {
			pos: pos, access: [APublic], name: 'typeGetClass',
			kind: FFun({
				args: [],
				expr: macro { return __base; },
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