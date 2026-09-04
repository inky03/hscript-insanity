package insanity.backend.types;

import insanity.custom.InsanityReflect;
import insanity.custom.InsanityType;

import insanity.backend.macro.AbstractMacro;
import insanity.backend.types.Abstract;
import insanity.backend.Interp;
import insanity.backend.Expr;
import insanity.Environment;
import insanity.Module;

using Lambda;
using StringTools;
using insanity.tools.Tools;
using insanity.backend.TypeCollection;

class ScriptedTools {
	public static var scriptedClasses(default, never):Map<String, Class<Dynamic>> = insanity.backend.macro.ScriptedMacro.listScriptableClasses();
	
	public static function resolve(t:Dynamic):Dynamic {
		if (t is InsanityScriptedClass)
			return cast t;
		
		var cls:String = Type.getClassName(t);
		if (scriptedClasses.exists(cls))
			return scriptedClasses.get(cls);
		
		throw 'Class $cls can\'t be extended for scripting';
		return null;
	}
}

@:access(insanity.backend.Interp)
@:access(insanity.backend.types.IInsanityScripted)
class InsanityScriptedClass implements IInsanityType implements IInsanityInterp implements ICustomReflection implements ICustomClassType {
	public var path:String;
	public var name:String;
	public var module:Module;
	public var pack:Array<String>;
	
	public var safe:Bool = false;
	public var snapshotAll:Bool = false;
	
	public var interp:Interp;
	
	public var extending(get, never):Dynamic;
	public var instanceClass(get, never):Dynamic;
	
	public var implementing:Array<Dynamic> = [];
	public var structInitFields:Null<Array<StructInitField>> = null;
	
	var decl:ClassDecl;
	var __vars:Map<String, Variable> = [];
	
	public var failed:Bool = false;
	public var initialized:Bool = false;
	public var initializing:Bool = false;
	
	public function new(decl:ClassDecl, ?module:Module) {
		this.name = decl.name;
		this.pack = (module?.pack ?? []);
		this.module = module;
		this.decl = decl;
		
		path = Tools.pathToString(name, pack);
		
		interp = Type.createInstance(Config.interpClass, []);
		interp.canDefer = true;
		interp.origin = path;
		
		if (decl.meta.exists((meta:MetadataEntry) -> meta.name == ':structInit')) initStructInit();
	}
	
	public function initStructInit():Void {
		var constructor:FieldDecl = decl.fields.find((field:FieldDecl) -> field.name == 'new');
		
		if (constructor == null) { // gay macro
			final args:Array<Argument> = [];
			final pos:Position = {origin: interp.position.origin, line: interp.position.line};
			
			for (field in decl.fields) {
				switch (field.kind) {
					default:
					case KVar(v):
						if (v.set != null && v.set != 'default' && v.set != 'null') continue;
						
						args.push({name: field.name, opt: v.expr != null, t: v.type});
				}
			}
			
			final newExpr:Expr = EBlock([for (arg in args) {
				EIf(
					EBinop('!=', EIdent(arg.name).mk(pos), EIdent('null').mk(pos)).mk(pos),
					EBinop('=', EField(EIdent('this').mk(pos), arg.name).mk(pos), EIdent(arg.name).mk(pos)).mk(pos)
				).mk(pos);
			}]).mk(pos);
			
			decl.fields.push(constructor = {
				meta: [],
				name: 'new',
				access: [APublic],
				kind: KFunction({
					args: args,
					expr: newExpr,
					ret: null
				})
			});
		}
		
		switch (constructor.kind) {
			default:
			case KFunction(fun):
				structInitFields = [for (arg in fun.args) {name: arg.name, optional: arg.opt || arg.value != null}];
		}
	}
	
