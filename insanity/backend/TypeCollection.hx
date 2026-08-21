package insanity.backend;

#if (!macro)
import insanity.backend.macro.TypeCollectionMacro;
import insanity.Environment;
#end

typedef TypeInfo = {
	var kind:String;
	var name:String;
	var module:String;
	var pack:Array<String>;
	var ?hasConstructor:Bool;
	
	var ?typedefType:TypeInfo;
	var ?isInterface:Bool;
	
	var ?interfaceFields:Array<InterfaceField>;
	var ?interfaceMethods:Array<InterfaceMethod>;
	
	var ?structInitFields:Array<StructInitField>;
}

typedef StructInitField = {
	var name:String;
	var optional:Bool;
}

typedef InterfaceVar = {
	var name:String;
	
	var isPublic:Bool;
}

typedef InterfaceField = { > InterfaceVar,
	var get:Null<String>;
	var set:Null<String>;
	
	var isFinal:Bool;
}

typedef InterfaceMethod = { > InterfaceVar,
	var argumentCount:Int;
	
	var isDynamic:Bool;
}

typedef TypeMap = {
	var byCompilePath:Map<String, Array<TypeInfo>>;
	var byPackage:Map<String, Array<TypeInfo>>;
	var byModule:Map<String, Array<TypeInfo>>;
	var byPath:Map<String, Array<TypeInfo>>;
	var all:Array<TypeInfo>;
}

/**
 * This class indexes information about types.
 * 
 * Although it is primarily designed for internal use, it can be insightful for cases beyond it.
 * 
 * Best used with `using insanity.backend.TypeCollection`!
 */
class TypeCollection {
	#if (!macro)
	/**
	 * A `TypeCollection` that stores information for all classes generated at compile time.
	 */
	public static var main(default, never):TypeCollection = new TypeCollection(TypeCollectionMacro.build());
	/**
	 * This collection's index.
	 */
	public var types:TypeMap;
	
	/**
	 * Creates a `TypeCollection`.
	 * 
	 * @param	map		The collection's index.
	 */
	public function new(?map:TypeMap) {
		this.types = map;
	}
	
	/**
	 * Retrieves information of all types inside the specified package.
	 * 
	 * @param	path		The package path to check.
	 * @return	All types within the package, or null if it doesn't exist.
	 */
	public inline function fromPackage(path:String):Array<TypeInfo> {
		return types.byPackage.get(path);
	}
	/**
	 * Retrieves information of all types inside the specified module.
	 * 
	 * @param	path		The module path to check.
	 * @return	All types within the module, or null if it doesn't exist.
	 */
	public inline function fromModule(path:String):Array<TypeInfo> {
		return types.byModule.get(path);
	}
	/**
	 * Retrieves information of a type from it's compile path, i.e. the pathing used to resolve a class with `Type`.
	 * (ex. `package.Module.Type` -> `package.Type`)
	 * 
	 * For consistency in function, a single element array with the type will be returned.
	 * 
	 * @param	path		The type path to check.
	 * @return	The type, or null if it doesn't exist.
	 */
	public inline function fromCompilePath(path:String):Array<TypeInfo> {
		return types.byCompilePath.get(path);
	}
	/**
	 * Retrieves information of a type from it's fully qualified path, i.e. the pathing to use when importing classes in Haxe.
	 * (ex. `package.Module.Type`)
	 * 
	 * For consistency in function, a single element array with the type will be returned.
	 * 
	 * @param	path		The type path to check.
	 * @param	moduleCheck	If true, if the path provided is that of a module and there's a type with the module's same name, it will also be matched.
	 * @return	The type, or null if it doesn't exist.
	 */
	public inline function fromPath(path:String, moduleCheck:Bool = true):Array<TypeInfo> {
		var t = types.byPath.get(path);
		
		if (t == null && moduleCheck) {
			var name = path.substring(path.lastIndexOf('.'));
			return fromPath(path + name, false);
		}
		
		return t;
	}
	
	/**
	 * Gets the compile path (i.e. the pathing used to resolve a class with `Type`) from a type information.
	 * 
	 * @param	info		The type information to get the path from.
	 * @return	The type's path.
	 */
	public static function compilePath(info:TypeInfo):String {
		var typePath:Array<String> = info.pack.copy();
		typePath.push(info.name);
		return typePath.join('.');
	}
	/**
	 * Gets the fully qualified path (i.e. the pathing to use when importing classes in Haxe) from a type information.
	 * 
	 * @param	info		The type information to get the path from.
	 * @return	The type's path.
	 */
	public static function fullPath(info:TypeInfo):String {
		return (info.module + (info.module.length > 0 ? '.' : '') + info.name);
	}
	/**
	 * Resolves a type from a type information.
	 * 
	 * @param	info		The type information to resolve.
	 * @param	env			The `Environment` this type belongs to, if applicable. (this can be omitted for compile time classes)
	 * @return	The type found.
	 */
	public static function resolve(info:TypeInfo, ?env:Environment):Dynamic {
		if (info.typedefType != null)
			return Tools.resolve(compilePath(info.typedefType), env);
		return Tools.resolve(compilePath(info), env);
	}
	#end
}