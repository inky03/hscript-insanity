package insanity;

import insanity.backend.types.Scripted;
import insanity.backend.TypeCollection;

class Environment {
	/**
	 * A map storing all modules defined for this environment, by path.
	 */
	public var modules:Map<String, Module> = [];
	/**
	 * A `TypeCollection` of all modules defined for this environment.
	 */
	public var types:TypeCollection;
	
	/**
	 * The environments's global variables.
	 * 
	 * All variables set here will also be set in all modules when initializing them.
	 */
	public var variables:Map<String, Dynamic> = [];
	/**
	 * Signal that is executed once all types in this environment are fully initialized.
	 * 
	 * If a function called in it returns false, it will be removed from the array.
	 */
	public var onInitialized:Array<Map<String, IInsanityType> -> Bool> = [];
	
	/**
	 * Creates a new `Environment`.
	 * 
	 * @param	modules		The modules to store in this environment.
	 */
	public function new(?modules:Array<Module>) {
		if (modules != null) {
			for (module in modules)
				this.modules.set(module.path, module);
		}
		
		rebuildTypes();
	}
	
	/**
	 * Adds a single `Module` to this environment.
	 * 
	 * @param	module		The module to store in this environment.
	 * @return	The module that was added to this environment.
	 */
	public function addModule(module:Module):Module {
		modules.set(module.path, module);
		rebuildTypes();
		return module;
	}
	
	/**
	 * Removes a single `Module` to this environment.
	 * 
	 * @param	module		The module to remove from this environment.
	 * @return	The module that was removed from this environment.
	 */
	public function removeModule(module:Module):Module {
		modules.remove(module.path);
		rebuildTypes();
		return module;
	}
	
	/**
	 * Locates a type in this environment from a string.
	 * 
	 * @param	path 		The path of the type to resolve.
	 * @return	The type if any was found, otherwise null.
	 */
	public function resolve(path:String):IInsanityType {
		for (module in modules) {
			if (module.types.exists(path))
				return module.types.get(path);
		}
		
		return null;
	}
	
	/**
	 * Initializes / starts up all modules on this environment.
	 * 
	 * Once finished, `onInitialized` will fire.
	 */
	public function start():Void {
		var allTypes:Map<String, IInsanityType> = [];
		
		for (module in modules)
			module.init(this);
		
		for (module in modules)
			module.start(this);
		
		for (module in modules) {
			module.startTypes(this);
			
			for (n => t in module.types)
				allTypes.set(n, t);
		}
		
		var i:Int = onInitialized.length;
		while (-- i >= 0) {
			if (!onInitialized[i](allTypes))
				onInitialized.remove(onInitialized[i]);
		}
	}
	/**
	 * Snapshots all modules in this environment.
	 */
	public function snapshot():Void {
		for (module in modules)
			module.snapshot();
	}
	
	/**
	 * Creates the `TypeCollection` of this environment's types. This will be stored in `types`.
	 * 
	 * @return	The new `TypeCollection` for this environment.
	 */
	public function rebuildTypes():TypeCollection {
		var map:TypeMap = { byPackage: [], byModule: [], byPath: [], byCompilePath: [], all: [] };
		
		function makeTypeInfo(module:Module) {
			var pack:String = module.pack.join('.');
			
			for (type in module.types) {
				var k:String = 'class';
				
				if (type is InsanityScriptedTypedef) {
					k = 'typedef';
				} else if (type is InsanityScriptedEnum) {
					k = 'enum';
				}
				
				var info:TypeInfo = {
					kind: k,
					module: module.path,
					pack: type.pack,
					name: type.name,
				};
				
				if (type is InsanityScriptedInterface) info.isInterface = true;
				
				var tp:Array<String> = info.pack.copy(); tp.push(info.name);
				
				map.all.push(info);
				
				map.byCompilePath[tp.join('.')] = [info];
				map.byPath[info.module + (info.module.length == 0 ? '' : '.') + info.name] = [info];
				
				map.byModule[info.module] ??= [];
				map.byModule[info.module].push(info);
				
				map.byPackage[pack] ??= [];
				map.byPackage[pack].push(info);
			}
		}
		
		for (module in modules)
			makeTypeInfo(module);
		
		return types = new TypeCollection(map);
	}
}