	public function init(?env:Environment, ?baseInterp:Interp, restore:Bool = true):Void {
		interp.environment = env;
		interp.setDefaults(true, baseInterp == null);
		
		if (baseInterp != null) {
			for (u in baseInterp.usings) interp.usings.push(u);
			for (k => i in baseInterp.imports) interp.imports.set(k, i);
			for (k => v in baseInterp.variables) if (!interp.variables.exists(k)) interp.variables.set(k, v);
		}
		
		interp.imports.set(name, this);
		
		interp.pushStack(insanity.backend.CallStack.StackItem.SModule(module?.path ?? name));
		
		safe = false;
		snapshotAll = false;
		for (meta in decl.meta) {
			safe = (safe || meta.name == ':safe');
			snapshotAll = (snapshotAll || meta.name == ':snapshot');
		}
		
		var overridingFields:Array<String> = [];
		var knownFields:Array<String> = [];
		
		for (field in decl.fields) {
			var f:String = field.name;
			
			if (f == 'new') continue;
			
			if (insanity.backend.macro.ScriptedMacro.ignoreFields.exists(f)) {
				throw 'Field $f reserved for internal use!!! - HScriptInsanity';
			} else if (knownFields.contains(f)) {
				throw 'Duplicate class field declaration: $name.$f';
			} else {
				if (field.access.contains(AOverride)) {
					switch (field.kind) {
						default: overridingFields.push(f);
						case KVar(_): throw 'Invalid accessor \'override\' for variable $f';
					}
				}
				
				knownFields.push(f);
			}
			
			if (!field.access.contains(AStatic)) continue;
			
			var l:Variable = {r: null, access: field.access};
			
			switch (field.kind) {
				default:
				case KVar(v):
					if (v.get != null) l.get = v.get;
					if (v.set != null) l.set = v.set;
					if (v.isFinal != null) l.isFinal = v.isFinal;
			}
			
			interp.locals.set(f, l);
		}
		
		implement(decl.implement);
		
		for (field in decl.fields) {
			var f:String = field.name;
			
			if (f == 'new' || !field.access.contains(AStatic)) continue;
			
			switch (field.kind) {
				case KFunction(fun):
					interp.locals.get(f).r = interp.buildFunction(f, fun.args, fun.expr, fun.ret, interp.locals);
					
				case KVar(v):
					if (restore) {
						var snapshot:Bool = snapshotAll;
						if (!snapshot) for (meta in field.meta) snapshot = (snapshot || meta.name == ':snapshot');
						
						if (snapshot && Module.snapshots.exists(path)) {
							var fields:Map<String, Dynamic> = Module.snapshots.get(path);
							if (fields.exists(f)) {
								interp.locals.get(f).r = fields.get(f);
								continue;
							}
						}
					}
					
					try {
						interp.locals.get(f).r = (v.expr == null ? null : interp.exprReturn(v.expr, v.type));
					} catch (d:Defer) {
						var signal = (env?.onInitialized ?? module.onInitialized);
						
						signal.push(function(_) {
							try {
								interp.locals.get(f).r = interp.exprReturn(v.expr, v.type);
							} catch (e:haxe.Exception) {
								onExpressionError(e, f, v.expr);
							}
							
							return false;
						});
					} catch (e:haxe.Exception) {
						onExpressionError(e, f, v.expr);
					}
			}
			
			__vars.set(f, interp.locals.get(f));
		}
		
		var foundOverridingFields:Array<String> = [];
		function overrideFieldCheck(extending:Dynamic) {
			if (extending is InsanityScriptedClass) {
				var extend:InsanityScriptedClass = cast extending;
				
				if (extend.module != null && !extend.initializing && !extend.initialized && !extend.failed) {
					if (!extend.module.starting && !extend.module.started) extend.module.start(env);
					
					extend.module.startType(env, extend);
				}
				
				for (field in extend.decl.fields) {
					var f:String = field.name;
					
					if (f == 'new' || field.access.contains(AStatic)) continue;
					
					if (overridingFields.contains(f)) {
						if (!foundOverridingFields.contains(f))
							foundOverridingFields.push(f);
					} else if (knownFields.contains(f)) {
						throw 'Field $f should be declared with \'override\' since it is inherited from superclass ${extend.name}';
					}
				}
				
				if (extend.extending != null) overrideFieldCheck(extend.extending);
			} else {
				var cls = instanceClass;
				if (cls == null) return;
				
				var instanceFields:Array<String> = (cls.instanceFields != null ? {
					var map:Map<String, Bool> = cast cls.instanceFields;
					[for (f in map.keys()) f];
				} : Type.getInstanceFields(cast cls));
				var inlinedFields:Map<String, Bool> = cls.inlinedFields;
				
				for (field in instanceFields) {
					if (insanity.backend.macro.ScriptedMacro.ignoreFields.exists(field)) continue;
					
					if (overridingFields.contains(field)) {
						if (inlinedFields?.exists(field)) { throw 'Field $field is inlined and cannot be overridden'; }
						
						if (!foundOverridingFields.contains(field))
							foundOverridingFields.push(field);
					} else if (knownFields.contains(field)) {
						throw 'Field $field should be declared with \'override\' since it is inherited from superclass ${cls.getBaseClass()}';
					}
				}
			}
		}
		overrideFieldCheck(extending);
		if (foundOverridingFields.length < overridingFields.length) {
			for (f in overridingFields) {
				if (!foundOverridingFields.contains(f))
					throw 'Field $f is declared \'override\' but doesn\'t override any field'; // TODO (Suggestion: ) ?
			}
		}
	}
	
	function matchFieldAccess(?access:String, ?with:String):Bool {
		if ((with == 'get' || with == 'set' || with == 'dynamic') && !(access == 'get' || access == 'set' || access == 'dynamic')) return false;
		
		if ((with == 'default' || with == null) && !(access == 'default' || access == null)) return false;
		
		if ((with == 'null' || with == 'never') && with != access) return false;
		
		return true;
	}
	function assertInterface(i:Dynamic):Void {
		if (i is InsanityScriptedInterface) {
			var i:InsanityScriptedInterface = cast i;
			
			for (field in i.interfaceVariables) {
				final name:String = field.name;
				var myField:Null<FieldDecl> = Lambda.find(decl.fields, (f) -> (f.name == name));
				if (myField == null) throw 'Field $name needed by ${i.path} is missing';
				
				if (field.access.contains(APublic) && !myField.access.contains(APublic)) throw 'Field $name should be public as requested by ${i.path}';
				
				var mismatch:Bool = false;
				switch (field.kind) {
					case KVar(v):
						switch (myField.kind) {
							case KVar(myV):
								mismatch = (
									!matchFieldAccess(myV.get, v.get) || !matchFieldAccess(myV.set, v.set) ||
									(v.isFinal == true && myV.isFinal != true) ||
									(v.isFinal == false && myV.isFinal == true)
								);
							
							case KFunction(_):
								mismatch = true;
						}
						
					case KFunction(f):
						switch (myField.kind) {
							case KVar(_):
								mismatch = true;
							
							case KFunction(myF):
								if (myF.args.length != f.args.length) throw 'Field $name has different type than in ${i.path}: Different number of function arguments';
								
								if (field.access.contains(ADynamic) && !myField.access.contains(ADynamic)) mismatch = true;
						}
				}
				
				if (mismatch) throw 'Field $name has different property access than in ${i.path}: ${Tools.fieldDeclToErrorString(myField)} should be ${Tools.fieldDeclToErrorString(field)}';
			}
			
			return;
		}
		
		var type:Null<TypeInfo> = null, typeName:Null<String> = null;
		
		try {
			typeName = InsanityType.getClassName(i);
			
			type = (TypeCollection.main.fromCompilePath(typeName) ?? interp.environment?.types.fromCompilePath(typeName))[0];
			
			if (!type.isInterface) throw 0;
		} catch(e) {
			throw 'You can only implement an interface';
		}
		
		for (field in type.interfaceFields) {
			final name:String = field.name;
			var myField:Null<FieldDecl> = Lambda.find(decl.fields, (f) -> (f.name == name));
			if (myField == null) throw 'Field $name needed by $typeName is missing';
			
			if (field.isPublic && !myField.access.contains(APublic)) throw 'Field $name should be public as requested by $typeName';
			
			var mismatch:Bool = false;
			switch (myField.kind) {
				case KVar(myV):
					mismatch = (
						!matchFieldAccess(myV.get, field.get) || !matchFieldAccess(myV.set, field.set) ||
						(field.isFinal == true && myV.isFinal != true) ||
						(field.isFinal == false && myV.isFinal == true)
					);
					
				case KFunction(_):
					mismatch = true;
			}
			
			if (mismatch) throw 'Field $name has different property access than in $typeName: ${Tools.fieldDeclToErrorString(myField)} should be ${
				field.isFinal ? 'final' : insanity.tools.Printer.varAccessToString(field.get, field.set)
			}';
		}
		
