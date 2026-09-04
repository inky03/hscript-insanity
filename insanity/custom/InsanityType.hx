package insanity.custom;

import insanity.backend.types.Scripted;
import insanity.Config;

/**
 * HscriptInsanity's extended version of the `Type` class, to make working with scripted types easier.
 */
class InsanityType {
	public static var environment:Environment = null;
	
	public static inline function getClass(o:Dynamic):Dynamic {
		if (o is ICustomClassType) {
			var o:ICustomClassType = cast o;
			return o.typeGetClass();
		} #if (insanity.scriptableTypes) else if (o?.__isScripted) {
			return o.typeGetClass();
		} #end else {
			var t:Class<Dynamic> = Type.getClass(o);
			return (t == null ? null : ConfigUtil.assertBlacklisted(Config.typeProxy.get(Type.getClassName(t)) ?? t));
		}
	}
	
	public static inline function getEnum(o:Dynamic):Dynamic {
		#if (insanity.scriptableTypes) if (o is ICustomEnumValueType) {
			var o:ICustomEnumValueType = cast o;
			return o.typeGetEnum();
		} else #end {
			var t:Enum<Dynamic> = Type.getEnum(o);
			return (t == null ? null : ConfigUtil.assertBlacklisted(Config.typeProxy.get(Type.getEnumName(t)) ?? t));
		}
	}
	
	public static inline function getSuperClass(c:Dynamic):Dynamic {
		#if (insanity.scriptableTypes)
		if (c is InsanityScriptedClass) {
			return cast(c:InsanityScriptedClass).extending;
		} else if (c is InsanityScriptedInterface) {
			return null;
		} else #end {
			var c:Class<Dynamic> = Type.getSuperClass(c);
			return (c == null ? null : ConfigUtil.assertBlacklisted(Config.typeProxy.get(Type.getClassName(c)) ?? c));
		}
	}
	
	public static inline function getClassName(c:Dynamic):String {
		if (c is ICustomClassType) {
			return cast(c:ICustomClassType).path;
		} else {
			return Type.getClassName(c);
		}
	}
	
	public static inline function getEnumName(e:Dynamic):String {
		#if (insanity.scriptableTypes) if (e is InsanityScriptedEnum) {
			return cast(e:InsanityScriptedEnum).path;
		} else #end {
			return Type.getEnumName(e);
		}
	}
	
	public static inline function resolveClass(name:String):Dynamic {
		#if (insanity.noScriptableTypes)
		
		var t:Class<Dynamic> = Type.resolveClass(name);
		return (t == null ? null : ConfigUtil.assertBlacklisted(Config.typeProxy.get(name) ?? t));
		
		#else
		
		var t:Dynamic = environment?.resolve(name);
		if (t != null && (t is InsanityScriptedClass || t is InsanityScriptedInterface)) {
			return t;
		} else {
			t = Type.resolveClass(name);
			return (t == null ? null : ConfigUtil.assertBlacklisted(Config.typeProxy.get(name) ?? t));
		}
		
		#end
	}
	
	public static inline function resolveEnum(name:String):Dynamic {
		#if (insanity.noScriptableTypes)
		
		var t:Enum<Dynamic> = Type.resolveEnum(name);
		return (t == null ? null : ConfigUtil.assertBlacklisted(Config.typeProxy.get(name) ?? t));
		
		#else
		
		var t:Dynamic = environment?.resolve(name);
		if (t != null && t is InsanityScriptedEnum) {
			return t;
		} else {
			t = Type.resolveEnum(name);
			return (t == null ? null : ConfigUtil.assertBlacklisted(Config.typeProxy.get(name) ?? t));
		}
		
		#end
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
		#if (insanity.scriptableTypes) if (e is ICustomEnumType) {
			var e:ICustomEnumType = cast e;
			return e.typeCreateEnum(constr, params);
		} else #end {
			return Type.createEnum(e, constr, params);
		}
	}
	
	public static inline function createEnumIndex(e:Dynamic, index:Int, ?params:Array<Dynamic>):Dynamic {
		#if (insanity.scriptableTypes) if (e is ICustomEnumType) {
			var e:ICustomEnumType = cast e;
			return e.typeCreateEnumIndex(index, params);
		} else #end {
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
		#if (insanity.scriptableTypes) if (e is ICustomEnumType) {
			var e:ICustomEnumType = cast e;
			return e.typeGetEnumConstructs();
		} else #end {
			return Type.getEnumConstructs(e);
		}
	}
	
	public static inline function typeof(v:Dynamic):Type.ValueType {
		return Type.typeof(v);
	}
	
	public static inline function enumEq(a:Dynamic, b:Dynamic):Bool {
		#if (insanity.scriptableTypes)  if (a is ICustomEnumValueType) {
			if (b is ICustomEnumValueType)
				return cast(a:ICustomEnumValueType).eq(b);
			return false;
		} else #end {
			return Type.enumEq(a, b);
		}
	}
	
	public static inline function enumConstructor(e:Dynamic):String {
		#if (insanity.scriptableTypes) if (e is ICustomEnumValueType) {
			return cast(e:ICustomEnumValueType).constructor;
		} else #end {
			return Type.enumConstructor(e);
		}
	}
	
	public static inline function enumParameters(e:Dynamic):Array<Dynamic> {
		#if (insanity.scriptableTypes) if (e is ICustomEnumValueType) {
			return (cast(e:ICustomEnumValueType).arguments ?? []);
		} else #end {
			return Type.enumParameters(e);
		}
	}
	
	public static inline function enumIndex(e:Dynamic):Int {
		#if (insanity.scriptableTypes) if (e is ICustomEnumValueType) {
			return cast(e:ICustomEnumValueType).index;
		} else #end {
			return Type.enumIndex(e);
		}
	}
	
	public static inline function allEnums(e:Dynamic):Array<Dynamic> {
		#if (insanity.scriptableTypes) if (e is ICustomEnumType) {
			var e:ICustomEnumType = cast e;
			return e.typeAllEnums();
		} else #end {
			return Type.allEnums(e);
		}
	}
}

