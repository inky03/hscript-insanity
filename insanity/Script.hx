package insanity;

import insanity.backend.Exception;
import insanity.backend.Parser;
import insanity.backend.Interp;
import insanity.backend.Expr;

@:access(insanity.backend.Interp)
class Script {
	/**
	 * Origin / name of the script (this is used for error reporting).
	 */
	public var name:String;
	
	/**
	 * The script's parser.
	 */
	public var parser:Parser = new Parser();
	/**
	 * The script's interpreter.
	 */
	public var interp:Interp = null;
	/**
	 * The script's program (expression).
	 */
	public var program:Expr = null;
	
	/**
	 * Whether the script failed when trying to start.
	 */
	public var failed:Bool = false;
	
	/**
	 * The script's global variables.
	 */
	public var variables(get, never):Map<String, Dynamic>;
	inline function get_variables():Map<String, Dynamic> { return interp.variables; }
	
	/**
	 * Creates a `Script` and parses a code string.
	 * 
	 * @param	string		The code string to parse.
	 * @param	name		The origin/name of the script (this is used for error reporting).
	 * @param	environment	The `Environment` to run this script in.
	 */
	public function new(string:String, name:String = 'hscript', ?environment:Environment):Void {
		parser.allowTypes = parser.allowJSON = parser.allowMetadata = true;
		interp = Type.createInstance(Config.interpClass, [environment, this]);
		interp.defineGlobals = true;
		
		this.name = name;
		
		parse(string);
	}
	
	/**
	 * Parses code from a string.
	 * If the code fails to parse, `onParsingError` will be called, otherwise, the expression will be stored in `program`.
	 * 
	 * @param	string		The code string to parse.
	 * @return	The script expression, or null if the code failed to parse.
	 */
	public function parse(string:String):Expr {
		try {
			program = parser.parseScript(string, name);
		} catch (e:haxe.Exception) {
			onParsingError(e);
			program = null;
		}
		
		return program;
	}
	
	/**
	 * Starts the script program.
	 * If the program fails to start, `onProgramError` will be called.
	 * 
	 * @return	The return value of the program, if any.
	 */
	public function start():Any {
		try {
			if (program == null) throw 'Program is uninitialized';
			
			failed = false;
			setDefaults();
			
			if (interp.environment != null) {
				for (k => v in interp.environment.variables)
					if (!variables.exists(k)) variables.set(k, v);
			}
			
			return interp.execute(program);
		} catch (e:haxe.Exception) {
			onProgramError(e);
			failed = true;
		}
		
		return null;
	}
	
	/**
	 * Calls a function on the script.
	 * 
	 * @param	variable	The name of the function.
	 * @param	args		Arguments to pass when calling the function.
	 * @return	The return value of the function, if any.
	 */
	public function call(variable:String, ?args:Array<Dynamic>):Any {
		if (interp == null) throw 'Interpreter is uninitialized';
		
		var fun = (variables.get(variable) ?? interp.getLocal(variable));
		
		if (!Reflect.isFunction(fun)) {
			trace('$variable isn\'t a function');
			return null;
		}
		
		return Reflect.callMethod(interp, fun, args ?? []);
	}
	
	/**
	 * Initializes default variables within the script.
	 * This can be overridden to define new variables.
	 */
	public function setDefaults():Void {
		interp.setDefaults();
		
		variables.set('this', this);
		variables.set('script', this);
		variables.set('interp', interp);
	}
	
	/**
	 * This function is called when the script encounters an error when parsing.
	 * Can be overridden to execute custom behavior.
	 * 
	 * @param	exception	The exception that caused the parsing to halt.
	 */
	public dynamic function onParsingError(exception:haxe.Exception):Void {
		trace('Failed to initialize script program!\n' + exception.details());
	}
	/**
	 * This function is called when the script program encounters an error when first running.
	 * Can be overridden to execute custom behavior.
	 * 
	 * @param	exception	The exception that caused the parsing to halt.
	 */
	public dynamic function onProgramError(exception:haxe.Exception):Void {
		trace('Script program stopped unexpectedly!\n' + exception.details());
	}
}