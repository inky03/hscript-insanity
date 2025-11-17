package insanity.backend.macro;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import Type as HaxeType;
using haxe.macro.ExprTools;
using haxe.macro.TypeTools;
using haxe.macro.ComplexTypeTools;
#end

class AbstractMacro {
	static function build():Array<Field> {
		var t = Context.getLocalType();
		var fields = Context.getBuildFields();
		var imports = Context.getLocalImports();
		
		var ab = null;
		
		switch (t) {
			case TInst(r, _):
				var c = r.get();
				
				c.meta.add(':keep', [], Context.currentPos());
				
				switch (c.kind) {
					case KAbstractImpl(a):
						ab = a.get();
						
						if (ab.meta.has(':coreType') || ab.meta.has(':forward.Variance') || ab.type == null || ab.pack[1] == 'Contraints')
							return fields;
					default:
						return fields;
				}
			default: return fields;
		}
		
		var fullPath = ab.pack.copy(); fullPath.push(ab.name);
		var isEnum = ab.meta.has(':enum');
		
		var cls = macro class extends InsanityAbstract {
			public static var impl(default, never):String = $v {fullPath.join('.')};
		}
		cls.pack = ab.pack;
		cls.name = 'InsanityAbstract_${fullPath.join('_')}';
		cls.meta.push({name: ':keep', pos: Context.currentPos()});
		cls.fields.push({
			name: 'isEnum', pos: Context.currentPos(), access: [APublic, AStatic],
			kind: FProp('default', 'never', macro:Bool, macro $v {isEnum})
		});
		
		imports.push({
			path: [for (v in 'insanity.backend.types.Abstract'.split('.')) {name: v, pos: Context.currentPos()}],
			mode: INormal
		});
		/* imports.push({
			path: [for (v in (ab.module + (ab.module != '' ? '.' : '') + ab.name).split('.')) {name: v, pos: Context.currentPos()}],
			mode: INormal
		}); */
		// trace(imports);
		
		function getTypePath(tt:Dynamic, ?ty:Dynamic) {
			if (tt.isPrivate || tt.name.length <= 1 || tt.name == ty?.name) return null;
			
			return (tt.module + (tt.module.length > 0 ? '.' : '') + tt.name);
		}
		function tryImport(ty:Dynamic):Bool {
			var pack:Array<String> = ty.module.split('.');
			for (t in Context.getModule(pack.join('.'))) {
				var p = null;
				
				switch (t) {
					case TEnum(r, _): p = getTypePath(r.get(), ty);
					case TInst(r, _): p = getTypePath(r.get(), ty);
					case TType(r, _): p = getTypePath(r.get(), ty);
					case TAbstract(r, _): p = getTypePath(r.get(), ty);
					default:
				}
				if (p == null) return false;
				
				imports.push({
					path: [for (v in p.split('.')) {name: v, pos: Context.currentPos()}],
					mode: INormal
				});
			}
			
			return true;
		}
		function stripComplex(t:ComplexType):ComplexType { // just strip the params
			return switch(t) {
				case TPath(p):
					if (p.name.length <= 1) macro:Dynamic;
					else TPath({name: p.name, pack: p.pack.copy(), sub: p.sub});
				case TOptional(t):
					TOptional(stripComplex(t));
				default:
					throw 'Invalid $t';
			}
		}
		function toComplex(t:haxe.macro.Type, includeParams:Bool = false):ComplexType {
			function toTypeParam(params:Array<haxe.macro.Type>):Array<TypeParam> {
				return [for (t in params) TPType(toComplex(t))];
			}
			function stuff(r:Dynamic, p:Array<haxe.macro.Type>) {
				var ct = r.get();
				if (ct.name.length <= 1) { // constructible bs
					return macro:Dynamic;
				} else {
					return TPath({name: ct.name, pack: ct.pack, params: (includeParams ? toTypeParam(p) : null)});
				}
			}
			
			return switch(t) {
				case TInst(r, p): stuff(r, p);
				case TType(r, p): stuff(r, p);
				case TEnum(r, p): stuff(r, p);
				case TAbstract(r, p): stuff(r, p);
				case TDynamic(_): macro:Dynamic;
				default: macro:Dynamic; //throw 'Invalid $t'; TODO tfun??
			}
		}
		function getFullComplex(t:ComplexType, includeParams:Bool = false):ComplexType {
			if (t == null) return null;
			return toComplex(t.toType(), includeParams);
		}
		function ex(expr:ExprDef):Expr {
			return {pos: Context.currentPos(), expr: expr};
		}
		
		var tt = ab.type, t;
		tt = switch (tt) {
			case TType(r, _): r.get().type;
			default: tt;
		}
		var t = toComplex(tt);
		var st = macro $v {ComplexTypeTools.toString(t)};
		var castExpr = (isEnum ?
			macro if (!_enumValues.contains(v) && !_enumMap.exists(v)) throw('Can\'t cast ' + v + ' to ' + impl)
			:
			macro if (AbstractTools.resolveName(v) != $st) throw('Can\'t cast ' + v + ' to ' + impl)
		);
		
		var enumI = 0;
		var enumIndex:Array<Expr> = (isEnum ? [] : null);
		var enumMap:Map<String, Int> = (isEnum ? [] : null);
		var enumConstructors:Array<String> = (isEnum ? [] : null);
		cls.fields.push({
			name: 'tryCast', pos: Context.currentPos(), access: [AStatic],
			kind: FFun({
				args: [{name: 'v', type: macro:Dynamic}], params: [], ret: macro:Void,
				expr: castExpr
			})
		});
		// trace(expr.toString());
		
		var fromExpr = [macro return null];
		var toExpr = [macro return null];
		
		fromExpr.unshift(macro if (Type.getClass(v) == $p {[cls.name]}) return v.__a);
		toExpr.unshift(macro if (t == $v {fullPath.join('.')}) return __a);
		
		if (isEnum) {
			fromExpr.unshift(macro {
				if (_enumValues.contains(v)) return v;
				else if (_enumMap.exists(v)) return _enumValues[_enumMap.get(v)];
			});
		} else {
			for (from in ab.from) {
				if ((t = toComplex(from.t)) == null) continue;
				st = macro $v {ComplexTypeTools.toString(t)};
				fromExpr.unshift(macro if (AbstractTools.resolveName(v) == $st) return v);
			}
			for (to in ab.to) {
				if ((t = toComplex(to.t)) == null) continue;
				st = macro $v {ComplexTypeTools.toString(t)};
				toExpr.unshift(macro if (t == $st) return __a);
			}
		}
		
		var props = [];
		var implPath = ab.impl.get().pack.copy(); implPath.push(ab.impl.get().name);
		var implStr = macro $v {implPath.join('.')};
		
		function afield(expr, typeIsAbstract) {
			var t = {name: cls.name, pack: ab.pack};
			var newExpr = (typeIsAbstract ? macro new $t($expr) : macro $expr);
			
			return newExpr;
		}
		function func(expr, returnIsAbstract) {
			return macro return ${afield(expr, returnIsAbstract)};
		}
		function matchAbstract(t:ComplexType) {
			if (t == null) return false;
			
			return switch (t) {
				case TPath(r): (r.name == ab.name);
				default: false;
			}
		}
		
		for (field in fields) {
			var name = field.name;
			if (name == '__init__') continue;
			
			if (field.access.contains(AOverload)) {
				// TODO: OPERATOR OVERLOAD
				continue;
			}
			if (field.access.contains(AStatic)) {
				switch (field.kind) {
					case FFun(f):
						var custom = false;
						for (meta in field.meta) {
							if (meta.name == ':from') {
								var ss;
								
								switch (f.args[0].type) {
									case TPath(p):
										var st = p.pack.copy();
										st.push(p.name);
										ss = macro $v {st.join('.')};
									default:
										throw 'Invalid ${f.args[0].type}';
								}
								
								var fc = macro return Reflect.getProperty(Type.resolveClass($implStr), $v{name})(v);
								fromExpr.unshift(macro if (AbstractTools.resolveName(v) == $ss) $fc);
								
								custom = true;
								continue;
							}
							if (meta.name == ':op') {
								// trace('op');
								
								custom = true;
								continue;
							}
						}
						
						if (custom) continue;
						
						var args = [];
						var stuff = [];
						for (i => arg in f.args) {
							if (i == 0 && props.contains(name)) continue; // remove "this"
							
							args.push({
								value: arg.value,
								type: macro:Dynamic,
								opt: arg.opt,
								name: arg.name,
								meta: arg.meta
							});
							stuff.push(macro $p {[arg.name]});
						}
						
						var isSetter = (props.contains(name) && StringTools.startsWith(name, 'set_'));
						var setterField = StringTools.replace(name, 'set_', '');
						
						cls.fields.push({
							name: name, pos: Context.currentPos(), access: [AStatic, APublic],
							kind: FFun({
								args: args, params: [],
								expr: func(isSetter ? macro {
									var cls = Type.resolveClass($implStr);
									$p {[setterField]} = Reflect.callMethod(cls, Reflect.field(cls, $v{name}), $a{stuff});
								} : macro {
									var cls = Type.resolveClass($implStr);
									Reflect.callMethod(cls, Reflect.field(cls, $v{name}), $a{stuff});
								}, matchAbstract(f.ret))
							})
						});
					
					case FVar(t, e):
						if (field.access.contains(APrivate) || !field.access.contains(APublic)) continue;
						
						cls.fields.push({
							name: name, pos: Context.currentPos(), access: [AStatic, APublic],
							kind: FProp('default', 'never', macro:Dynamic, afield(macro Reflect.field(Type.resolveClass($implStr), $v{name}), matchAbstract(t)))
						});
						
					default:
				}
			} else {
				switch (field.kind) {
					case FFun(f):
						var to = false;
						for (meta in field.meta) {
							if (meta.name == ':to') {
								t = stripComplex(f.ret);
								st = macro $v {ComplexTypeTools.toString(t)};
								var fc = macro return Reflect.getProperty(Type.resolveClass($implStr), $v{name})(__a);
								toExpr.unshift(macro if (t == $st) $fc);
								
								to = true;
								break;
							}
						}
						
						if (!to) {
							var args = [];
							var stuff = [macro __a];
							
							for (i => arg in f.args) {
								args.push({
									value: arg.value,
									type: macro:Dynamic,
									opt: arg.opt,
									name: arg.name,
									meta: arg.meta
								});
								stuff.push(macro $p {[arg.name]});
							}
							
							var setterExpr = null;
							var isSetter = StringTools.startsWith(name, 'set_');
							if (isSetter) {
								function transformThis(expr) {
									return switch(expr.expr) {
										case EVars(a):
											var vars = macro $expr;
											switch(vars.expr) {
												case EVars(a):
													for (i => v in a) {
														a[i] = {
															type: macro:Dynamic,
															namePos: v.namePos,
															name: v.name,
															meta: v.meta,
															isStatic: v.isStatic,
															isFinal: v.isFinal,
															expr: v.expr
														}
													}
												default:
											}
											vars;
										case EConst(CIdent('this')):
											{expr: EConst(CIdent('__a')), pos: expr.pos};
										default:
											// trace(expr);
											ExprTools.map(expr, transformThis);
									}
								}
								
								setterExpr = macro ${f.expr};
								setterExpr = setterExpr.map(transformThis);
								// trace(setterExpr.toString());
							}
							
							cls.fields.push({
								name: name, pos: Context.currentPos(), access: [APublic],
								kind: FFun({
									args: args, params: [],
									expr: func(isSetter ? setterExpr : macro {
										var cls = Type.resolveClass($implStr);
										Reflect.callMethod(cls, Reflect.field(cls, $v{name}), $a{stuff});
									}, matchAbstract(f.ret))
								})
							});
						}
					
					case FProp(get, set, _):
						props.push('get_$name');
						props.push('set_$name');
						
						cls.fields.push({
							name: name, pos: Context.currentPos(),
							kind: FProp(get, set, macro:Dynamic)
						});
						// trace('$get, $set, $t ');
						
					case FVar(t, e):
						if (isEnum) {
							enumConstructors.push(name);
							enumMap.set(name, enumI ++);
							enumIndex.push(e);
						}
										
					default:
				}
			}
		}
		/*trace('FROM: ' + (macro $b {fromExpr}).toString());
		trace('TO: ' + (macro $b {toExpr}).toString());
		trace('--------------------------- finisched');*/
		
		cls.fields.push({
			name: 'set_value', pos: Context.currentPos(), access: [APrivate, AOverride],
			kind: FFun({args: [{name: 'v', type: macro:Dynamic}], params: [], expr: macro {
				var r = resolveFrom(v);
				if (r == null) throw ('Can\'t cast ' + v + ' to ' + impl);
				return __a = r;
			}})
		});
		cls.fields.push({
			name: 'resolveFrom', pos: Context.currentPos(), access: [APublic, AStatic],
			kind: FFun({args: [{name: 'v', type: macro:Dynamic}], params: [], expr: macro $b {fromExpr}, ret: macro:Dynamic})
		});
		cls.fields.push({
			name: 'resolveTo', pos: Context.currentPos(), access: [APublic, AOverride],
			kind: FFun({args: [{name: 't', type: macro:String}], params: [], expr: macro $b {toExpr}, ret: macro:Dynamic})
		});
		
		cls.fields.push({
			name: '_enumMap', pos: Context.currentPos(), access: [APrivate, AStatic],
			kind: FProp('default', 'never', macro:Map<String, Int>, macro $v {enumMap})
		});
		cls.fields.push({
			name: '_enumConstructors', pos: Context.currentPos(), access: [APrivate, AStatic],
			kind: FProp('default', 'never', macro:Array<String>, macro $v {enumConstructors})
		});
		cls.fields.push({
			name: '_enumValues', pos: Context.currentPos(), access: [APrivate, AStatic],
			kind: FProp('default', 'never', macro:Array<Dynamic>, (isEnum ? macro $a {enumIndex} : null))
		});
		
		Context.defineModule(ab.pack.join('.') + (ab.pack.length > 0 ? '.' : '') + cls.name, [cls], imports);
		
		return fields;
	}
}