		for (field in type.interfaceMethods) {
			final name:String = field.name;
			var myField:Null<FieldDecl> = Lambda.find(decl.fields, (f) -> (f.name == name));
			if (myField == null) throw 'Field $name needed by $typeName is missing';
			
			if (field.isPublic && !myField.access.contains(APublic)) throw 'Field $name should be public as requested by $typeName';
			
			var mismatch:Bool = false;
			switch (myField.kind) {
				case KVar(_):
					mismatch = true;
					
				case KFunction(myF):
					if (myF.args.length != field.argumentCount) throw 'Field $name has different type than in $typeName: Different number of function arguments';
					
					if (field.isDynamic && !myField.access.contains(ADynamic)) mismatch = true;
			}
			
			if (mismatch) throw 'Field $name has different property access than in $typeName: ${Tools.fieldDeclToErrorString(myField)} should be ${
				field.isDynamic ? 'dynamic method' : 'method'
			}';
		}
	}
	public function implement(?types:Array<CType>):Void {
		if (types == null || types.length == 0) return;
		
		for (type in types) {
			switch (type) {
				case CTPath(path, _):
					var p:String = path.join('.');
					
					var type:Dynamic = module?.interp.imports.get(p);
					type ??= interp.imports.get(p);
					type ??= Tools.resolve(p, interp.environment);
					
					if (type == null) throw 'Type not found: $p';
					
					function pushImplement(i:Dynamic) {
						if (i is InsanityScriptedInterface) {
							var i:InsanityScriptedInterface = cast i;
							
							if (i.module != null && !i.initializing && !i.initialized && !i.failed) {
								if (!i.module.starting && !i.module.started) i.module.start(interp.environment);
								
								i.module.startType(interp.environment, i);
							}
							
							if (!implementing.contains(i)) implementing.push(i);
							
							for (i in i.extending) pushImplement(i);
						} else {
							if (!implementing.contains(i)) implementing.push(i);
						}
					}
					
					pushImplement(type);
					
				default:
					throw 'Invalid implement $type';
			}
		}
		
		for (i in implementing) {
			assertInterface(i);
		}
	}
	
	public function snapshot():Void {
		for (field in decl.fields) {
			if (field.name == 'new' || !field.access.contains(AStatic)) continue;
			
			var snapshot:Bool = snapshotAll;
			if (!snapshot) for (meta in field.meta) snapshot = (snapshot || meta.name == ':snapshot');
			if (!snapshot) continue;
			
			switch (field.kind) {
				case KFunction(_):
				case KVar(_):
					var fields:Map<String, Dynamic> = (Module.snapshots.get(path) ?? []);
					fields.set(field.name, interp.getLocal(field.name));
					Module.snapshots.set(path, fields);
			}
		}
	}
	
	function get_extending():Dynamic {
		return switch (decl.extend) {
			case CTPath(path, _):
				var p:String = path.join('.');
				
				var type:Dynamic = module?.interp.imports.get(p);
				type ??= interp.imports.get(p);
				type ??= Tools.resolve(p, interp.environment);
				
				if (type == null) throw 'Type not found: $p';
				
				ScriptedTools.resolve(type);
			case null:
				null;
			default:
				throw 'Invalid extend ${decl.extend}';
				null;
		}
	}
	function get_instanceClass():Dynamic {
		if (extending is InsanityScriptedClass) {
			return cast(extending, InsanityScriptedClass).instanceClass;
		} else if (extending == null) {
			return InsanityDummyClass;
		} else {
			return extending;
		}
	}
	
	public function toString():String {
		if (interp.locals?.exists('toString'))
			return interp.locals.get('toString').r();
		
		return 'InsanityScriptedClass<$path>';
	}
	
	public function typeCreateInstance(arguments:Array<Dynamic>):Dynamic {
		if (!initialized) throw 'Type $path is not initialized';
		
		var inst:Dynamic = Type.createEmptyInstance(instanceClass);
		inst.insanityNew(this, arguments);
		
		return inst;
	}
	public function typeCreateEmptyInstance():Dynamic {
		if (!initialized) throw 'Type $path is not initialized';
		
		return Type.createEmptyInstance(instanceClass);
	}
	public function typeGetClass():Dynamic {
		return null;
	}
	public function typeGetClassFields():Array<String> {
		var fields:Array<String> = [for (loc => _ in interp.locals) loc];
		return fields;
	}
	public function typeGetInstanceFields():Array<String> {
		var fields:Array<String> = [];
		
		function getFields(c:Dynamic) {
			if (c is InsanityScriptedClass) {
				for (field in cast(c, InsanityScriptedClass).decl.fields) {
					var f:String = field.name;
					if (f == 'new' || field.access.contains(AStatic)) continue;
					if (!fields.contains(f)) fields.push(f);
				}
				
				var instance = c.instanceClass;
				if (instance != InsanityScriptedClass)
					getFields(instance);
				
				if (c.extending != null) {
					getFields(c.extending);
				}
			} else if (c is Class) {
				for (f in Type.getInstanceFields(c)) {
					if (!fields.contains(f) && !insanity.backend.macro.ScriptedMacro.ignoreFields.exists(f))
						fields.push(f);
				}
			}
		}
		
		getFields(this);
		
		return fields;
	}
	
	public function reflectHasField(field:String):Bool {
		return (__vars.exists(field));
	}
	public function reflectGetField(field:String):Dynamic {
		return (__vars.exists(field) ? __vars.get(field).r : null);
	}
	public function reflectSetField(field:String, value:Dynamic):Dynamic {
		return (__vars.exists(field) ? __vars.get(field).r = value : null);
	}
	public function reflectGetProperty(property:String):Dynamic {
		return (__vars.exists(property) ? interp.getLocal(property, __vars) : null);
	}
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic {
		return (__vars.exists(property) ? interp.setLocal(property, value, __vars) : null);
	}
	public function reflectListFields():Array<String> {
		return [for (field in __vars.keys()) field];
	}
	
	public dynamic function onExpressionError(error:Dynamic, field:String, ?expr:Expr):Void {
		trace('Error on field $field of $path: $error');
	}
	public dynamic function onInstanceError(error:Dynamic, fun:String, ?instance:Dynamic):Void {
		trace('Error on function $fun of $path: $error');
	}
}

