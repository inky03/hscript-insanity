package insanity.backend.types;

using insanity.backend.macro.TypeRegistry;

class AbstractTools {
	public static function resolve(path:String):Class<HScriptAbstract> {
		var t = (TypeRegistry.fromPath(path) ?? TypeRegistry.fromCompilePath(path));
		
		if (t != null) {
			var a = Type.resolveClass('insanity.backend._abstract._Abstract_${StringTools.replace(t[0].compilePath(), '.', '_')}');
			
			if (a != null)
				return cast a;
		}
		
		trace('Can\'t resolve abstract $path');
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
			if (Type.getSuperClass(vv) == HScriptAbstract) {
				return (vv.impl ?? 'unknown');
			} else {
				return Type.getClassName(vv);
			}
		}
		
		return 'unknown';
	}
	
	public static function getEnumConstructs(a:Class<HScriptAbstract>):Array<String> {
		var a:Dynamic = a;
		
		if (a.isEnum) return a._enumConstructors.copy();
		
		throw '${a?.impl ?? a} is not an enum abstract';
		return null;
	}
	
	public static function createEnum(a:Class<HScriptAbstract>, n:String):String {
		var a:Dynamic = a;
		
		if (a.isEnum)
			return Type.createInstance(a, [a._enumValues[a._enumMap.get(n) ?? -1]]);
		
		throw '${a?.impl ?? a} is not an enum abstract';
		return null;
	}
}

class HScriptAbstract {
	var value(get, set):Dynamic;
	var __a(default, null):Dynamic;
	
	public function new(v:Dynamic) { value = v; }
	
	// implemented in macro
	function get_value():Dynamic { return __a; }
	function set_value(v:Dynamic):Dynamic { return __a = v; }
	public function resolveTo(t:String):Dynamic { return null; }
}