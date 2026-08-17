package insanity.backend.types;

import insanity.backend.macro.AbstractMacro;
import insanity.backend.types.Scripted;

import insanity.custom.InsanityReflect;
import insanity.custom.InsanityType;

import insanity.custom.InsanityReflect as Reflect;
import insanity.custom.InsanityType as Type;

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
	
	@:access(insanity.backend.types.InsanityAbstractValue)
	public static function getAbstractTypeCast(v:Dynamic):AbstractTypeCast {
		if (v is InsanityAbstractValue) return ATType(v.info.name);
		
		if (v is Int) {
			return ATType('Int');
		} else if (v is Float) {
			return ATType('Float');
		} else if (v is String) {
			return ATType('String');
		} else if (v is Bool) {
			return ATType('Bool');
		} else if (v is Class) {
			return ATType('Class');
		} else if (v is Enum) {
			return ATType('Enum');
		} else if (v is Array) {
			return ATType('Array');
		} // wow
		
		var cl = Type.getClass(v);
		if (cl != null) return ATType(Type.getClassName(cl));
		
		var en = Type.getEnum(v);
		if (en != null) return ATType(Type.getEnumName(cl));
		
		if (Reflect.isFunction(v)) return ATMethod;
		
		if (Reflect.isObject(v)) return ATStruct;
		
		return ATDynamic;
	}
	
	public static inline function abstractTypeCastToString(t:AbstractTypeCast):String {
		return switch (t) {
			case ATType(t): t;
			case ATMethod: 'Function'; // glup
			case ATDynamic: 'Dynamic';
			case ATStruct: 'Object'; // glup 2
		}
	}
	
	public static inline function isAbstract(o:Dynamic):Bool {
		return (o is InsanityAbstractValue);
	}
}

class InsanityAbstract implements ICustomReflection implements ICustomClassType {
	public var info:AbstractInfo;
	public var impl:Class<Dynamic>;
	
	public var isEnum:Bool = false;
	
	public static var needOps:Map<String, Bool> = [for (op in ['+', '-', '*', '/', '%', '&', '|', '^', '<<', '>>', '>>>']) op => true];
	
	var methodCache:Map<String, Dynamic> = [];
	
	#if cpp var resolve:String -> Dynamic; #end
	
	public function new(info:AbstractInfo) {
		this.info = info;
		this.impl = Type.resolveClass(info.implName);
		
		isEnum = info.isEnum;
		
		#if cpp resolve = Reflect.field(impl, 'insanityCppResolve'); #end
	}
	
	public function create(v:Dynamic):InsanityAbstractValue {
		return new InsanityAbstractValue(this, v is InsanityAbstractValue ? v.__a : v);
	}
	
	public function castFrom(v:Dynamic):InsanityAbstractValue {
		if (v is InsanityAbstractValue && v.info.name == info.name) return v;
		
		var type:AbstractTypeCast = AbstractTools.getAbstractTypeCast(v);
		
		var test:AbstractTypeCast = type;
		if (!info.from.exists(test) && v is Int && info.from.exists(ATType('Float'))) test = ATType('Float');
		if (!info.from.exists(test) && info.from.exists(ATDynamic)) test = ATDynamic;
		
		if (info.from.exists(test)) {
			var from:Null<String> = info.from.get(test);
			
			return create(from == null ? v : Reflect.callMethod(impl, Reflect.field(impl, from), [v]));
		} else {
			throw 'Can\'t cast ${AbstractTools.abstractTypeCastToString(type)} to ${info.name}';
			return null;
		}
	}
	
	public function reflectHasField(field:String):Bool {
		var f:Null<AbstractPropertyInfo> = info.properties.get(field);
		
		if (f != null && f.isStatic) return true;
		
		var m:Null<AbstractMethodInfo> = info.methods.get(field);
		
		return (m != null && m.isStatic);
	}
	
	public function reflectGetField(field:String):Dynamic {
		var f:Null<AbstractPropertyInfo> = info.properties.get(field);
		
		if (f != null && (f.isStatic || (isEnum && f.isAbstract))) {
			final r:Dynamic = #if cpp resolve(field) #else Reflect.field(impl, field) #end;
			
			return (f.isAbstract ? create(r) : r);
		} else {
			return cacheMethod(field);
		}
	}
	public function reflectSetField(field:String, value:Dynamic):Dynamic {
		var f:Null<AbstractPropertyInfo> = info.properties.get(field);
		
		if (f != null && f.isStatic) {
			Reflect.setField(impl, field, value);
		} else if (info.methods.exists(field)) {
			throw 'Cannot rebind this method';
		}
		
		return value;
	}
	