@:access(insanity.backend.Interp)
class InsanityScriptedTypedef implements IInsanityType {
	public var name:String;
	public var module:Module;
	public var pack:Array<String>;
	public var path:String;
	
	public var alias:Dynamic;
	
	var decl:TypeDecl;
	
	public var failed:Bool = false;
	public var initialized:Bool = false;
	public var initializing:Bool = false;
	
	public function new(decl:TypeDecl, ?module:Module) {
		this.name = decl.name;
		this.pack = (module?.pack ?? []);
		this.module = module;
		this.decl = decl;
		
		path = Tools.pathToString(name, pack);
	}
	
	public function init(?env:Environment, ?baseInterp:Interp, restore:Bool = true):Void {
		alias = null;
		
		switch (decl.t) {
			case insanity.backend.Expr.CType.CTPath(path, params):
				var fullPath:String = path.join('.');
				
				if (fullPath == 'Map') { // infer from parameters
					if (params == null || params.length < 2) throw 'Not enough type parameters for Map'; // we dont really care about the value type , but whatever
					else if (params.length > 2) throw 'Too many type parameters for Map';
					
					switch (params[0]) {
						case CTAnon(_):
							alias = haxe.ds.ObjectMap;
						case CTPath(path, _):
							var fullPath:String = path.join('.');
							
							if (fullPath == 'String') {
								alias = haxe.ds.StringMap;
							} else if (fullPath == 'Int') {
								alias = haxe.ds.IntMap;
							} else {
								var type:TypeInfo = null;
								var r = (Tools.resolve(fullPath, env) ?? baseInterp.imports.get(fullPath));
								if (r is Class) {
									type = TypeCollection.main.fromCompilePath(InsanityType.getClassName(r))[0];
								} else if (r == null) {
									throw Printer.errorToString(EUnknownType(fullPath));
								}
								
								if (type?.kind == 'class') {
									alias = haxe.ds.ObjectMap;
								}
							}
						default:
					}
					
					if (alias == null) {
						var p = new Printer();
						throw 'Map of type <${p.typeToString(params[0])}, ${p.typeToString(params[1])}> is not accepted';
					}
				} else {
					alias = baseInterp.resolve(fullPath);
				}
				
				if (alias == null)
					throw Printer.errorToString(EUnknownType(fullPath));
				
			default:
				#if debug trace('Non type-alias typedefs are not supported'); #end
		}
	}
	
	public function snapshot():Void {}
}

@:access(insanity.Module)
class InsanityScriptedEnum implements IInsanityType implements ICustomReflection implements ICustomEnumType {
	public var name:String;
	public var module:Module;
	public var pack:Array<String>;
	public var path:String;
	
	public var values:Array<String>;
	public var constructs:Map<String, EnumFieldDecl>;
	var constructFunctions:Map<String, Array<Dynamic> -> InsanityScriptedEnumValue>;
	
	var decl:EnumDecl;
	
	public var failed:Bool = false;
	public var initialized:Bool = false;
	public var initializing:Bool = false;
	
	public function new(decl:EnumDecl, ?module:Module) {
		this.name = decl.name;
		this.pack = (module?.pack ?? []);
		this.module = module;
		this.decl = decl;
		
		path = Tools.pathToString(name, pack);
	}
	
	public function init(?env:Environment, ?baseInterp:Interp, restore:Bool = true):Void {
		values = decl.names.copy();
		constructs = decl.constructs.copy();
		constructFunctions = new Map();
		
		for (name => construct in constructs) {
			var params = construct.arguments;
			if (params != null) {
				var minParams:Int = 0;
				for (i => p in params) {
					if (!p.opt) minParams = (i + 1);
				}
				
				constructFunctions.set(name, Reflect.makeVarArgs(function(args:Array<Dynamic>) {
					if (args.length < minParams) {
						var arg = params[args.length];
						var argType:String = arg.name;
						if (arg.t != null) argType += (':' + new Printer().typeToString(arg.t));
						
						throw 'Not enough arguments, expected $argType';
					}
					if (args.length > params.length && params.length > 0) {
						throw 'Too many arguments';
					}
					
					return new InsanityScriptedEnumValue(this, values.indexOf(name), args);
				}));
			}
		}
	}
	
	public function toString():String {
		return 'InsanityScriptedEnum<$path>';
	}
	
