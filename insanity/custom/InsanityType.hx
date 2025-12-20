package insanity.custom;

import insanity.backend.types.Scripted.InsanityScriptedClass;
import Type.ValueType;

class InsanityType {
	public static var environment:Environment = null;
	
	public static inline function getClass(o:Dynamic):Dynamic {
		if (o is ICustomClassType) {
			var o:ICustomClassType = cast o;
			return o.typeGetClass();
		} else {
			return Type.getClass(o);
		}
	}
	
	public static inline function getEnum(o:EnumValue):Enum<Dynamic> {
		return Type.getEnum(o);
	}
	
	public static inline function getSuperClass(c:Class<Dynamic>):Class<Dynamic> {
		return Type.getSuperClass(c);
	}
	
	public static inline function getClassName(c:Dynamic):String {
		if (c is InsanityScriptedClass)
			return cast(c, InsanityScriptedClass).path;
		
		return Type.getClassName(c);
	}
	
	public static inline function getEnumName(e:Enum<Dynamic>):String {
		return Type.getEnumName(e);
	}
	
	public static inline function resolveClass(name:String):Dynamic {
		var t:Dynamic = environment?.resolve(name);
		if (t != null) return t;
		
		t = Type.resolveClass(name);
		if (t == null) return null;
		
		return (Config.typeProxy.get(Type.getClassName(t)) ?? t); // prevent resolved type from bypassing proxy (lol)
	}
	
	public static inline function resolveEnum(name:String):Enum<Dynamic> {
		return Type.resolveEnum(name);
	}
	
	public static inline function createInstance<T>(cl:Class<T>, args:Array<Dynamic>):T {
		if (cl is ICustomClassType) {
			var cl:ICustomClassType = cast cl;
			return cl.typeCreateInstance(args);
		} else {
			return Type.createInstance(cl, args);
		}
	}
	
	public static inline function createEmptyInstance<T>(cl:Class<T>):T {
		return Type.createEmptyInstance(cl);
	}
	
	public static inline function createEnum<T>(e:Enum<T>, constr:String, ?params:Array<Dynamic>):T {
		return Type.createEnum(e, constr, params);
	}
	
	public static inline function createEnumIndex<T>(e:Enum<T>, index:Int, ?params:Array<Dynamic>):T {
		return Type.createEnumIndex(e, index, params);
	}
	
	public static inline function getInstanceFields(c:Class<Dynamic>):Array<String> {
		return Type.getInstanceFields(c);
	}
	
	public static inline function getClassFields(c:Class<Dynamic>):Array<String> {
		return Type.getClassFields(c);
	}
	
	public static inline function getEnumConstructs(e:Enum<Dynamic>):Array<String> {
		return Type.getEnumConstructs(e);
	}
	
	public static inline function typeof(v:Dynamic):ValueType {
		return Type.typeof(v);
	}
	
	public static inline function enumEq<T:EnumValue>(a:T, b:T):Bool {
		return Type.enumEq(a, b);
	}
	
	public static inline function enumConstructor(e:EnumValue):String {
		return Type.enumConstructor(e);
	}
	
	public static inline function enumParameters(e:EnumValue):Array<Dynamic> {
		return Type.enumParameters(e);
	}
	
	public static inline function enumIndex(e:EnumValue):Int {
		return Type.enumIndex(e);
	}
	
	public static inline function allEnums<T>(e:Enum<T>):Array<T> {
		return Type.allEnums(e);
	}
}

interface ICustomClassType extends ICustomType {
	public function typeCreateInstance(args:Array<Dynamic>):Dynamic;
	public function typeGetClass():Dynamic;
}

interface ICustomType {}