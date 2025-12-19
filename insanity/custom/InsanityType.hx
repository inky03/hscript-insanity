package insanity.custom;

import Type.ValueType;

class InsanityType {
	public static inline function getClass<T>(o:T):Class<T> {
		return Type.getClass(o);
	}
	
	public static inline function getEnum(o:EnumValue):Enum<Dynamic> {
		return Type.getEnum(o);
	}
	
	public static inline function getSuperClass(c:Class<Dynamic>):Class<Dynamic> {
		return Type.getSuperClass(c);
	}
	
	public static inline function getClassName(c:Class<Dynamic>):String {
		return Type.getClassName(c);
	}
	
	public static inline function getEnumName(e:Enum<Dynamic>):String {
		return Type.getEnumName(e);
	}
	
	public static inline function resolveClass(name:String):Class<Dynamic> {
		return Type.resolveClass(name);
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
}

interface ICustomType {}