	public function typeGetEnumName():String { return path; }
	public function typeCreateEnum(constr:String, ?arguments:Array<Dynamic>):Dynamic {
		var construct:EnumFieldDecl = constructs.get(constr);
		if (construct != null) {
			if (constructFunctions.exists(constr)) {
				return Reflect.callMethod(this, constructFunctions.get(constr), arguments ?? []);
			} else {
				return new InsanityScriptedEnumValue(this, values.indexOf(constr));
			}
		}
		return null;
	}
	public function typeCreateEnumIndex(index:Int, ?arguments:Array<Dynamic>):Dynamic {
		return typeCreateEnum(values[index], arguments);
	}
	public function typeGetEnumConstructs():Array<String> {
		return (values?.copy() ?? []);
	}
	public function typeAllEnums():Array<Dynamic> {
		var enums:Array<InsanityScriptedEnumValue> = [];
		
		for (index => constr in values) {
			if (constructs.get(constr).arguments == null)
				enums.push(new InsanityScriptedEnumValue(this, index));
		}
		
		return enums;
	}
	
	public function reflectHasField(field:String):Bool { return false; }
	public function reflectGetField(field:String):Dynamic {
		var construct:EnumFieldDecl = constructs.get(field);
		if (construct != null) {
			if (constructFunctions.exists(field)) {
				return constructFunctions.get(field);
			} else {
				return new InsanityScriptedEnumValue(this, values.indexOf(field));
			}
		}
		return null;
	}
	public function reflectSetField(field:String, value:Dynamic):Dynamic { return null; }
	public function reflectGetProperty(property:String):Dynamic { return reflectGetField(property); }
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic { return null; }
	public function reflectListFields():Array<String> { return null; }
	
	public function snapshot():Void {}
}

class InsanityScriptedEnumValue implements ICustomEnumValueType {
	var base:InsanityScriptedEnum;
	
	public var index:Int;
	public var constructor:String;
	public var arguments:Array<Dynamic>;
	
	public function new(base:InsanityScriptedEnum, index:Int, ?arguments:Array<Dynamic>) {
		this.base = base;
		this.arguments = arguments;
		
		this.index = index;
		this.constructor = base.values[index];
	}
	
	public function toString():String {
		if (arguments != null) return '$constructor(${arguments.join(',')})';
		
		return constructor;
	}
	
	public function typeGetEnum():Dynamic { return base; }
	public function eq(o:ICustomEnumValueType):Bool {
		if (!(o is InsanityScriptedEnumValue)) return false;
		
		var o:InsanityScriptedEnumValue = cast o;
		if (o.base == base) {
			if (o.arguments == null && arguments == null) return true;
			
			for (i => argument in arguments) {
				if (argument != o.arguments[i])
					return false;
			}
			
			return true;
		}
		
		return false;
	}
}

@:access(insanity.backend.Interp)
class InsanityScriptedInterface implements IInsanityType implements IInsanityInterp implements ICustomReflection implements ICustomClassType {
	public var path:String;
	public var name:String;
	public var module:Module;
	public var pack:Array<String>;
	
	public var safe:Bool = false;
	
	public var interp:Interp;
	public var extending(default, null):Array<Dynamic>;
	
	var decl:InterfaceDecl;
	public var interfaceVariables:Array<FieldDecl> = [];
	
	public var failed:Bool = false;
	public var initialized:Bool = false;
	public var initializing:Bool = false;
	
	public function new(decl:InterfaceDecl, ?module:Module) {
		this.name = decl.name;
		this.pack = (module?.pack ?? []);
		this.module = module;
		this.decl = decl;
		
		path = Tools.pathToString(name, pack);
		
		interp = Type.createInstance(Config.interpClass, []);
		interp.canDefer = true;
		interp.origin = path;
	}
	
	public function init(?env:Environment, ?baseInterp:Interp, restore:Bool = true):Void {
		interp.environment = env;
		interp.setDefaults(true, baseInterp == null);
		
		if (baseInterp != null) {
			for (u in baseInterp.usings) interp.usings.push(u);
			for (k => i in baseInterp.imports) interp.imports.set(k, i);
		}
		
		interp.imports.set(name, this);
		
		interp.pushStack(insanity.backend.CallStack.StackItem.SModule(module?.path ?? name));
		
		safe = false;
		for (meta in decl.meta) safe = (safe || meta.name == ':safe');
		
		extending = [for (extend in decl.extend) switch (extend) {
			case CTPath(path, _):
				var p:String = path.join('.');
				
				var type:Dynamic = module?.interp.imports.get(p);
				type ??= interp.imports.get(p);
				type ??= Tools.resolve(p, interp.environment);
				
				if (type == null) throw 'Type not found: $p';
				
				try {
					var name:String = InsanityType.getClassName(type);
					if (name != null) {
						var type = (TypeCollection.main.fromCompilePath(name) ?? interp.environment?.types.fromCompilePath(name));
						
						if (!type[0].isInterface) throw 0;
					}
				} catch(e) {
					throw 'Should extend by using a class, found ${Type.typeof(type)}';
				}
				
				type;
			case null:
				null;
			default:
				throw 'Invalid extend ${decl.extend}';
				null;
		}];
		
		var knownFields:Array<String> = [];
		
		for (field in decl.fields) {
			var f:String = field.name;
			
			if (f == 'new') {
				throw 'An interface cannot have a constructor';
			} else if (field.access.contains(AInline)) {
				throw ('Invalid modifier: inline on ' + (field.kind.match(KVar(_)) ? 'non-static-variable' : 'method of interface'));
			} else if (field.access.contains(AStatic)) {
				throw 'You can only declare static fields in extern interfaces';
			} else if (field.access.contains(AOverride)) {
				throw 'Invalid modifier: override on field of class that has no parent';
			} else if (insanity.backend.macro.ScriptedMacro.ignoreFields.exists(f)) {
				throw 'Field $f reserved for internal use!!! - HScriptInsanity';
			} else if (knownFields.contains(f)) {
				throw 'Duplicate class field declaration: $name.$f';
			} else {
				knownFields.push(f);
			}
			
			interfaceVariables.push(field);
			knownFields.push(f);
		}
	}
	
	public function toString():String {
		return 'InsanityScriptedInterface<$path>';
	}
	