/**
 * Implements custom behavior for class adjacent functions in `InsanityType`.
 */
interface ICustomClassType extends ICustomType {
	/**
	 * Behavior override for `Type.createEmptyInstance`.
	 * Creates an empty (uninitialized) instance.
	 * 
	 * @return	The new instance.
	 */
	public function typeCreateEmptyInstance():Dynamic;
	/**
	 * Behavior override for `Type.createInstance`.
	 * Creates an instance.
	 * 
	 * @param	args	List of arguments to pass to the class' constructor.
	 * @return	The new instance.
	 */
	public function typeCreateInstance(args:Array<Dynamic>):Dynamic;
	/**
	 * Behavior override for `Type.getInstanceFields`.
	 * Gets the names of all of this class' instance fields.
	 * 
	 * @return	Array.
	 */
	public function typeGetInstanceFields():Array<String>;
	/**
	 * Behavior override for `Type.getClassFields`.
	 * Gets the names of all of this class' static fields.
	 * 
	 * @return	Array.
	 */
	public function typeGetClassFields():Array<String>;
	/**
	 * Behavior override for `Type.getClass`.
	 * Gets the class this instance belongs to.
	 * 
	 * @return	Class.
	 */
	public function typeGetClass():Dynamic;
}

#if (insanity.scriptableTypes)
/**
 * Implements custom behavior for enum adjacent functions in `InsanityType`.
 */
interface ICustomEnumType extends ICustomType {
	/**
	 * Behavior override for `Type.createEnumIndex`.
	 * Creates an enum value from the constructor's numerical index.
	 * 
	 * @param	index	The index of the enum constructor.
	 * @param	params	The parameters to pass to the enum's constructor.
	 * @return	The enum value.
	 */
	public function typeCreateEnumIndex(index:Int, ?params:Array<Dynamic>):Dynamic;
	/**
	 * Behavior override for `Type.createEnum`.
	 * Creates an enum value from the constructor's name.
	 * 
	 * @param	index	The name of the enum constructor.
	 * @param	params	The parameters to pass to the enum's constructor.
	 * @return	The enum value.
	 */
	public function typeCreateEnum(constr:String, ?params:Array<Dynamic>):Dynamic;
	/**
	 * Behavior override for `Type.getEnumConstructs`.
	 * Gets the names of all of this enum's constructors.
	 * 
	 * @return	Array.
	 */
	public function typeGetEnumConstructs():Array<String>;
	/**
	 * Behavior override for `Type.getEnumName`.
	 * Gets the path of this enum.
	 * 
	 * @return	The path of the enum.
	 */
	public function typeGetEnumName():String;
	/**
	 * Behavior override for `Type.allEnums`.
	 * Returns a list of all constructors of this enum that require no arguments.
	 * 
	 * @return	Array.
	 */
	public function typeAllEnums():Array<Dynamic>;
}

/**
 * Implements custom behavior for enum value adjacent functions in `InsanityType`.
 */
interface ICustomEnumValueType extends ICustomType {
	public var index:Int;
	public var constructor:String;
	public var arguments:Array<Dynamic>;
	
	/**
	 * Behavior override for `Type.getEnum`.
	 * Gets the enum this enum value belongs to.
	 * 
	 * @return	Enum.
	 */
	public function typeGetEnum():Dynamic;
	/**
	 * Behavior override for `Type.enumEq`.
	 * Evaluates equivalence between this enum value and another.
	 * 
	 * @param	e	The enum value to match.
	 * @return	Whether the two enum values are equivalent or not.
	 */
	public function eq(e:ICustomEnumValueType):Bool;
}
#end

interface ICustomType {}
