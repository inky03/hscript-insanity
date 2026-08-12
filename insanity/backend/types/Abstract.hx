package insanity.backend.types;

import insanity.backend.macro.AbstractMacro;
import insanity.custom.InsanityReflect;
import insanity.custom.InsanityType;

using insanity.backend.TypeCollection;

class AbstractTools {
	public static var abstractInfos:Map<String, AbstractInfo> = AbstractMacro.listAbstractInfos();
	
	public static var abstracts:Map<String, InsanityAbstract> = []; // could maybe move this to typecollection
	
	public static function resolve(path:String):Null<InsanityAbstract> {
		var t = (TypeCollection.main.fromPath(path) ?? TypeCollection.main.fromCompilePath(path));
		
		final path:Null<String> = (t != null ? TypeCollection.compilePath(t[0]) : null);
		
		if (path != null && abstractInfos.exists(path)) {
			if (!abstracts.exists(path)) abstracts.set(path, new InsanityAbstract(abstractInfos.get(path)));
			
			return abstracts.get(path);
		}
		
		// trace('Can\'t resolve abstract $path');
		return null;
	}
	
	public static function resolveName(v:Dynamic):String {
		var vv:Dynamic = v;
		switch (Type.typeof(v)) {
			case TInt:
				return 'Int';
			case TFloat:
				return 'Float';
			case TBool:
				return 'Bool';
			case TObject:
				if (v is Enum) return Type.getEnumName(v);
			case TClass(c):
				vv = c;
			case TEnum(e):
				return Type.getEnumName(e);
			default:
				return 'unknown';
		}
		
		if (vv is Class) {
			if (Type.getSuperClass(vv) == InsanityAbstract) {
				return (vv.impl ?? 'unknown');
			} else {
				return Type.getClassName(vv);
			}
		}
		
		return 'unknown';
	}
	
	/*public static function getEnumConstructs(a:Class<InsanityAbstract>):Array<String> {
		var a:Dynamic = a;
		
		if (a.isEnum) return a._enumConstructors.copy();
		
		throw '${a?.impl ?? a} is not an enum abstract';
		return null;
	}
	
	public static function createEnum(a:Class<InsanityAbstract>, n:String):InsanityAbstract {
		var a:Dynamic = a;
		
		if (a.isEnum) return Type.createInstance(a, [a._enumValues[a._enumMap.get(n) ?? -1]]);
		
		throw '${a?.impl ?? a} is not an enum abstract';
		return null;
	}
	
	public static function createEnumIndex(a:Class<InsanityAbstract>, i:Int):InsanityAbstract {
		var a:Dynamic = a;
		
		if (a.isEnum) return Type.createInstance(a, [a._enumValues[i]]);
		
		throw '${a?.impl ?? a} is not an enum abstract';
		return null;
	}*/
	
	public static inline function isAbstract(o:Dynamic):Bool {
		return (o is InsanityAbstractValue);
	}
}

class InsanityAbstract implements ICustomReflection {
	public var info:AbstractInfo;
	public var impl:Class<Dynamic>;
	
	public function new(info:AbstractInfo) {
		this.info = info;
		this.impl = Type.resolveClass(info.implName);
	}
	
	public function create(v:Dynamic):InsanityAbstractValue {
		return new InsanityAbstractValue(this, v);
	}
	
	public function reflectHasField(field:String):Bool {
		var f:Null<AbstractPropertyInfo> = info.properties.get(field);
		
		if (f != null && f.isStatic) return true;
		
		var m:Null<AbstractMethodInfo> = info.methods.get(field);
		
		return (m != null && m.isStatic);
	}
	
	public function reflectGetField(field:String):Dynamic {
		var f:Null<AbstractPropertyInfo> = info.properties.get(field);
		
		return (f != null && f.isStatic ? Reflect.field(impl, field) : null);
	}
	public function reflectSetField(field:String, value:Dynamic):Dynamic {
		var f:Null<AbstractPropertyInfo> = info.properties.get(field);
		
		if (f != null && f.isStatic) Reflect.setField(impl, field, value);
		
		return value;
	}
	