	public function typeCreateInstance(arguments:Array<Dynamic>):Dynamic {
		return typeCreateEmptyInstance();
	}
	public function typeCreateEmptyInstance():Dynamic {
		throw 'Can\'t initialize interface';
		return null;
	}
	public function typeGetClass():Dynamic {
		return null;
	}
	public function typeGetClassFields():Array<String> {
		return [];
	}
	@:access(insanity.backend.types.InsanityScriptedClass)
	public function typeGetInstanceFields():Array<String> {
		var fields:Array<String> = [];
		
		function getFields(c:Dynamic) {
			if (c is InsanityScriptedInterface) {
				var i:InsanityScriptedInterface = cast c;
				
				for (field in i.interfaceVariables) {
					if (!field.kind.match(KVar(_))) continue; // methods not listed apparently
					
					if (!fields.contains(field.name)) fields.push(field.name);
				}
				
				if (i.extending != null) {
					getFields(i.extending);
				}
			} else if (c is Class) {
				for (f in Type.getInstanceFields(c)) {
					if (!fields.contains(f) && !insanity.backend.macro.ScriptedMacro.ignoreFields.exists(f))
						fields.push(f);
				}
			}
		}
		
		getFields(this);
		
		return fields;
	}
	
	public function reflectHasField(field:String):Bool {
		return false;
	}
	public function reflectGetField(field:String):Dynamic {
		return null;
	}
	public function reflectSetField(field:String, value:Dynamic):Dynamic {
		return null;
	}
	public function reflectGetProperty(property:String):Dynamic {
		return null;
	}
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic {
		return null;
	}
	public function reflectListFields():Array<String> {
		return [];
	}
	
	public dynamic function onExpressionError(error:Dynamic, field:String, ?expr:Expr):Void {
		trace('Error on field $field of $path: $error');
	}
	public dynamic function onInstanceError(error:Dynamic, fun:String, ?instance:Dynamic):Void {
		trace('Error on function $fun of $path: $error');
	}
	
	public function snapshot():Void {}
}

@:access(insanity.backend.Interp)
@:access(insanity.backend.types.InsanityScriptedAbstractValue)
class InsanityScriptedAbstract extends InsanityAbstract implements IInsanityInterp implements IInsanityType {
	public var path:String;
	public var name:String;
	public var module:Module;
	public var pack:Array<String>;
	
	public var safe:Bool = false;
	public var snapshotAll:Bool = false;
	
	public var interp:Interp;
	
	var decl:AbstractDecl;
	
	public var failed:Bool = false;
	public var initialized:Bool = false;
	public var initializing:Bool = false;
	
	var __vars:Map<String, Variable> = [];
	
	public function new(decl:AbstractDecl, ?module:Module) {
		this.name = decl.name;
		this.pack = (module?.pack ?? []);
		this.module = module;
		this.decl = decl;
		
		path = Tools.pathToString(name, pack);
		
		interp = Type.createInstance(Config.interpClass, []);
		interp.canDefer = true;
		interp.origin = path;
		
		info = {
			isEnum: decl.isEnum,
			
			name: path,
			implName: path,
			underlying: null,
			forwards: [],
			
			methods: [],
			properties: [],
			overloads: [],
			
			from: [],
			to: []
		};
		
		super(info);
	}
	
	override function initEnumConstructors():Void {}
	
	function ctypeToAbstractTypeCast(type:Null<CType>):AbstractTypeCast {
		if (type == null) return null;
		
		return switch (type) {
			case CTPath(path, _):
				var p:String = path.join('.');
				
				var type:Dynamic = module?.interp.imports.get(p);
				type ??= interp.imports.get(p);
				type ??= Tools.resolve(p, interp.environment);
				
				if (type == null) throw 'Type not found: $p';
				
				var name:String;
				if (type is Class || type is ICustomClassType) {
					name = InsanityType.getClassName(type);
				} else if (type is Enum || type is ICustomEnumType) {
					name = InsanityType.getEnumName(type);
				} else {
					throw 'Type not found: $type';
				}
				
				(name == 'Dynamic' ? ATDynamic : ATType(name));
				
			case CTFun(_, _):
				ATMethod;
			
			default:
				throw '???'; null;
		};
	}
	