	public function reflectGetProperty(property:String):Dynamic {
		var f:Null<AbstractPropertyInfo> = info.properties.get(property);
		
		if (f != null && (f.isStatic || (isEnum && f.isAbstract))) {
			final r:Dynamic = #if cpp resolve(property) #else Reflect.getProperty(impl, property) #end;
			
			return (f.isAbstract ? create(r) : r);
		} else {
			return cacheMethod(property);
		}
	}
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic {
		var f:Null<AbstractPropertyInfo> = info.properties.get(property);
		
		if (f != null && f.isStatic) Reflect.setProperty(impl, property, value);
		
		return value;
	}
	
	public function reflectListFields():Array<String> {
		var fields = [for (name => f in info.properties) if (f.isStatic || (isEnum && f.get == ADefault && f.set == ADefault)) name];
		
		for (name => m in info.methods) if (m.isStatic) fields.push(name);
		
		return fields;
	}
	
	public function typeCreateInstance(arguments:Array<Dynamic>):Dynamic {
		return create(Reflect.callMethod(impl, Reflect.field(impl, '_new'), arguments));
	}
	public function typeCreateEmptyInstance():Dynamic {
		return throw 'Not supported';
	}
	public function typeGetClass():Dynamic {
		return null;
	}
	public function typeGetClassFields():Array<String> {
		return reflectListFields();
	}
	public function typeGetInstanceFields():Array<String> {
		var fields = [for (name => f in info.properties) if (!f.isStatic) name];
		
		for (name => m in info.methods) if (!m.isStatic) fields.push(name);
		
		return fields;
	}
	
	inline function cacheMethod(field:String):Dynamic {
		var m:Null<AbstractMethodInfo> = info.methods.get(field);
		
		if (m == null || !m.isStatic) {
			return null;
		} else {
			if (!methodCache.exists(field)) {
				final f = Reflect.field(impl, field);
				
				if (m.returnsAbstract) {
					methodCache.set(field, Reflect.makeVarArgs((args) -> create(Reflect.callMethod(impl, f, args))));
				} else {
					methodCache.set(field, f);
				}
			}
			
			return methodCache.get(field);
		}
	}
}

class InsanityAbstractValue implements ICustomReflection {
	@:noCompletion public var base:InsanityAbstract;
	
	@:noCompletion public var info:AbstractInfo;
	@:noCompletion public var impl:Class<Dynamic>;
	
	@:noCompletion public var __a(default, set):Dynamic;
	
	var methodCache:Map<String, Dynamic> = [];
	var implFields:Map<String, Dynamic>;
	
	public function new(base:InsanityAbstract, value:Dynamic) {
		this.base = base;
		
		info = base.info;
		impl = base.impl;
		
		implFields = [for (name in info.properties.keys()) name => Reflect.field(impl, name)];
		for (name in info.methods.keys()) implFields.set(name, Reflect.field(impl, name));
		
		__a = value;
	}
	
	function cacheMethod(field:String):Dynamic {
		var m:Null<AbstractMethodInfo> = info.methods.get(field);
		
		if (m == null || m.isStatic) {
			return null;
		} else {
			if (!methodCache.exists(field)) {
				if (m.setsSelf) {
					methodCache.set(field, Reflect.makeVarArgs((args) -> { __a = callImpl(field, args); }));
				} else if (m.returnsAbstract) {
					methodCache.set(field, Reflect.makeVarArgs((args) -> { base.create(callImpl(field, args)); }));
				} else {
					methodCache.set(field, Reflect.makeVarArgs((args) -> { callImpl(field, args); }));
				}
			}
			
			return methodCache.get(field);
		}
	}
	
	public function reflectHasField(field:String):Bool {
		var f:Null<AbstractPropertyInfo> = info.properties.get(field);
		
		if (f != null && !f.isStatic) return true;
		
		var m:Null<AbstractMethodInfo> = info.methods.get(field);
		
		return (m != null && !m.isStatic);
	}
	
	public function reflectGetField(field:String):Dynamic { return null; }
	public function reflectSetField(field:String, value:Dynamic):Dynamic { return null; }
	
	public function reflectGetProperty(property:String):Dynamic {
		var f:Null<AbstractPropertyInfo> = info.properties.get(property);
		
		if (f != null && !f.isStatic) {
			return switch (f.get) {
				case ADefault: null;
				case ADynamic: callImpl('get_$property', []);
				case ANever: 'This expression cannot be accessed for reading';
			}
		} else {
			var m = cacheMethod(property);
			if (m != null) return m;
			
			if (info.forwards.exists(property)) return Reflect.getProperty(__a, property);
			
			return op(AResolve(false, null), null, property);
		}
	}
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic {
		var f:Null<AbstractPropertyInfo> = info.properties.get(property);
		
		if (f != null && !f.isStatic) {
			return switch (f.get) {
				case ADefault: null;
				case ADynamic: __a = callImpl('insanityset_$property', [value]); value;
				case ANever: 'This expression cannot be accessed for writing';
			}
		} else if (info.methods.exists(property)) {
			throw 'Cannot rebind this method';
		}
		
		if (info.forwards.exists(property)) {
			Reflect.setProperty(__a, property, value);
			return value;
		}
		
		return op(AResolve(true, AbstractTools.getAbstractTypeCast(value)), value, property);
	}
	