	public function reflectGetProperty(property:String):Dynamic {
		var f:Null<AbstractPropertyInfo> = info.properties.get(property);
		
		return (f != null && f.isStatic ? Reflect.getProperty(impl, property) : null);
	}
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic {
		var f:Null<AbstractPropertyInfo> = info.properties.get(property);
		
		if (f != null && f.isStatic) Reflect.setProperty(impl, property, value);
		
		return value;
	}
	
	public function reflectListFields():Array<String> {
		var fields = [for (name => f in info.properties) if (f.isStatic) name];
		
		for (name => m in info.methods) if (m.isStatic) fields.push(name);
		
		return fields;
	}
}

class InsanityAbstractValue implements ICustomReflection {
	var __base:InsanityAbstract;
	var __info:AbstractInfo;
	var __impl:Class<Dynamic>;
	
	var __v:Dynamic;
	
	var __methodCache:Map<String, Dynamic> = [];
	
	public function new(base:InsanityAbstract, value:Dynamic) {
		__base = base;
		__info = base.info;
		__impl = base.impl;
		__v = value;
	}
	
	inline function __cacheMethod(field:String):Dynamic {
		var m:Null<AbstractMethodInfo> = __info.methods.get(field);
		
		if (m == null || m.isStatic) {
			return null;
		} else {
			if (!__methodCache.exists(field)) {
				final f = Reflect.field(__impl, field);
				
				if (m.returnsAbstract) {
					__methodCache.set(field, Reflect.makeVarArgs((args) -> { args.unshift(__v); __base.create(Reflect.callMethod(__impl, f, args)); }));
				} else {
					__methodCache.set(field, Reflect.makeVarArgs((args) -> { args.unshift(__v); Reflect.callMethod(__impl, f, args); }));
				}
			}
			
			return __methodCache.get(field);
		}
	}
	
	public function reflectHasField(field:String):Bool {
		var f:Null<AbstractPropertyInfo> = __info.properties.get(field);
		
		if (f != null && !f.isStatic) return true;
		
		var m:Null<AbstractMethodInfo> = __info.methods.get(field);
		
		return (m != null && !m.isStatic);
	}
	
	public function reflectGetField(field:String):Dynamic { return null; }
	public function reflectSetField(field:String, value:Dynamic):Dynamic { return null; }
	
	public function reflectGetProperty(property:String):Dynamic {
		var f:Null<AbstractPropertyInfo> = __info.properties.get(property);
		
		if (f != null && !f.isStatic) {
			return switch (f.get) {
				case ADefault: null;
				case ADynamic: Reflect.callMethod(__impl, Reflect.field(__impl, 'get_$property'), [__v]);
				case ANever: 'This expression cannot be accessed for reading';
			}
		} else {
			return __cacheMethod(property);
		}
	}
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic {
		var f:Null<AbstractPropertyInfo> = __info.properties.get(property);
		
		if (f != null && !f.isStatic) {
			return switch (f.get) {
				case ADefault: null;
				case ADynamic: __v = Reflect.callMethod(__impl, Reflect.field(__impl, 'insanityset_$property'), [__v, value]); value;
				case ANever: 'This expression cannot be accessed for writing';
			}
		} else {
			return throw 'Cannot rebind this method';
		}
	}
	
	public function reflectListFields():Array<String> {
		var fields = [for (name => f in __info.properties) if (!f.isStatic) name];
		
		for (name => m in __info.methods) if (!m.isStatic) fields.push(name);
		
		return fields;
	}
	
	public function toString():String {
		var f:Null<AbstractPropertyInfo> = __info.properties.get('toString');
		
		if (f != null && !f.isStatic) return Reflect.callMethod(__impl, Reflect.field(__impl, 'toString'), [__v]);
		
		return __v;
	}
}