	public function init(?env:Environment, ?baseInterp:Interp, restore:Bool = true):Void {
		interp.environment = env;
		interp.setDefaults(true, baseInterp == null);
		
		if (baseInterp != null) {
			for (u in baseInterp.usings) interp.usings.push(u);
			for (k => i in baseInterp.imports) interp.imports.set(k, i);
			for (k => v in baseInterp.variables) if (!interp.variables.exists(k)) interp.variables.set(k, v);
		}
		
		interp.imports.set(name, this);
		
		interp.pushStack(insanity.backend.CallStack.StackItem.SModule(module?.path ?? name));
		
		safe = false;
		snapshotAll = false;
		
		for (meta in decl.meta) {
			safe = (safe || meta.name == ':safe');
			snapshotAll = (snapshotAll || meta.name == ':snapshot');
			
			if (meta.name != ':forward') continue;
			
			for (param in meta.params) {
				switch (param.e) {
					case EIdent(name): info.forwards.set(name, true);
					default:
				}
			}
		}
		
		info.underlying = ctypeToAbstractTypeCast(decl.underlying);
		
		info.from.set(info.underlying, null);
		info.to.set(info.underlying, null);
		
		for (from in decl.from) info.from.set(ctypeToAbstractTypeCast(from), null);
		for (to in decl.to) info.to.set(ctypeToAbstractTypeCast(to), null);
		
		var knownFields:Array<String> = [];
		
		for (field in decl.fields) {
			final f:String = field.name;
			
			if (f != 'new' && insanity.backend.macro.ScriptedMacro.ignoreFields.exists(f)) {
				throw 'Field $f reserved for internal use!!! - HScriptInsanity';
			} else if (knownFields.contains(f)) {
				throw 'Duplicate abstract field declaration: $name.$f';
			} else {
				if (field.access.contains(AOverride)) throw 'Invalid modifier: \'override\' override on field of class that has no parent';
				
				knownFields.push(f);
			}
			
			var l:Variable = {r: null, access: field.access};
			
			switch (field.kind) {
				default:
				case KVar(v):
					if (v.get != null) l.get = v.get;
					if (v.set != null) l.set = v.set;
					if (v.isFinal != null) l.isFinal = v.isFinal;
					
					if (field.access.contains(AInline)) l.isFinal = true;
					
					if (!isEnum && !field.access.contains(AStatic)) {
						if (v.get == 'default' && v.set == 'default')
							throw 'Cannot declare member variable in abstract';
						if ((v.get != 'get' && v.get != 'never') || (v.set != 'set' && v.set != 'never'))
							throw 'Member property accessors must be get/set or never';
					}
			}
			
			interp.locals.set(f, l);
		}
		
		var lastEnumValue:Dynamic = null;
		
		for (field in decl.fields) {
			final f:String = field.name;
			
			switch (field.kind) {
				case KFunction(fun):
					interp.locals.get(f).r = interp.buildFunction(f, fun.args, fun.expr, fun.ret, interp.locals);
					
					if (f == 'new') continue;
					
					final method:AbstractMethodInfo = {isStatic: field.access.contains(AStatic), setsSelf: false, returnsAbstract: false};
					
					for (meta in field.meta) {
						if (meta.name == ':op') {
							var op:AbstractOp;
							
							switch (meta.params[0].e) {
								case EBinop(binop, _, _):
									op = ABinop(binop, ctypeToAbstractTypeCast(fun.args[method.isStatic ? 1 : 0].t));
								
								case EUnop(unop, preFix, _):
									op = AUnop(unop, !preFix);
								
								case EField(_, _, _):
									final write:Bool = (fun.args.length == 2);
									op = AResolve(write, write ? ctypeToAbstractTypeCast(fun.args[1].t) : null);
								
								case EArrayDecl(_):
									final write:Bool = (fun.args.length == 2);
									op = AArray(write, ctypeToAbstractTypeCast(fun.args[0].t), write ? ctypeToAbstractTypeCast(fun.args[1].t) : null);
									
								default:
									throw '???';
							}
							
							// if (!method.isStatic && fun.args.length != 1) throw 'Member @:op functions must accept exactly one argument';
							// else if (method.isStatic && fun.args.length != 2) throw 'Static @:op functions must accept exactly two arguments';
							
							info.overloads.set(op, f);
						} else if (meta.name == ':commutative') {
							method.isCommutative = true;
						}
					}
					
					info.methods.set(f, method);
					
				case KVar(v):
					final isEnumValue:Bool = (isEnum &&
						!field.access.contains(AStatic) && !field.access.contains(APublic) &&
						(v.get == 'default' || v.get == null) && (v.set == 'default' || v.set == null));
					var enumValue:Dynamic = null;
					
					if (isEnumValue) {
						if (v.type != null) {
							final t:AbstractTypeCast = ctypeToAbstractTypeCast(v.type);
							final err:String = '${AbstractTools.abstractTypeCastToString(t)} should be ${AbstractTools.abstractTypeCastToString(info.underlying)}';
							
							switch (t) {
								case ATDynamic if (info.underlying != ATDynamic): throw err;
								case ATMethod if (info.underlying != ATMethod): throw err;
								case ATType(t) if (t != path): throw err;
								default:
							}
						}
						
						switch (info.underlying) {
							default:
								if (v.expr == null) throw 'Value required for field $f';
							
							case ATType('Int'):
								enumValue = (lastEnumValue == null ? 0 : lastEnumValue + 1);
								
							case ATType('String'):
								enumValue = f;
						}
					} else if (restore) {
						var snapshot:Bool = snapshotAll;
						if (!snapshot) for (meta in field.meta) snapshot = (snapshot || meta.name == ':snapshot');
						
						if (snapshot && Module.snapshots.exists(path)) {
							var fields:Map<String, Dynamic> = Module.snapshots.get(path);
							if (fields.exists(f)) {
								interp.locals.get(f).r = fields.get(f);
								continue;
							}
						}
					}
					
					try {
						var value:Dynamic = (v.expr == null ? (isEnumValue ? enumValue : null) : interp.exprReturn(v.expr, v.type));
						
						if (value is InsanityAbstractValue) {
							interp.locals.get(f).a = value;
							value = value.__a;
						}
						
						interp.locals.get(f).r = value;
						
						if (isEnum && value != null) lastEnumValue = value;
					} catch (d:Defer) {
						var signal = (env?.onInitialized ?? module.onInitialized);
						
						signal.push(function(_) {
							try {
								interp.locals.get(f).r = interp.exprReturn(v.expr/*, v.type*/);
							} catch (e:haxe.Exception) {
								onExpressionError(e, f, v.expr);
							}
							
							return false;
						});
					} catch (e:haxe.Exception) {
						onExpressionError(e, f, v.expr);
					}
					
					info.properties.set(f, {
						isStatic: (isEnumValue || field.access.contains(AStatic)),
						isAbstract: (v.type == null ? isEnumValue : switch (ctypeToAbstractTypeCast(v.type)) {
							case ATType(t): (t == path);
							default: false;
						}),
						isConstructor: isEnumValue,
						
						get: switch (v.get) {
							default: ADefault;
							case 'get' | 'dynamic': ADynamic;
							case 'never' | 'null': ANever;
						},
						set: (isEnumValue ? ANever : switch (v.set) {
							default: ADefault;
							case 'get' | 'dynamic': ADynamic;
							case 'never' | 'null': ANever;
						})
					});
					
					if (info.properties.get(f).isAbstract) interp.variables.set(f, MProperty(this, f));
			}
			
			__vars.set(f, interp.locals.get(f));
		}
		
		for (name => field in info.properties) {
			if (!field.isConstructor) continue;
		
			enumConstructors.push(name);
			enumValues.set(name, create(interp.locals.get(name).r));
		}
	}
	
