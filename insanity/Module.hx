package insanity;

import insanity.backend.types.Scripted;
import insanity.backend.Exception;
import insanity.backend.Parser;
import insanity.backend.Interp;
import insanity.backend.Expr;
import insanity.tools.Tools;

class Module {
	/**
	 * A map storing the state of all static variables using the `@:snapshot` metadata.
	 */
	public static var snapshots:Map<String, Map<String, Dynamic>> = [];
	
	/**
	 * The name of the module.
	 */
	public var name:String;
	/**
	 * Origin of the module (this is used for error reporting).
	 */
	public var origin:String;
	/**
	 * Array with the module's packages.
	 */
	public var pack:Array<String>;
	/**
	 * The module's fully qualified path, as a string.
	 */
	public var path(get, never):String;
	
	/**
	 * The module's parser.
	 */
	public var parser:Parser = new Parser();
	/**
	 * The module's interpreter.
	 */
	public var interp:Interp = null;
	
	/**
	 * The module's declarations (expressions).
	 */
	public var decls:Array<ModuleDecl> = [];
	/**
	 * A map storing all of this module's initialized types, by path.
	 */
	public var types:Map<String, IInsanityType> = [];
	/**
	 * The `Module_Fields_` implementation class for this module's [module level fields](https://haxe.org/blog/module-level-fields/) (if any).
	 */
	public var moduleFields:InsanityScriptedClass = null;
	/**
	 * Signal that is executed once the module's types are fully initialized.
	 * 
	 * If a function called in it returns false, it will be removed from the array.
	 */
	public var onInitialized:Array<Map<String, IInsanityType> -> Bool> = [];
	
	/**
	 * Array containing other modules.
	 * 
	 * This is used to expose this module's main type to all other modules, like Haxe does for all modules within the same directory and subdirectories.
	 * If it contains an `ImportModule`, all of it's import / using statements will be set on this module.
	 */
	public var subModules:Array<Module> = [];
	
	/**
	 * Whether the module is currently initializing or not.
	 */
	public var starting:Bool = false;
	/**
	 * Whether the module has successfully initialized or not.
	 */
	public var started:Bool = false;
	
	/**
	 * The module's global variables.
	 * 
	 * All variables set here will also be set in the module's types when initializing them.
	 */
	public var variables(get, never):Map<String, Dynamic>;
	inline function get_variables():Map<String, Dynamic> { return interp.variables; }
	
	/**
	 * Creates a `Module` and parses a module code string.
	 * 
	 * @param	string		The code string to parse.
	 * @param	name		The origin/name of the script (this is used for error reporting).
	 * @param	pack		The module's packages. This is also used to assert the package and an error will be thrown if the module doesn't match it.
	 * @param	origin		The origin of the module (this is used for error reporting).
	 */
	public function new(string:String, name:String = 'Module', pack:Array<String>, origin:String = 'hscript'):Void {
		parser.allowTypes = parser.allowJSON = true;
		interp = Type.createInstance(Config.interpClass, [null, this]);
		
		this.origin = origin;
		this.name = name;
		this.pack = pack;
		
		parse(string);
	}
	
	/**
	 * Parses module code from a string.
	 * 
	 * Calling this will also create the scripted type instances to be stored in `types`.
	 * If the code fails to parse, `onParsingError` will be called, otherwise, the generated declarations will be stored in `decls`.
	 * 
	 * @param	string		The code string to parse.
	 * @return	Array with the module's declarations.
	 */
	public function parse(string:String):Array<ModuleDecl> {
		decls.resize(0);
		types.clear();
		
		try {
			var declList:Array<ModuleDecl> = parser.parseModule(string, origin, pack);
			for (decl in declList) {
				decls.push(decl);
				
				var type:IInsanityType = loadType(decl);
				
				if (type != null) types.set(Tools.pathToString(type.name, pack), type);
			}
		} catch (e:haxe.Exception) {
			onParsingError(e);
		}
		
		return decls;
	}
	
	/**
	 * Creates a scripted type from a module declaration.
	 * 
	 * If the declaration is a `DField`, `moduleFields` will be initialized, and this function will not return anything.
	 * Any other non-type declarations will not execute or return anything.
	 * 
	 * @param	decl		The module type declaration.
	 * @return 	A scripted type instance (if any). This type is not initialized and should not be used yet!
	 */
	public function loadType(decl:ModuleDecl):IInsanityType {
		return switch (decl.d) {
			default:
				null;
			case DClass(m):
				new InsanityScriptedClass(m, this);
			case DEnum(m):
				new InsanityScriptedEnum(m, this);
			case DTypedef(m):
				new InsanityScriptedTypedef(m, this);
			case DInterface(m):
				new InsanityScriptedInterface(m, this);
			case DAbstract(m):
				new InsanityScriptedAbstract(m, this);
			case DField(m):
				var fieldsPath:String = Tools.pathToString('_$name.${name}_Fields_', pack);
				var t:InsanityScriptedClass = cast types.get(fieldsPath);
				
				var d:FieldDecl = {
					name: m.name,
					meta: m.meta,
					kind: m.kind,
					access: (m.isPrivate ? [AStatic, APrivate] : [AStatic, APublic])
				};
				
				if (t == null) { // creates Dummy class for the module level fields
					var fieldsModule:ClassDecl = {
						name: '${name}_Fields_',
						params: {},
						meta: [],
						fields: [d],
						isExtern: false,
						isPrivate: false,
						implement: null,
						extend: null,
					};
					
					var cl = new InsanityScriptedClass(fieldsModule, this);
					cl.pack = cl.pack.copy(); cl.pack.push('_$name');
					cl.path = Tools.pathToString(cl.name, cl.pack);
					
					moduleFields = cl;
					
					types.set(fieldsPath, cl);
				} else {
					@:privateAccess t.decl.fields.push(d);
				}
				
				null;
		}
	}
	
