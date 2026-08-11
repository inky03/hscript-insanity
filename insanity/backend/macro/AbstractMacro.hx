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
	var implName:String;
	var underlying:AbstractTypeCast;
	
	var methods:Map<String, AbstractMethodInfo>;
	var properties:Map<String, AbstractPropertyInfo>;
	var overloads:Map<String, Array<AbstractMethodInfo>>;
	
	var from:Map<AbstractTypeCast, Null<String>>;
	var to:Map<AbstractTypeCast, Null<String>>;
	
	var ?read:String;
	var ?write:String;
}

typedef AbstractPropertyInfo = {
	var isStatic:Bool;
	
	var ?get:AbstractProperty;
	var ?set:AbstractProperty;
}

typedef AbstractMethodInfo = {
	var isStatic:Bool;
	
	var ?commutative:Bool;
	var ?type:AbstractTypeCast; // OVERLOAD
	var ?op:String;
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
		
		var path:Array<String> = ab.module.split('.');
		path.push(ab.name);
		
		var implPath:Array<String> = ab.module.split('.');
		if (implPath.length > 0) implPath[implPath.length - 1] = '_${implPath[implPath.length - 1]}';
		implPath.push('${ab.name}_Impl_');
		
		var info:AbstractInfo = {
			implName: implPath.join('.'),
			underlying: typeToAbstractTypeCast(ab.type),
			
			methods: [],
			properties: [],
			overloads: [],
			
			from: [],
			to: [],
			
			read: ab.resolve?.name,
			write: ab.resolveWrite?.name
		};
		
		var printer = new haxe.macro.Printer();
		
		for (to in ab.to) {
			info.to.set(typeToAbstractTypeCast(to.t), to.field?.name);
		}
		for (from in ab.from) {
			info.from.set(typeToAbstractTypeCast(from.t), from.field?.name);
		}
		
		for (field in fields) {
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
					var method:AbstractMethodInfo = {isStatic: isStatic};
					
					var metas = field.meta;
					if (metas != null) {
						for (meta in metas) {
							if (meta.name == ':commutative') method.commutative = true;
							
							if (meta.name == ':op') {
								switch (meta.params[0].expr) {
									case EBinop(binop, _, _):
										method.op = printer.printBinop(binop);
										
										method.type = typeToAbstractTypeCast(fun.args[1].type.toType());
										
									default:
										// throw '???';
								}
								
								if (method.op != null) {
									if (!info.overloads.exists(method.op))
										info.overloads.set(method.op, []);
									
									info.overloads.get(method.op).push(method);
								}
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