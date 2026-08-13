package insanity.backend.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;
using haxe.macro.ComplexTypeTools;
#end

typedef AbstractInfo = {
	var isEnum:Bool;
	
	var name:String;
	var implName:String;
	var underlying:AbstractTypeCast;
	
	var methods:Map<String, AbstractMethodInfo>;
	var properties:Map<String, AbstractPropertyInfo>;
	var overloads:Map<AbstractOp, String>;
	
	var from:Map<AbstractTypeCast, Null<String>>;
	var to:Map<AbstractTypeCast, Null<String>>;
}

typedef AbstractPropertyInfo = {
	var isStatic:Bool;
	
	var ?get:AbstractProperty;
	var ?set:AbstractProperty;
}

typedef AbstractMethodInfo = {
	var isStatic:Bool;
	var setsSelf:Bool;
	var returnsAbstract:Bool;
	
	// OVERLOAD
	var ?isOverload:Bool;
	var ?isCommutative:Bool;
	
	var ?op:AbstractOp;
}

enum AbstractOp {
	AUnop(op:String, postFix:Bool);
	ABinop(op:String, type:AbstractTypeCast);
	
	AArray(write:Bool, readType:AbstractTypeCast, writeType:Null<AbstractTypeCast>);
	AResolve(write:Bool, writeType:Null<AbstractTypeCast>);
}

enum AbstractProperty {
	ADefault;
	ADynamic;
	ANever;
}

enum AbstractTypeCast {
	ATType(name:String);
	ATDynamic;
	ATMethod;
	ATStruct;
}

class AbstractMacro {
	static inline function typeName(t:Dynamic):String {
		var path = t.pack.copy();
		path.push(t.name);
		
		return path.join('.');
	}
	
	static inline function typeToAbstractTypeCast(type:haxe.macro.Type):AbstractTypeCast {
		return switch (type) {
			case TMono(r): typeToAbstractTypeCast(r.get());
			case TEnum(r, _): ATType(typeName(r.get()));
			case TInst(r, _): ATType(typeName(r.get()));
			case TType(r, _): typeToAbstractTypeCast(r.get().type);
			case TFun(_, _): ATMethod;
			case TLazy(f): typeToAbstractTypeCast(f());
			case TAbstract(r, _): ATType(typeName(r.get()));
			case TDynamic(t): (t != null ? typeToAbstractTypeCast(t) : ATDynamic);
			case TAnonymous(_): ATStruct;
		}
	}
	
