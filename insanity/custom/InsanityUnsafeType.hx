package insanity.custom;

import insanity.backend.types.Scripted;
import insanity.custom.InsanityType;

/**
 * unsafe version of InsanityType (internal use ONLY)
 */
class InsanityUnsafeType {
	public static inline function getClass(o:Dynamic):Dynamic {
		if (o is ICustomClassType) {
			var o:ICustomClassType = cast o;
			return o.typeGetClass();
		} else {
			return Type.getClass(o);
		}
	}
	
	public static inline function getEnum(o:Dynamic):Dynamic {
		if (o is ICustomEnumValueType) {
			var o:ICustomEnumValueType = cast o;
			return o.typeGetEnum();
		} else {
			return Type.getEnum(o);
		}
	}
	
	public static inline function getSuperClass(c:Dynamic):Dynamic {
		if (c is InsanityScriptedClass) {
			return cast(c:InsanityScriptedClass).extending;
		} else if (c is InsanityScriptedInterface) {
			return null;
		} else {
			return Type.getSuperClass(c);
		}
	}
	
	public static inline function getClassName(c:Dynamic):String {
		if (c is ICustomClassType)
			return cast(c:ICustomClassType).path;
		
		return Type.getClassName(c);
	}
	
	public static inline function getEnumName(e:Dynamic):String {
		if (e is InsanityScriptedEnum)
			return cast(e:InsanityScriptedEnum).path;
		
		return Type.getEnumName(e);
	}
	
	public static inline function resolveClass(name:String):Dynamic {
		return Type.resolveClass(name);
	}
	
	public static inline function resolveEnum(name:String):Dynamic {
		return Type.resolveEnum(name);
	}
	
	public static inline function createInstance(cl:Dynamic, args:Array<Dynamic>):Dynamic {
		if (cl is ICustomClassType) {
			var cl:ICustomClassType = cast cl;
			return cl.typeCreateInstance(args);
		} else {
			return Type.createInstance(cl, args);
		}
	}
	
	public static inline function createEmptyInstance(cl:Dynamic):Dynamic {
		if (cl is ICustomClassType) {
			var cl:ICustomClassType = cast cl;
			return cl.typeCreateEmptyInstance();
		} else {
			return Type.createEmptyInstance(cl);
		}
	}
	
	public static inline function createEnum(e:Dynamic, constr:String, ?params:Array<Dynamic>):Dynamic {
		if (e is ICustomEnumType) {
			var e:ICustomEnumType = cast e;
			return e.typeCreateEnum(constr, params);
		} else {
			return Type.createEnum(e, constr, params);
		}
	}
	
	public static inline function createEnumIndex(e:Dynamic, index:Int, ?params:Array<Dynamic>):Dynamic {
		if (e is ICustomEnumType) {
			var e:ICustomEnumType = cast e;
			return e.typeCreateEnumIndex(index, params);
		} else {
			return Type.createEnumIndex(e, index, params);
		}
	}
	
	public static inline function getInstanceFields(c:Dynamic):Array<String> {
		if (c is ICustomClassType) {
			var c:ICustomClassType = cast c;
			return c.typeGetInstanceFields();
		} else {
			return Type.getInstanceFields(c);
		}
	}
	
	public static inline function getClassFields(c:Dynamic):Array<String> {
		if (c is ICustomClassType) {
			var c:ICustomClassType = cast c;
			return c.typeGetClassFields();
		} else {
			return Type.getClassFields(c);
		}
	}
	
	public static inline function getEnumConstructs(e:Dynamic):Array<String> {
		if (e is ICustomEnumType) {
			var e:ICustomEnumType = cast e;
			return e.typeGetEnumConstructs();
		} else {
			return Type.getEnumConstructs(e);
		}
	}
	
	public static inline function typeof(v:Dynamic):Type.ValueType {
		return Type.typeof(v);
	}
	
	public static inline function enumEq(a:Dynamic, b:Dynamic):Bool {
		if (a is ICustomEnumValueType) {
			if (b is ICustomEnumValueType)
				return cast(a:ICustomEnumValueType).eq(b);
			return false;
		} else {
			return Type.enumEq(a, b);
		}
	}
	
	public static inline function enumConstructor(e:Dynamic):String {
		if (e is ICustomEnumValueType)
			return cast(e:ICustomEnumValueType).constructor;
		
		return Type.enumConstructor(e);
	}
	
	public static inline function enumParameters(e:Dynamic):Array<Dynamic> {
		if (e is ICustomEnumValueType)
			return (cast(e:ICustomEnumValueType).arguments ?? []);
		
		return Type.enumParameters(e);
	}
	
	public static inline function enumIndex(e:Dynamic):Int {
		if (e is ICustomEnumValueType)
			return cast(e:ICustomEnumValueType).index;
		
		return Type.enumIndex(e);
	}
	
	public static inline function allEnums(e:Dynamic):Array<Dynamic> {
		if (e is ICustomEnumType) {
			var e:ICustomEnumType = cast e;
			return e.typeAllEnums();
		} else {
			return Type.allEnums(e);
		}
	}
}

typedef ValueType = Type.ValueType; // booooring