	override function create(v:Dynamic):InsanityScriptedAbstractValue {
		return new InsanityScriptedAbstractValue(this, v is InsanityAbstractValue ? v.__a : v);
	}
	
	public function toString():String {
		return 'InsanityScriptedAbstract<$path>';
	}
	
	public function snapshot():Void {
		for (field in decl.fields) {
			var snapshot:Bool = snapshotAll;
			if (!snapshot) for (meta in field.meta) snapshot = (snapshot || meta.name == ':snapshot');
			if (!snapshot) continue;
			
			switch (field.kind) {
				case KFunction(_):
				case KVar(_):
					var fields:Map<String, Dynamic> = (Module.snapshots.get(path) ?? []);
					fields.set(field.name, interp.getLocal(field.name));
					Module.snapshots.set(path, fields);
			}
		}
	}
	
	public override function reflectHasField(field:String):Bool {
		return (__vars.exists(field));
	}
	public override function reflectGetField(field:String):Dynamic {
		if (isEnum && enumValues.exists(field)) return enumValues.get(field);
		
		var r = (__vars.exists(field) ? __vars.get(field).r : null);
		return (info.properties.get(field)?.isAbstract ? create(r) : r);
	}
	public override function reflectSetField(field:String, value:Dynamic):Dynamic {
		return (__vars.exists(field) ? __vars.get(field).r = value : null);
	}
	public override function reflectGetProperty(property:String):Dynamic {
		if (isEnum && enumValues.exists(property)) return enumValues.get(property);
		
		var r = (__vars.exists(property) ? interp.getLocal(property, __vars) : null);
		return (info.properties.get(property)?.isAbstract ? create(r) : r);
	}
	public override function reflectSetProperty(property:String, value:Dynamic):Dynamic {
		return (__vars.exists(property) ? interp.setLocal(property, value, __vars) : null);
	}
	
	public override function typeCreateInstance(arguments:Array<Dynamic>):Dynamic {
		if (!interp.locals.exists('new')) throw '$path does not have a constructor';
		
		final ab:InsanityScriptedAbstractValue = new InsanityScriptedAbstractValue(this, null);
		
		interp.variables.set('this', ab.__prop);
		final r:Dynamic = InsanityReflect.callMethod(this, interp.locals.get('new').r, arguments);
		interp.variables.set('this', null);
		
		return ab;
	}
	
	public dynamic function onExpressionError(error:Dynamic, field:String, ?expr:Expr):Void {
		trace('Error on field $field of $path: $error');
	}
	public dynamic function onInstanceError(error:Dynamic, fun:String, ?instance:Dynamic):Void {
		trace('Error on function $fun of $path: $error');
	}
}

@:access(insanity.backend.Interp)
class InsanityScriptedAbstractValue extends InsanityAbstractValue {
	var __prop:Mirror;
	var __base:InsanityScriptedAbstract;
	
	public function new(base:InsanityScriptedAbstract, value:Dynamic) {
		super(base, value);
		
		__base = cast base;
		__prop = MScriptAbstract(this);
		
		for (name in implFields.keys()) implFields.set(name, __base.interp.locals.get(name));
	}
	
	override function cacheMethod(field:String):Dynamic {
		var m:Null<AbstractMethodInfo> = info.methods.get(field);
		
		if (m == null || m.isStatic) {
			return null;
		} else {
			if (!methodCache.exists(field)) methodCache.set(field, Reflect.makeVarArgs((args) -> callImpl(field, args)));
			
			return methodCache.get(field);
		}
	}
	
	override function callImpl(field:String, arguments:Array<Dynamic>):Dynamic {
		__base.interp.variables.set('this', __prop);
		final r:Dynamic = InsanityReflect.callMethod(__base, implFields.get(field).r, arguments);
		__base.interp.variables.set('this', null);
		
		return r;
	}
	
	public override function reflectSetProperty(property:String, value:Dynamic):Dynamic {
		var f:Null<AbstractPropertyInfo> = info.properties.get(property);
		
		if (f != null && !f.isStatic) {
			return switch (f.get) {
				case ADefault: null;
				case ADynamic: callImpl('set_$property', [value]);
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
	
	public override function increment(prefix:Bool, delta:Int):Bool {
		final unop:AbstractOp = AUnop(delta > 0 ? '++' : '--', !prefix);
		
		return (op(unop) != null);
	}
	
	public override function op(op:AbstractOp, ?v:Dynamic, ?f:Dynamic):Dynamic {
		final field:Null<String> = findOverload(op, v, f);
		
		if (field == null) return null;
		
		var args = switch (op) {
			case ABinop(_, _): [v is InsanityAbstractValue ? v.__a : v];
			case AUnop(_, _): [];
			case AResolve(false, _) | AArray(false, _, _): [f];
			case AResolve(true, _) | AArray(true, _, _): [f, v is InsanityAbstractValue ? v.__a : v];
		};
		
		if (info.methods.get(field).isStatic) args.unshift(__a);
		
		return callImpl(field, args);
	}
}

class InsanityDummyClass {}

interface IInsanityInterp {
	public var interp:Interp;
}

interface IInsanityType {
	public var name:String;
	public var module:Module;
	public var pack:Array<String>;
	public var path:String;
	
	public var failed:Bool;
	public var initialized:Bool;
	public var initializing:Bool;
	
	public function init(?env:Environment, ?baseInterp:Interp, restore:Bool = true):Void;
	public function snapshot():Void;
}

@:autoBuild(insanity.backend.macro.ScriptedMacro.build())
interface IInsanityScripted extends ICustomReflection extends ICustomClassType {
	private var __scriptedBase:InsanityScriptedClass;
	private var __interp:insanity.backend.Interp;
	private var __interpSafe:Bool;
	// private var __vars:Map<String, insanity.backend.Interp.Variable>;
	
	private var __func:String;
	private var __fields:Array<String>;
}

enum Defer {
	DDefer;
}