	public function reflectListFields():Array<String> {
		var fields = [for (name => f in info.properties) if (!f.isStatic) name];
		
		for (name => m in info.methods) if (!m.isStatic) fields.push(name);
		
		return fields;
	}
	
	public function toString():String {
		var f:Null<AbstractPropertyInfo> = info.properties.get('toString');
		
		if (f != null && !f.isStatic) return callImpl('toString', []);
		
		return Std.string(__a); //info.name;
	}
	
	function callImpl(field:String, arguments:Array<Dynamic>):Dynamic {
		arguments.unshift(__a);
		
		return Reflect.callMethod(impl, implFields.get(field), arguments);
	}
	
	// should deprecate now maybe
	public inline function binop(op:String, ?v:Dynamic):Dynamic {
		return this.op(ABinop(op, AbstractTools.getAbstractTypeCast(v)), v);
	}
	
	public function increment(prefix:Bool, delta:Int):Bool {
		final unop:AbstractOp = AUnop(delta > 0 ? '++' : '--', !prefix);
		
		if (!prefix) throw '(A ${delta > 0 ? '++' : '--'}) is currently unsupported in abstracts'; // todo
		
		return (op(unop) != null);
	}
	
	public function findOverload(op:AbstractOp, ?v:Dynamic, ?f:Dynamic):Dynamic {
		if (info.overloads.exists(op)) return info.overloads.get(op);
		
		var field:Null<String> = null;
		
		switch (op) { // other posible types
			case ABinop(op, type):
				if (v is Int) field ??= info.overloads.get(ABinop(op, ATType('Float')));
				field ??= info.overloads.get(ABinop(op, ATDynamic));
				
			case AArray(write, readType, _):
				inline function find():Void {
					if (v is Int) field ??= info.overloads.get(AArray(write, readType, ATType('Float')));
					field ??= info.overloads.get(AArray(write, readType, ATDynamic));
				}
				
				find();
				
				if (field == null) {
					for (k in info.overloads.keys()) {
						if (f is Int && k.match(AArray(_, ATType('Float'), _))) {
							readType = ATType('Float');
							find();
						}
						
						if (k.match(AArray(_, ATDynamic, _))) {
							readType = ATDynamic;
							find();
						}
						
						if (field == null) break;
					}
				}
			
			case AResolve(true, _):
				if (v is Int) field ??= info.overloads.get(AResolve(true, ATType('Float')));
				field ??= info.overloads.get(AResolve(true, ATDynamic));
			
			default:
		}
		
		return field;
	}
	
	public function op(op:AbstractOp, ?v:Dynamic, ?f:Dynamic):Dynamic {
		final field:Null<String> = findOverload(op, v, f);
		
		if (field == null) return null;
		
		var method:AbstractMethodInfo = info.methods.get(field);
		
		final r:Dynamic = callImpl(field, switch (op) {
			case ABinop(_, _): [v is InsanityAbstractValue ? v.__a : v];
			case AUnop(_, _): [];
			case AResolve(false, _) | AArray(false, _, _): [f];
			case AResolve(true, _) | AArray(true, _, _): [f, v is InsanityAbstractValue ? v.__a : v];
		});
		
		if (method.setsSelf) return (__a = r);
		
		return (method.returnsAbstract ? base.create(r) : r);
	}
	
	function set___a(v:Dynamic):Dynamic {
		return __a = v;
	}
	
	public function castTo(v:Dynamic):Dynamic {
		if (v is InsanityAbstract && v.info.name == info.name) return v;
		
		final cls:String = Type.getClassName(v);
		var type:AbstractTypeCast = ATType(cls);
		
		var test:AbstractTypeCast = type;
		if (!info.to.exists(test) && __a is Int && info.to.exists(ATType('Float'))) test = ATType('Float');
		if (!info.to.exists(test) && info.to.exists(ATDynamic)) test = ATDynamic;
		
		if (info.to.exists(test)) {
			var to:Null<String> = info.to.get(test);
			
			return (to == null ? __a : callImpl(to, []));
		} else {
			throw 'Can\'t cast ${info.name} to ${cls}';
			return null;
		}
	}
}