	public static macro function build():Array<Field> {
		var pos = Context.currentPos();
		var type = Context.getLocalType();
		var fields = Context.getBuildFields();
		
		var c:ClassType;
		var ab:AbstractType;
		
		switch (type) {
			case TInst(r, params):
				c = r.get();
				
				if (c.module == 'UInt') return fields; // akward
				
				switch (c.pack[0]) {
					case 'haxe' | 'hl' | 'cpp' | 'neko' | 'js' | 'cs' | 'lua' | 'php' | 'macro' | 'java' | 'flash' | 'python':
						return fields;
						
					default:
				}
				
				switch (c.kind) {
					case KAbstractImpl(a):
						ab = a.get();
						
						if (ab.meta.has(':coreType'))
							return fields;
						
					default:
						return fields;
				}
				
			default:
				return fields;
		}
		
		var path:Array<String> = ab.pack.copy();
		path.push(ab.name);
		
		var implPath:Array<String> = ab.module.split('.');
		if (implPath.length > 0) implPath[implPath.length - 1] = '_${implPath[implPath.length - 1]}';
		implPath.push('${ab.name}_Impl_');
		
		var info:AbstractInfo = {
			isEnum: ab.meta.has(':enum'),
			
			name: path.join('.'),
			implName: implPath.join('.'),
			underlying: typeToAbstractTypeCast(ab.type),
			
			methods: [],
			properties: [],
			overloads: [],
			
			from: [],
			to: []
		};
		
		var printer = new haxe.macro.Printer();
		
		for (to in ab.to) {
			info.to.set(typeToAbstractTypeCast(to.t), to.field?.name);
		}
		for (from in ab.from) {
			info.from.set(typeToAbstractTypeCast(from.t), from.field?.name);
		}
		
		function matchAbstract(t:ComplexType) {
			if (t == null) return false;
			
			return switch (t) {
				case TPath(r): (r.name == ab.name);
				default: false;
			}
		}
		
		for (field in fields) {
			if (field.name.indexOf('insanity') == 0 || field.name == '_new') continue; // dont need to list these..
			
			final isStatic:Bool = (field.access != null && field.access.contains(AStatic));
			
			switch (field.kind) {
				case FVar(t, e):
					var prop:AbstractPropertyInfo = {isStatic: isStatic};
					
					prop.get = prop.set = ADefault;
					
					info.properties.set(field.name, prop);
					
				case FProp(get, set, t, e):
					var prop:AbstractPropertyInfo = {isStatic: isStatic};
					
					prop.get = switch (get) {
						default: ADefault;
						case 'get' | 'dynamic': ADynamic;
						case 'never' | 'null': ANever;
					}
					prop.set = switch (set) {
						default: ADefault;
						case 'get' | 'dynamic': ADynamic;
						case 'never' | 'null': ANever;
					}
					
					info.properties.set(field.name, prop);
					
				case FFun(fun):
					var method:AbstractMethodInfo = {isStatic: isStatic, returnsAbstract: matchAbstract(fun.ret), setsSelf: false};
					
					if (field.name.indexOf('set_') < 0) {
						function testSet(e:Expr):Void {
							if (e == null) return;
							
							return ExprTools.iter(e, function(e:Expr) {
								switch (e.expr) {
									case EBinop(OpAssign, {pos: _, expr: EConst(CIdent('this'))}, _) |
										EBinop(OpAssignOp(_), {pos: _, expr: EConst(CIdent('this'))}, _):
										// trace('${ab.name}.${field.name} sets  self');
										method.setsSelf = true;
									
									default:
										testSet(e);
								}
							});
						};
						
						testSet(fun.expr);
					}
					
					if (!isStatic && field.name.indexOf('set_') == 0) {
						function mapSet(e:Expr):Expr {
							if (e == null) return null;
							
							return ExprTools.map(e, function(e:Expr) {
								return switch (e.expr) {
									case EReturn(_):
										{pos: e.pos, expr: EReturn({pos: e.pos, expr: EConst(CIdent('this'))})};
									
									default:
										mapSet(e);
								}
							});
						};
						
						fields.push({
							pos: pos,
							meta: field.meta,
							name: 'insanity${field.name}',
							access: field.access,
							
							kind: FFun({
								args: fun.args,
								params: fun.params,
								expr: mapSet(fun.expr)
							})
						});
					}
					
					var metas = field.meta;
					if (metas != null) {
						for (meta in metas) {
							if (meta.name == ':commutative') method.isCommutative = true;
							
							if (meta.name == ':op') {
								switch (meta.params[0].expr) {
									case EBinop(binop, _, _):
										method.op = ABinop(printer.printBinop(binop), typeToAbstractTypeCast(fun.args[1].type.toType()));
									
									case EUnop(unop, postFix, _):
										method.op = AUnop(printer.printUnop(unop), postFix);
									
									case EField(_, _, _):
										final write:Bool = (fun.args.length == 2);
										method.op = AResolve(write, write ? typeToAbstractTypeCast(fun.args[1].type.toType()) : null);
									
									case EArrayDecl(_):
										final write:Bool = (fun.args.length == 2);
										method.op = AArray(write, typeToAbstractTypeCast(fun.args[0].type.toType()), write ? typeToAbstractTypeCast(fun.args[1].type.toType()) : null);
										
									default:
										throw '??? (${meta.params[0].toString()})';
								}
								
								method.isOverload = true;
								
								info.overloads.set(method.op, field.name);
							}
						}
					}
					
					info.methods.set(field.name, method);
			}
		}
		
		c.meta.add(':insanityAbstractInfo', [macro $v {path.join('.')}, macro $v {haxe.Serializer.run(info)}], pos);
		
		return fields;
	}
	
	static var _name:String = 'insanity.backend.macro.AbstractMacro';
	
	public static macro function listAbstractInfos() {
		Context.onAfterTyping(function(types) {
			var self = TypeTools.getClass(Context.getType(_name));
			if (self.meta.has('insanityAbstractInfo')) return;
			
			var map:Map<String, Dynamic> = [];
			
			for (type in types) {
				switch (type) {
					case TClassDecl(r):
						var meta = r.get().meta.extract(':insanityAbstractInfo');
						
						if (meta.length > 0) map.set(meta[0].params[0].getValue(), haxe.Unserializer.run(meta[0].params[1].getValue()));
						
					default:
				}
			}
			
			self.meta.add('insanityAbstractInfo', [macro $v {haxe.Serializer.run(map)}], self.pos);
		});
		
		return macro haxe.Unserializer.run(haxe.rtti.Meta.getType($p {_name.split('.')}).insanityAbstractInfo[0]);
	}
}