	/**
	 * Initializes the module's environment and default variables.
	 * 
	 * @param	environment		The `Environment` to use for this module.
	 */
	public function init(?environment:Environment):Void { // forgot why i separated init and start actually... merge?
		interp.environment = environment;
		setDefaults();
		
		if (environment != null) {
			for (k => v in environment.variables)
				if (!variables.exists(k)) variables.set(k, v);
		}
		
		for (type in types)
			interp.imports.set(type.name, type);
	}
	
	/**
	 * Initializes the module's imports and usings.
	 * 
	 * If this step fails, `onProgramError` will be called.
	 * 
	 * @param	environment		The `Environment` to use for this module.
	 */
	public function start(?environment:Environment):Void {
		try {
			if (decls.length == 0) throw 'Module is uninitialized';
			
			starting = true;
			
			for (module in subModules) {
				if (module is ImportModule) {
					module.start(environment);
					
					for (u in module.interp.usings) interp.usings.push(u);
					for (n => i in module.interp.imports) interp.imports.set(n, i);
				} else {
					var mainType:IInsanityType = module.types.get(module.path);
					
					if (mainType != null) module.interp.imports.set(mainType.name, mainType);
				}
			}
			
			interp.canInit = true;
			interp.executeModule(decls, path);
			
			starting = false;
			started = true;
		} catch (e:haxe.Exception) {
			onProgramError(e);
		}
	}
	
	/**
	 * Attempts to initialize a single type from this module.
	 * 
	 * If this step fails, `onTypeError` will be called.
	 * 
	 * @param	environment		The `Environment` to use for this module.
	 * @param 	type 			The scripted type instance to initialize.
	 * @return 	The scripted type instance that was initialized.
	 */
	public function startType(?environment:Environment, type:IInsanityType):IInsanityType {
		if (type.initializing || type.initialized || type.failed) return type;
		
		if (starting) return type;
		if (!started) start(environment);
		
		try {
			type.initializing = true;
			
			type.init(environment, interp);
			
			type.initializing = false;
			type.initialized = true;
		} catch (e:haxe.Exception) {
			type.failed = true;
			type.initialized = false;
			type.initializing = false;
			
			onTypeError(e, type);
		}
		
		return type;
	}
	
	/**
	 * Initializes / starts up all types in this module.
	 * 
	 * Once finished, `onInitialized` will fire.
	 * 
	 * @param	environment		The `Environment` to use for this module.
	 * @return 	A map with all initialized scripted types.
	 */
	public function startTypes(?environment:Environment):Map<String, IInsanityType> {
		if (moduleFields != null)
		{
			startType(environment, moduleFields);
			
			for (field in insanity.custom.InsanityReflect.fields(moduleFields))
				interp.imports.set(field, MProperty(moduleFields, field));
		}
		
		for (type in types) startType(environment, type);
		
		var i:Int = onInitialized.length;
		while (-- i >= 0) {
			if (!onInitialized[i](types))
				onInitialized.remove(onInitialized[i]);
		}
		
		return types;
	}
	
	/**
	 * Creates a snapshot of all of this module's types' fields that use the `@:snapshot` metadata.
	 */
	public function snapshot():Void {
		for (type in types)
			type.snapshot();
	}
	
	/**
	 * Initializes default variables within the script.
	 * This can be overridden to define new variables.
	 */
	public function setDefaults():Void {
		interp.setDefaults();
		
		variables.set('module', this);
	}
	
	/**
	 * This function is called when the module encounters an error when parsing.
	 * Can be overridden to execute custom behavior.
	 * 
	 * @param	exception	The exception that caused the parsing to halt.
	 */
	public dynamic function onParsingError(exception:haxe.Exception):Void {
		if (exception is ParserException) {
			trace('Failed to initialize module program!\nException: $exception');
		} else {
			trace('A fatal error occurred while initializing module program!\n' + exception.details());
		}
	}
	/**
	 * This function is called when the module program encounters an error when first running.
	 * Can be overridden to execute custom behavior.
	 * 
	 * @param	exception	The exception that caused the parsing to halt.
	 */
	public dynamic function onProgramError(exception:haxe.Exception):Void {
		trace('Module program stopped unexpectedly!\n' + exception.details());
	}
	/**
	 * This function is called when a type fails to initialize.
	 * Can be overridden to execute custom behavior.
	 * 
	 * @param	exception	The exception that caused the parsing to halt.
	 * @param 	type 		The type that encountered the error.
	 */
	public dynamic function onTypeError(exception:haxe.Exception, type:IInsanityType):Void {
		trace('Failed to load type ${type.name} for module $path!\nException: $exception' /*+ e.details()*/);
	}
	
	function get_path():String {
		var path:String = pack.join('.');
		
		if (path.length > 0) {
			return ('$path.$name');
		} else {
			return name;
		}
	}
}